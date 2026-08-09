local cli = require("wrt.cli")
local util = require("wrt.util")

local M = {}

--- state.json schema version this plugin understands. The CLI treats a
--- mismatch as a hard error, so refusing to guess is the right behaviour here.
M.STATE_VERSION = 3

M.LAYOUT = "managed-root"

--- Mirror of the CLI's `slug()`: worktree directory names and allocation keys.
--- Lowercase, runs of non-alphanumerics collapsed to `-`, trimmed, empty
--- becomes "wrt".
---@param name string
---@return string
function M.slug(name)
  local out = vim.trim(name):lower():gsub("[^a-z0-9]+", "-")
  out = out:gsub("^%-+", ""):gsub("%-+$", "")
  return out == "" and "wrt" or out
end

--- Mirror of the CLI's `normalize_branch()`. Unlike slug this preserves case
--- and slashes, strips a `refs/heads/` prefix, and only collapses whitespace.
---@param name string
---@return string
function M.normalize_branch(name)
  local s = vim.trim(name)
  s = s:gsub("^refs/heads/", "")
  local parts = {}
  for word in s:gmatch("%S+") do
    parts[#parts + 1] = word
  end
  return table.concat(parts, "-")
end

--- Resolve the managed root containing `path` (defaults to the cwd).
--- Returns nil plus a human-readable reason when `path` is not inside one.
---@param path? string
---@return wrt.Root|nil, string|nil
function M.root(path)
  if not cli.exe() then
    return nil, cli.missing_message()
  end
  local common = util.find_common_dir(path or vim.uv.cwd())
  if not common then
    return nil, "not inside a git repository"
  end
  local state_path = common .. "/.wrt/state.json"
  local state = util.read_json(state_path)
  if not state then
    return nil, "not a wrt managed root — use `wrt clone <url>` or `wrt root init <src> --root <dir>`"
  end
  if state.version ~= M.STATE_VERSION then
    return nil,
      ("unsupported wrt state version %s (expected %d) — recreate the managed root"):format(
        tostring(state.version),
        M.STATE_VERSION
      )
  end
  if type(state.root) ~= "table" or state.root.layout ~= M.LAYOUT then
    return nil, "not a wrt managed root"
  end
  return {
    managed_root = state.root.managedRoot or vim.fs.dirname(common),
    main = state.root.mainWorktree,
    common_dir = common,
    state_path = state_path,
    state = state,
  }
end

return M
