--- Headless test harness. No external dependencies: specs are plain functions
--- that record assertions, and async work is driven with vim.wait.
local M = {}

M.stats = { passed = 0, failed = 0 }
M.failures = {}

local spec_name = "?"
local spec_counts = {}

---@param name string
function M.spec(name)
  spec_name = name
  spec_counts[name] = spec_counts[name] or { passed = 0, failed = 0 }
end

function M.spec_summary()
  return spec_counts
end

---@param cond any
---@param msg string
---@return boolean
function M.check(cond, msg)
  local counts = spec_counts[spec_name] or { passed = 0, failed = 0 }
  spec_counts[spec_name] = counts
  if cond then
    M.stats.passed = M.stats.passed + 1
    counts.passed = counts.passed + 1
    return true
  end
  M.stats.failed = M.stats.failed + 1
  counts.failed = counts.failed + 1
  M.failures[#M.failures + 1] = ("[%s] %s"):format(spec_name, msg)
  return false
end

function M.eq(actual, expected, msg)
  if vim.deep_equal(actual, expected) then
    return M.check(true, msg)
  end
  return M.check(
    false,
    ("%s\n      expected: %s\n      actual:   %s"):format(msg, vim.inspect(expected), vim.inspect(actual))
  )
end

function M.truthy(value, msg)
  return M.check(value ~= nil and value ~= false, msg .. " (got " .. vim.inspect(value) .. ")")
end

function M.falsy(value, msg)
  return M.check(value == nil or value == false, msg .. " (got " .. vim.inspect(value) .. ")")
end

function M.matches(str, pattern, msg)
  local ok = type(str) == "string" and str:match(pattern) ~= nil
  return M.check(ok, ("%s\n      pattern: %s\n      actual:  %s"):format(msg, pattern, vim.inspect(str)))
end

--- Block until `pred` is true. Records a failure on timeout.
---@param pred fun(): boolean
---@param msg string
---@param timeout? integer
---@return boolean
function M.wait(pred, msg, timeout)
  local ok = vim.wait(timeout or 30000, pred, 20)
  return M.check(ok, "timed out waiting for " .. msg)
end

--------------------------------------------------------------------------------
-- process helpers
--------------------------------------------------------------------------------

---@param cmd string[]
---@param opts? table
---@return vim.SystemCompleted
function M.sh(cmd, opts)
  return vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait()
end

---@return string
function M.wrt_bin()
  local exe = require("wrt.cli").exe()
  assert(exe, "wrt binary not found; the suite needs a real wrt install")
  return exe
end

---@param args string[]
---@param cwd string
---@return vim.SystemCompleted
function M.wrt(args, cwd)
  local cmd = { M.wrt_bin() }
  vim.list_extend(cmd, args)
  return M.sh(cmd, { cwd = cwd })
end

--------------------------------------------------------------------------------
-- fixtures
--------------------------------------------------------------------------------

local fixtures = {}

---@param path string
---@param content string
local function write_file(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local fd = assert(vim.uv.fs_open(path, "w", 420))
  vim.uv.fs_write(fd, content, 0)
  vim.uv.fs_close(fd)
end

M.write_file = write_file

--- Build a real managed root with `wrt`. Commits are made with signing off
--- because a signing global config cannot prompt in a headless run.
---
--- Each entry of `specs` is either a name or `{ name, extra args... }`. Names
--- whose normalized branch would be illegal to git (a colon, for example) must
--- pass an explicit `--branch`.
---@param specs? (string|string[])[]
---@return { dir: string, src: string, root: string, main: string, names: string[] }
function M.fixture(specs)
  specs = specs or {}
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local src = dir .. "/src"
  vim.fn.mkdir(src, "p")

  write_file(src .. "/README.md", "one\ntwo\nthree\n")
  write_file(src .. "/lib/a.lua", "return 1\n")
  write_file(src .. "/lib/b.lua", "return 2\n")

  local git = {
    "git",
    "-c",
    "commit.gpgsign=false",
    "-c",
    "user.name=wrt test",
    "-c",
    "user.email=wrt@test.local",
    "-c",
    "init.defaultBranch=main",
  }

  local function run_git(args)
    local cmd = vim.deepcopy(git)
    vim.list_extend(cmd, args)
    local res = M.sh(cmd, { cwd = src })
    assert(res.code == 0, "git " .. table.concat(args, " ") .. " failed: " .. tostring(res.stderr))
  end

  run_git({ "init", "-q", "-b", "main" })
  run_git({ "config", "commit.gpgsign", "false" })
  run_git({ "config", "user.name", "wrt test" })
  run_git({ "config", "user.email", "wrt@test.local" })
  run_git({ "add", "-A" })
  run_git({ "commit", "-q", "-m", "init" })

  local root = dir .. "/root"
  local res =
    M.wrt({ "root", "init", src, "--root", root, "--install", "false", "--supabase", "false", "--db", "false" }, dir)
  assert(res.code == 0, "wrt root init failed: " .. tostring(res.stderr))
  M.sh({ "git", "--git-dir", root .. "/.git", "config", "commit.gpgsign", "false" })

  local names = {}
  for _, spec in ipairs(specs) do
    local entry = type(spec) == "table" and spec or { spec }
    local name = entry[1]
    names[#names + 1] = name
    local args = { "new", name }
    for i = 2, #entry do
      args[#args + 1] = entry[i]
    end
    vim.list_extend(args, { "--install", "false", "--supabase", "none", "--db", "false" })
    local created = M.wrt(args, root)
    assert(created.code == 0, ("wrt new %s failed: %s"):format(name, tostring(created.stderr)))
  end

  local fixture = { dir = dir, src = src, root = root, main = root .. "/main", names = names }
  fixtures[#fixtures + 1] = fixture
  return fixture
end

local shared
--- One managed root reused by the read-only specs.
---@return { dir: string, src: string, root: string, main: string, names: string[] }
function M.shared_fixture()
  if not shared then
    shared = M.fixture({ { "Agent 07: retry queue", "--branch", "agent/retry" }, "feature/demo" })
  end
  return shared
end

function M.cleanup()
  for _, fixture in ipairs(fixtures) do
    vim.fn.delete(fixture.dir, "rf")
  end
  fixtures = {}
  shared = nil
end

--------------------------------------------------------------------------------
-- stubs
--------------------------------------------------------------------------------

--- Capture notifications emitted through wrt.ui.
---@return { list: table[], restore: fun() }
function M.capture_notify()
  local original = vim.notify
  local captured = { list = {} }
  vim.notify = function(msg, level, opts)
    captured.list[#captured.list + 1] = { msg = msg, level = level, opts = opts }
  end
  captured.restore = function()
    vim.notify = original
  end
  captured.text = function()
    return table.concat(
      vim.tbl_map(function(entry)
        return entry.msg
      end, captured.list),
      "\n"
    )
  end
  return captured
end

--- Answer the next vim.ui.input with `value` (nil cancels).
---@param value string|nil
---@return fun() restore
function M.stub_input(value)
  local original = vim.ui.input
  vim.ui.input = function(_, cb)
    cb(value)
  end
  return function()
    vim.ui.input = original
  end
end

--- Answer vim.ui.select by picking the entry `chooser` returns.
---@param chooser fun(items: any[]): any
---@return fun() restore
function M.stub_select(chooser)
  local original = vim.ui.select
  vim.ui.select = function(items, _, cb)
    local choice = chooser(items)
    local idx
    for i, item in ipairs(items) do
      if item == choice then
        idx = i
      end
    end
    cb(choice, idx)
  end
  return function()
    vim.ui.select = original
  end
end

--- Replace wrt.ui.terminal so specs can drive on_exit without a real terminal.
---@param handler fun(args: string[], opts: table)
---@return fun() restore
function M.stub_terminal(handler)
  local ui = require("wrt.ui")
  local original = ui.terminal
  ui.terminal = function(args, opts)
    return handler(args, opts or {})
  end
  return function()
    ui.terminal = original
  end
end

--- Reset all mutable module state between specs.
function M.reset_state()
  require("wrt.config").reset()
  require("wrt.cli").clear_cache()
  require("wrt.env").reset()
  require("wrt.git").clear()
end

--- Close every buffer and window except one scratch buffer.
function M.clean_buffers()
  vim.cmd("silent! only")
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), scratch)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= scratch and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

return M
