local config = require("wrt.config")

local M = {}

--- path -> "dirty"|"clean"|"?"  ("?" when git could not be queried)
---@type table<string, string>
M.dirty = {}

--- path -> { status?: string[], log?: string[] }
---@type table<string, { status?: string[], log?: string[] }>
M.cache = {}

function M.clear()
  M.dirty, M.cache = {}, {}
end

---@param res vim.SystemCompleted
---@return string[]|nil
local function lines(res)
  if res.code ~= 0 then
    return nil
  end
  return vim.split(vim.trim(res.stdout or ""), "\n", { trimempty = true })
end

--- Fill M.dirty for the given worktrees, then call `cb` exactly once.
--- Runs one `git status --porcelain` per worktree in parallel.
---@param items wrt.Worktree[]
---@param cb? fun()
function M.refresh_dirty(items, cb)
  local pending = #items
  if pending == 0 then
    return cb and cb()
  end
  for _, item in ipairs(items) do
    vim.system({ "git", "-C", item.path, "status", "--porcelain" }, { text = true }, function(res)
      M.dirty[item.path] = res.code ~= 0 and "?" or ((res.stdout or "") ~= "" and "dirty" or "clean")
      pending = pending - 1
      if pending == 0 and cb then
        vim.schedule(cb)
      end
    end)
  end
end

--- Populate M.cache[path] with the short status and recent commits, then call
--- `cb` once. The cache is filled even if `cb` decides not to redraw.
---@param path string
---@param cb? fun(info: { status?: string[], log?: string[] })
function M.info(path, cb)
  local info, pending = {}, 2
  local function done()
    pending = pending - 1
    if pending > 0 then
      return
    end
    M.cache[path] = info
    if cb then
      vim.schedule(function()
        cb(info)
      end)
    end
  end
  vim.system({ "git", "-C", path, "status", "--short" }, { text = true }, function(res)
    info.status = lines(res)
    done()
  end)
  local count = tostring(config.get().git.log_count)
  vim.system({ "git", "-C", path, "log", "--oneline", "--decorate", "-n", count }, { text = true }, function(res)
    info.log = lines(res)
    done()
  end)
end

return M
