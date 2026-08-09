local config = require("wrt.config")
local util = require("wrt.util")

local M = {}

--- Every subcommand clap accepts, for `:Wrt` completion. There is deliberately
--- no `status` here: managed-root status is `wrt root status`.
M.SUBCOMMANDS = {
  "add",
  "clone",
  "completions",
  "db",
  "env",
  "help",
  "housekeeping",
  "init",
  "ls",
  "new",
  "path",
  "prune",
  "remove",
  "rm",
  "root",
  "run",
}

local cache = { key = nil, path = nil }

--- Absolute path of the `wrt` binary, or nil. Honours `opts.bin`, then $PATH,
--- then the default cargo install location.
---@return string|nil
function M.exe()
  local configured = config.get().bin
  local key = configured or ""
  if cache.key ~= key then
    cache.key = key
    local found
    if configured and configured ~= "" then
      local expanded = vim.fs.normalize(configured)
      found = util.exists(expanded) and expanded or nil
    else
      local on_path = vim.fn.exepath("wrt")
      if on_path ~= "" then
        found = on_path
      else
        local cargo = vim.fs.normalize("~/.cargo/bin/wrt")
        found = util.exists(cargo) and cargo or nil
      end
    end
    cache.path = found
  end
  return cache.path
end

function M.clear_cache()
  cache = { key = nil, path = nil }
end

--- Message shown when the binary is missing.
---@return string
function M.missing_message()
  return "`wrt` was not found\ninstall it with: cargo install --git https://github.com/pascalporedda/wrt-cli"
end

--- Combined stderr+stdout, trimmed. wrt logs diagnostics to stderr.
---@param res vim.SystemCompleted
---@return string
function M.detail(res)
  return vim.trim((res.stderr or "") .. (res.stdout or ""))
end

--- `wrt run` and `wrt db` forward the child's exit code, so a nonzero status
--- does not prove wrt itself failed. Its own errors are always prefixed.
---@param res vim.SystemCompleted
---@return boolean
function M.is_wrt_error(res)
  return (res.stderr or ""):match("^%[wrt%] ERROR:") ~= nil
end

--- Run wrt in the background. `cb` receives the completed result on the main
--- loop. Without `cb`, a nonzero exit is reported to the user.
---@param args string[]
---@param opts? { cwd?: string }
---@param cb? fun(res: vim.SystemCompleted)
---@return vim.SystemObj|nil
function M.system(args, opts, cb)
  local exe = M.exe()
  if not exe then
    local res = { code = 127, signal = 0, stdout = "", stderr = M.missing_message() }
    vim.schedule(function()
      if cb then
        cb(res)
      else
        require("wrt.ui").error(M.missing_message())
      end
    end)
    return nil
  end
  local cmd = { exe }
  vim.list_extend(cmd, args)
  return vim.system(cmd, { cwd = (opts or {}).cwd, text = true }, function(res)
    vim.schedule(function()
      if cb then
        cb(res)
      elseif res.code ~= 0 then
        require("wrt.ui").error(("wrt %s failed (exit %d)\n%s"):format(args[1] or "", res.code, M.detail(res)))
      end
    end)
  end)
end

--- Split a command-line-ish string into argv, honouring quotes and backslash
--- escapes. Backslashes are literal inside single quotes, like sh.
---@param str string
---@return string[]
function M.tokenize(str)
  local args, buf, quote, escaped = {}, nil, nil, false
  for ch in str:gmatch(".") do
    if escaped then
      buf, escaped = (buf or "") .. ch, false
    elseif ch == "\\" and quote ~= "'" then
      escaped = true
    elseif quote then
      if ch == quote then
        quote = nil
      else
        buf = (buf or "") .. ch
      end
    elseif ch == '"' or ch == "'" then
      quote, buf = ch, buf or ""
    elseif ch:match("%s") then
      if buf then
        args[#args + 1], buf = buf, nil
      end
    else
      buf = (buf or "") .. ch
    end
  end
  if buf then
    args[#args + 1] = buf
  end
  return args
end

--- Partition a `wrt new` prompt into a name and trailing flags. Everything
--- before the first `-flag` belongs to the name, so multi-word names need no
--- quoting: `Agent 07: retry queue --branch agent/retry` yields one positional.
---@param str string
---@return string name, string[] flags
function M.split_name_and_flags(str)
  local name_parts, flags = {}, {}
  for _, token in ipairs(M.tokenize(str)) do
    if #flags == 0 and token:sub(1, 1) ~= "-" then
      name_parts[#name_parts + 1] = token
    else
      flags[#flags + 1] = token
    end
  end
  return table.concat(name_parts, " "), flags
end

--- Build argv for `wrt run`. The CLI requires `--` at raw argv index 3, which
--- means exactly one positional before it.
---@param name string
---@param command string[]
---@return string[]
function M.run_args(name, command)
  local args = { "run", name, "--" }
  vim.list_extend(args, command)
  return args
end

return M
