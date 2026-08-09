local cli = require("wrt.cli")
local config = require("wrt.config")

local M = {}

--- Values that a previous apply() overwrote. `false` means "was unset".
--- An empty string is truthy in Lua, so genuinely empty values round-trip.
---@type table<string, string|false>|nil
M.backup = nil

--- Generation counter. Switching faster than `wrt env` completes must not let
--- an older callback clobber a newer worktree's environment.
---@type integer
M.seq = 0

--- Undo the CLI's sh_quote: '...' with '\'' standing in for an embedded quote.
---@param value string
---@return string
function M.sh_unquote(value)
  if #value >= 2 and value:sub(1, 1) == "'" and value:sub(-1) == "'" then
    value = value:sub(2, -2):gsub("'\\''", "'")
  end
  return value
end

--- Parse `wrt env` stdout (`export KEY='value'` lines) into a table.
---@param stdout string|nil
---@return table<string, string>
function M.parse(stdout)
  local env = {}
  for line in (stdout or ""):gmatch("[^\r\n]+") do
    local key, value = line:match("^export%s+([%w_]+)=(.*)$")
    if key then
      env[key] = M.sh_unquote(value)
    end
  end
  return env
end

--- Fetch a worktree's environment. Runs at the managed root, which is always a
--- valid cwd for the CLI even when the worktree directory is gone.
---@param name string
---@param root wrt.Root
---@param cb fun(env: table<string, string>|nil, err?: string)
function M.get(name, root, cb)
  cli.system({ "env", name }, { cwd = root.managed_root }, function(res)
    if res.code ~= 0 then
      return cb(nil, cli.detail(res))
    end
    cb(M.parse(res.stdout))
  end)
end

--- Put back the values a previous apply() replaced.
function M.restore()
  for key, previous in pairs(M.backup or {}) do
    vim.env[key] = previous or nil
  end
  M.backup = nil
end

--- Push a worktree's env into vim.env so terminals, tasks and LSP children
--- inherit its port block. Values replaced by an earlier call are restored
--- first, so environments never accumulate across switches.
---
--- `wrt env` legitimately fails when a Supabase-bound worktree's stack is not
--- running, which happens routinely while switching; that is why the failure
--- path only warns when notifications are requested.
---@param item wrt.Worktree
---@param root wrt.Root
---@param opts? { notify?: boolean }
function M.apply(item, root, opts)
  opts = opts or {}
  local notify = opts.notify
  if notify == nil then
    notify = config.get().env.notify
  end

  M.seq = M.seq + 1
  local seq = M.seq
  M.get(item.name, root, function(env, err)
    if seq ~= M.seq then
      return
    end
    local ui = require("wrt.ui")
    if not env then
      M.restore()
      if notify then
        ui.warn(("`wrt env %s` failed\n%s"):format(item.name, err or ""))
      end
      return
    end
    M.restore()
    local backup, count = {}, 0
    for key, value in pairs(env) do
      backup[key] = vim.env[key] or false
      vim.env[key] = value
      count = count + 1
    end
    M.backup = backup
    if notify then
      ui.info(("applied %d env vars from `%s`"):format(count, item.name))
    end
  end)
end

--- Test seam.
function M.reset()
  M.backup = nil
  M.seq = 0
end

return M
