local commands = require("wrt.commands")
local config = require("wrt.config")
local env = require("wrt.env")
local pickers = require("wrt.pickers")
local state = require("wrt.state")
local ui = require("wrt.ui")
local worktree = require("wrt.worktree")

local M = {}

--------------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------------

--- Open the worktree picker with the configured backend.
---@param opts? table backend-specific picker options
function M.pick(opts)
  return pickers.pick(opts)
end

--- Switch to a worktree by allocation name or by item.
---@param target string|wrt.Worktree
---@param opts? { from?: string, notify?: boolean }
function M.switch(target, opts)
  local root, err = state.root()
  if not root then
    return ui.error(err or "no wrt managed root")
  end
  local item = target
  if type(target) == "string" then
    item = worktree.find(root, state.slug(target))
    if not item then
      return ui.error(("unknown worktree: %s"):format(target))
    end
  end
  return worktree.switch(item, vim.tbl_extend("force", { root = root }, opts or {}))
end

--- Prompt for a name plus optional flags and run `wrt new`.
function M.create()
  return commands.create()
end

--- Create without prompting.
---@param name string
---@param flags? string[]
function M.create_named(name, flags)
  return commands.create_named(name, flags)
end

--- Remove a worktree, asking which flags to use.
---@param target? string|wrt.Worktree defaults to the worktree containing the cwd
function M.remove(target)
  if target == nil then
    return commands.remove_current()
  end
  local root, err = state.root()
  if not root then
    return ui.error(err or "no wrt managed root")
  end
  local item = type(target) == "string" and worktree.find(root, state.slug(target)) or target
  if not item then
    return ui.error(("unknown worktree: %s"):format(tostring(target)))
  end
  return commands.remove(item, root)
end

---@param root? wrt.Root
---@return wrt.Worktree[]
function M.list(root)
  return worktree.list(root)
end

---@return wrt.Worktree|nil
function M.current()
  return worktree.current()
end

---@return wrt.Worktree|nil
function M.main()
  return worktree.main()
end

function M.goto_main()
  return commands.goto_main()
end

--- The managed root containing `path`, or nil plus a reason.
---@param path? string
---@return wrt.Root|nil, string|nil
function M.root(path)
  return state.root(path)
end

--- Mirror of the CLI's slug(), for predicting directory and allocation names.
---@param name string
---@return string
function M.slug(name)
  return state.slug(name)
end

--- Push a worktree's `wrt env` into vim.env.
---@param target? string|wrt.Worktree defaults to the worktree containing the cwd
---@param opts? { notify?: boolean }
function M.apply_env(target, opts)
  if target == nil then
    return commands.apply_env_current()
  end
  local root, err = state.root()
  if not root then
    return ui.error(err or "no wrt managed root")
  end
  local item = type(target) == "string" and worktree.find(root, state.slug(target)) or target
  if not item then
    return ui.error(("unknown worktree: %s"):format(tostring(target)))
  end
  return env.apply(item, root, opts or { notify = true })
end

--- Restore the environment values that apply_env replaced.
function M.restore_env()
  return env.restore()
end

function M.prune()
  return commands.prune()
end

---@param apply? boolean delete branches instead of a dry run
function M.housekeeping(apply)
  return commands.housekeeping(apply)
end

function M.status()
  return commands.status()
end

--- `wrt init` — Codex-assisted `.wrt.json` discovery.
function M.discover()
  return commands.discover()
end

function M.clone()
  return commands.clone()
end

--- Interactive shell inside a worktree.
---@param target? string|wrt.Worktree
function M.shell(target)
  if target == nil then
    return commands.shell_current()
  end
  return M.with_root(function(root)
    local item = type(target) == "string" and worktree.find(root, state.slug(target)) or target
    return item and commands.shell(item, root)
  end)
end

