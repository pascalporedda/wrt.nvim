local git = require("wrt.git")
local util = require("wrt.util")

local M = {}

M.NAME_WIDTH = 32
M.BRANCH_WIDTH = 28

--- Fuzzy-match text. snacks requires a `text` field on every item or matching
--- errors on the first keystroke.
---@param wt wrt.Worktree
---@return string
function M.text(wt)
  return wt.name .. " " .. wt.branch
end

---@param wt wrt.Worktree
---@return string
local function dirty_glyph(wt)
  local dirty = git.dirty[wt.path]
  if dirty == "dirty" then
    return "±"
  end
  return dirty == "clean" and "" or "…"
end

---@param wt wrt.Worktree
---@return string
local function meta(wt)
  local parts = { ("block %d/%d"):format(wt.block, wt.offset) }
  if wt.supabase ~= "none" then
    parts[#parts + 1] = "sb:" .. wt.supabase
  end
  if wt.status ~= "active" then
    parts[#parts + 1] = wt.status
  end
  return table.concat(parts, "  ")
end

--- One-line rendering for pickers without highlight support.
---@param item { wt: wrt.Worktree, current?: boolean }
---@return string
function M.plain(item)
  local wt = item.wt
  return table.concat({
    item.current and "● " or "  ",
    util.align(wt.name, M.NAME_WIDTH, { truncate = true }),
    " ",
    util.align(wt.branch, M.BRANCH_WIDTH, { truncate = true }),
    util.align(dirty_glyph(wt), 2),
    meta(wt),
  })
end

--- snacks.picker highlight list.
---@param item snacks.picker.Item
---@return snacks.picker.Highlight[]
function M.snacks(item)
  local wt = item.wt ---@type wrt.Worktree
  local ret = {}

  ret[#ret + 1] = { item.current and "● " or "  ", "SnacksPickerGitBranchCurrent", virtual = true }
  ret[#ret + 1] = {
    util.align(wt.name, M.NAME_WIDTH, { truncate = true }),
    wt.is_main and "SnacksPickerSpecial" or "SnacksPickerLabel",
  }
  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { util.align(wt.branch, M.BRANCH_WIDTH, { truncate = true }), "SnacksPickerGitBranch" }

  local dirty = git.dirty[wt.path]
  ret[#ret + 1] = {
    util.align(dirty_glyph(wt), 2),
    dirty == "dirty" and "DiagnosticWarn" or "SnacksPickerDimmed",
    virtual = true,
  }

  ret[#ret + 1] = {
    col = 0,
    virt_text = { { meta(wt), wt.status == "active" and "SnacksPickerDimmed" or "DiagnosticError" } },
    virt_text_pos = "right_align",
    hl_mode = "combine",
  }
  return ret
end

--- Markdown preview body. Git sections appear once wrt.git has cached them.
---@param wt wrt.Worktree
---@return string[]
function M.preview_lines(wt)
  local lines = {
    "# " .. wt.name,
    "",
    "branch    `" .. wt.branch .. "`",
    "path      `" .. wt.path .. "`",
    "ports     block " .. wt.block .. ", offset " .. wt.offset,
    "supabase  " .. wt.supabase,
    "status    " .. wt.status,
  }
  if wt.created_at then
    lines[#lines + 1] = "created   " .. wt.created_at
  end
  local info = git.cache[wt.path]
  if not info then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "_loading git info…_"
    return lines
  end
  if info.status and #info.status > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## status"
    lines[#lines + 1] = "```"
    vim.list_extend(lines, info.status)
    lines[#lines + 1] = "```"
  end
  if info.log and #info.log > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## commits"
    lines[#lines + 1] = "```"
    vim.list_extend(lines, info.log)
    lines[#lines + 1] = "```"
  end
  return lines
end

return M
