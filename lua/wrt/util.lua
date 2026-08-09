---@class wrt.Root
---@field managed_root string  absolute path of the managed root (parent of the bare .git)
---@field main string|nil      absolute path of the default-branch checkout
---@field common_dir string    absolute path of the bare git common dir
---@field state_path string    absolute path of .git/.wrt/state.json
---@field state table          decoded state.json

---@class wrt.Worktree
---@field name string       allocation key (slug); the primary checkout is always "main"
---@field branch string
---@field path string
---@field block integer
---@field offset integer
---@field status string     "active"|"creating"|"failed"
---@field created_at string|nil
---@field supabase string   "none"|"owner"|"isolated"|"shared:<owner>"
---@field is_main boolean

local M = {}

local uv = vim.uv

--- Resolve symlinks, falling back to the input when resolution fails.
--- macOS needs this: /var is a symlink to /private/var and git resolves it, so
--- state.json paths and getcwd() can describe the same directory differently.
---@param path string|nil
---@return string|nil
function M.realpath(path)
  return path and (uv.fs_realpath(path) or path) or nil
end

---@param path string
---@return boolean
function M.exists(path)
  return uv.fs_stat(path) ~= nil
end

---@param path string
---@return string|nil
function M.read_file(path)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local stat = uv.fs_fstat(fd)
  local data = stat and uv.fs_read(fd, stat.size, 0) or nil
  uv.fs_close(fd)
  return data
end

---@param path string
---@return table|nil
function M.read_json(path)
  local data = M.read_file(path)
  if not data then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, data)
  return ok and type(decoded) == "table" and decoded or nil
end

--- Relative path of `path` inside `dir`, "" when identical, nil when outside.
---@param path string|nil
---@param dir string|nil
---@return string|nil
function M.rel_under(path, dir)
  if not path or not dir or dir == "" then
    return nil
  end
  if path == dir then
    return ""
  end
  if path:sub(1, #dir + 1) == dir .. "/" then
    return path:sub(#dir + 2)
  end
  return nil
end

--- Walk up from `start` and resolve the git common dir. Works from the bare
--- managed root (.git is a directory) as well as from inside any linked
--- worktree (.git is a file containing `gitdir: <path>/worktrees/<name>`).
---@param start string
---@return string|nil
function M.find_common_dir(start)
  local dir = vim.fs.normalize(start)
  while dir and dir ~= "" do
    local git = dir .. "/.git"
    local stat = uv.fs_stat(git)
    if stat then
      if stat.type == "directory" then
        return git
      end
      local content = stat.type == "file" and M.read_file(git) or nil
      local gitdir = content and content:match("gitdir:%s*([^\r\n]+)")
      if gitdir then
        gitdir = vim.trim(gitdir)
        if not gitdir:match("^/") then
          gitdir = vim.fs.normalize(dir .. "/" .. gitdir)
        end
        return gitdir:match("^(.*)/worktrees/[^/]+$") or gitdir
      end
      return nil
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      return nil
    end
    dir = parent
  end
end

--- Pad or truncate to an exact display width. Replaces Snacks.picker.util.align
--- so the formatter works with every picker backend.
---@param str string|nil
---@param width integer
---@param opts? { truncate?: boolean, align?: "left"|"right" }
---@return string
function M.align(str, width, opts)
  opts = opts or {}
  str = tostring(str or "")
  local w = vim.api.nvim_strwidth(str)
  if w > width then
    if not opts.truncate then
      return str
    end
    local chars = vim.fn.strchars(str)
    while chars > 0 and w > width do
      chars = chars - 1
      str = vim.fn.strcharpart(str, 0, chars)
      w = vim.api.nvim_strwidth(str)
    end
    return str .. string.rep(" ", width - w)
  end
  local pad = string.rep(" ", width - w)
  return opts.align == "right" and (pad .. str) or (str .. pad)
end

return M