--- Prompt for a command and run it inside a worktree.
---@param target? string|wrt.Worktree
function M.run(target)
  if target == nil then
    return commands.run_current()
  end
  return M.with_root(function(root)
    local item = type(target) == "string" and worktree.find(root, state.slug(target)) or target
    return item and commands.run(item, root)
  end)
end

--- Database task picker (reset/seed/migrate).
---@param target? string|wrt.Worktree
function M.db(target)
  if target == nil then
    return commands.db_current()
  end
  return M.with_root(function(root)
    local item = type(target) == "string" and worktree.find(root, state.slug(target)) or target
    return item and commands.db(item, root)
  end)
end

M.with_root = worktree.with_root
M.with_current = worktree.with_current

--------------------------------------------------------------------------------
-- keymaps
--------------------------------------------------------------------------------

--- Named actions, usable as keymap targets and remappable by name.
---@type table<string, { desc: string, fn: fun() }>
M.actions = {
  pick = { desc = "Worktrees (switch)", fn = M.pick },
  create = { desc = "New worktree", fn = M.create },
  remove_current = { desc = "Remove current worktree", fn = commands.remove_current },
  goto_main = { desc = "Go to main worktree", fn = M.goto_main },
  prune = { desc = "Prune missing worktrees", fn = M.prune },
  housekeeping_dry = {
    desc = "Housekeeping (dry run)",
    fn = function()
      M.housekeeping(false)
    end,
  },
  housekeeping_apply = {
    desc = "Housekeeping (apply)",
    fn = function()
      M.housekeeping(true)
    end,
  },
  status = { desc = "Root status", fn = M.status },
  discover = { desc = "Discover .wrt.json (codex)", fn = M.discover },
  clone = { desc = "Clone a new managed root", fn = M.clone },
  apply_env_current = { desc = "Apply worktree env", fn = commands.apply_env_current },
  shell_current = { desc = "Shell in worktree", fn = commands.shell_current },
  run_current = { desc = "Run command in worktree", fn = commands.run_current },
  db_current = { desc = "Database task", fn = commands.db_current },
}

--- Suffix -> action, appended to `keymap_prefix`. Enabled by `keymaps = true`.
M.DEFAULT_KEYMAPS = {
  w = "pick",
  W = "pick",
  n = "create",
  x = "remove_current",
  m = "goto_main",
  p = "prune",
  h = "housekeeping_dry",
  H = "housekeeping_apply",
  s = "status",
  i = "discover",
  c = "clone",
  e = "apply_env_current",
  t = "shell_current",
  r = "run_current",
  d = "db_current",
}

---@param cfg wrt.Config
local function set_keymaps(cfg)
  if not cfg.keymaps then
    return
  end
  local maps = vim.deepcopy(M.DEFAULT_KEYMAPS)
  if type(cfg.keymaps) == "table" then
    maps = vim.tbl_extend("force", maps, cfg.keymaps)
  end
  local unknown = {}
  for suffix, name in pairs(maps) do
    if name then
      local action = M.actions[name]
      if action then
        vim.keymap.set("n", cfg.keymap_prefix .. suffix, action.fn, { desc = action.desc })
      else
        unknown[#unknown + 1] = ("%s -> %s"):format(suffix, tostring(name))
      end
    end
  end
  if #unknown > 0 then
    ui.error("unknown keymap actions:\n" .. table.concat(unknown, "\n"))
  end
  if cfg.which_key then
    local ok, wk = pcall(require, "which-key")
    if ok and type(wk.add) == "function" then
      wk.add({ { cfg.keymap_prefix, group = cfg.which_key_group } })
    end
  end
end

--------------------------------------------------------------------------------
-- setup
--------------------------------------------------------------------------------

--- Wire up the plugin. Everything with a side effect happens here; requiring
--- any wrt module on its own does nothing observable.
---@param opts? table
function M.setup(opts)
  local cfg = config.setup(opts)
  require("wrt.cli").clear_cache()
  if pickers.available("snacks") then
    require("wrt.pickers.snacks").register()
  end
  set_keymaps(cfg)
end

return M
