local config = require("wrt.config")
local env = require("wrt.env")
local state = require("wrt.state")
local util = require("wrt.util")

local M = {}

---@param alloc table
---@return string
local function supabase_label(alloc)
  local sb = alloc.supabase
  if type(sb) ~= "table" then
    return "none"
  end
  if sb.mode == "owned" then
    return alloc.name == "main" and "owner" or "isolated"
  end
  if sb.mode == "shared" then
    return "shared:" .. (sb.owner or "?")
  end
  return "none"
end

--- Tracked worktrees, main first, then alphabetical.
---@param root? wrt.Root
---@return wrt.Worktree[]
function M.list(root)
  root = root or (state.root())
  if not root then
    return {}
  end
  local items = {} ---@type wrt.Worktree[]
  for key, alloc in pairs(root.state.allocations or {}) do
    local name = alloc.name or key
    items[#items + 1] = {
      name = name,
      branch = alloc.branch or "",
      path = alloc.path or "",
      block = alloc.block or 0,
      offset = alloc.offset or 0,
      status = alloc.status or "?",
      created_at = alloc.createdAt,
      supabase = supabase_label(alloc),
      is_main = name == "main",
    }
  end
  table.sort(items, function(a, b)
    if a.is_main ~= b.is_main then
      return a.is_main
    end
    return a.name < b.name
  end)
  return items
end

--- The worktree containing `cwd`. Paths are compared both literally and after
--- symlink resolution because git canonicalises and macOS symlinks /var.
---@param root? wrt.Root
---@param cwd? string
---@return wrt.Worktree|nil
function M.current(root, cwd)
  cwd = vim.fs.normalize(cwd or vim.uv.cwd())
  local resolved = util.realpath(cwd)
  for _, item in ipairs(M.list(root)) do
    if util.rel_under(cwd, item.path) or util.rel_under(resolved, util.realpath(item.path)) then
      return item
    end
  end
end

--- The primary checkout. Its allocation key is always "main" even though its
--- directory is named after the default branch.
---@param root? wrt.Root
---@return wrt.Worktree|nil
function M.main(root)
  for _, item in ipairs(M.list(root)) do
    if item.is_main then
      return item
    end
  end
end

---@param root wrt.Root|nil
---@param name string
---@return wrt.Worktree|nil
function M.find(root, name)
  for _, item in ipairs(M.list(root)) do
    if item.name == name then
      return item
    end
  end
end

--- Move listed file buffers to the same relative path in another worktree.
--- Window layout and cursor positions are preserved; buffers whose counterpart
--- does not exist are closed; modified buffers are left alone and counted.
---@param from string
---@param to string
---@return { moved: integer, dropped: integer, dirty: integer }
function M.migrate_buffers(from, to)
  local from_resolved = util.realpath(from)
  local moves, drops = {}, {}
  local stats = { moved = 0, dropped = 0, dirty = 0 }

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
      local name = vim.api.nvim_buf_get_name(buf)
      local rel = name ~= "" and (util.rel_under(name, from) or util.rel_under(util.realpath(name), from_resolved))
        or nil
      if rel and rel ~= "" then
        if vim.bo[buf].modified then
          stats.dirty = stats.dirty + 1
        elseif util.exists(to .. "/" .. rel) then
          moves[#moves + 1] = { buf = buf, target = to .. "/" .. rel }
        else
          drops[#drops + 1] = buf
        end
      end
    end
  end

  local wins_by_buf = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    wins_by_buf[buf] = wins_by_buf[buf] or {}
    table.insert(wins_by_buf[buf], win)
  end

  for _, move in ipairs(moves) do
    local target = vim.fn.bufadd(move.target)
    vim.bo[target].buflisted = true
    for _, win in ipairs(wins_by_buf[move.buf] or {}) do
      local cursor = vim.api.nvim_win_get_cursor(win)
      vim.api.nvim_win_set_buf(win, target)
      if not pcall(vim.api.nvim_win_set_cursor, win, cursor) then
        local last = vim.api.nvim_buf_line_count(target)
        pcall(vim.api.nvim_win_set_cursor, win, { math.min(cursor[1], last), 0 })
      end
    end
    if pcall(vim.api.nvim_buf_delete, move.buf, { force = false }) then
      stats.moved = stats.moved + 1
    end
  end

  local blank
  for _, buf in ipairs(drops) do
    local wins = wins_by_buf[buf] or {}
    if #wins > 0 then
      blank = blank or vim.api.nvim_create_buf(true, false)
      for _, win in ipairs(wins) do
        vim.api.nvim_win_set_buf(win, blank)
      end
    end
    if pcall(vim.api.nvim_buf_delete, buf, { force = false }) then
      stats.dropped = stats.dropped + 1
    end
  end

  return stats
end

--- Make `item` the active worktree: migrate buffers, cd, refresh env, then fire
--- `User WrtSwitch` with `data = { name, path, branch }`.
---
--- Pass `opts.from` when the current directory is about to disappear (removing
--- the active worktree), because the source path cannot be re-derived then.
---@param item wrt.Worktree
---@param opts? { root?: wrt.Root, from?: string, notify?: boolean }
---@return { moved: integer, dropped: integer, dirty: integer }|nil
function M.switch(item, opts)
  opts = opts or {}
  local ui = require("wrt.ui")
  local cfg = config.get()
  local root = opts.root or (state.root())
  if not util.exists(item.path) then
    return ui.error(("worktree path is gone: %s\nrun `wrt prune`"):format(item.path))
  end

  local from = opts.from
  if from == nil then
    local current = M.current(root)
    from = current and current.path or nil
  end

  local stats = nil
  if cfg.switch.migrate_buffers and from and from ~= item.path then
    stats = M.migrate_buffers(from, item.path)
  end

  vim.api.nvim_set_current_dir(item.path)
  if cfg.switch.clear_jumps then
    vim.cmd.clearjumps()
  end
  if root and cfg.switch.apply_env then
    env.apply(item, root)
  end

  local notify = opts.notify
  if notify == nil then
    notify = cfg.switch.notify
  end
  if notify then
    local msg = ("%s  (%s)"):format(item.name, item.branch)
    if stats then
      msg = msg .. ("\n%d buffers moved, %d closed, %d kept (modified)"):format(stats.moved, stats.dropped, stats.dirty)
    end
    ui.info(msg)
  end

  vim.api.nvim_exec_autocmds("User", {
    pattern = "WrtSwitch",
    data = { name = item.name, path = item.path, branch = item.branch },
  })
  return stats
end

--- Run `fn` with a resolved managed root, reporting why if there is none.
---@generic T
---@param fn fun(root: wrt.Root): T
---@return T|nil
function M.with_root(fn)
  local root, err = state.root()
  if not root then
    return require("wrt.ui").error(err or "no wrt managed root")
  end
  return fn(root)
end

--- Run `fn` with the worktree containing the cwd.
---@generic T
---@param fn fun(item: wrt.Worktree, root: wrt.Root): T
---@return T|nil
function M.with_current(fn)
  return M.with_root(function(root)
    local item = M.current(root)
    if not item then
      return require("wrt.ui").error("the cwd is not inside a wrt worktree")
    end
    return fn(item, root)
  end)
end

return M
