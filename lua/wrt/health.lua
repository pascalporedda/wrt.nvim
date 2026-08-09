local cli = require("wrt.cli")
local config = require("wrt.config")
local pickers = require("wrt.pickers")
local state = require("wrt.state")
local util = require("wrt.util")
local worktree = require("wrt.worktree")

local M = {}

--- Resolved on every call so the reporter can be swapped in tests.
local function reporter()
  return vim.health
end

local function check_neovim()
  if vim.fn.has("nvim-0.11") == 1 then
    reporter().ok("Neovim " .. tostring(vim.version()))
  else
    reporter().error("Neovim >= 0.11 is required (vim.system, vim.uv, jobstart term)")
  end
end

local function check_binaries()
  local exe = cli.exe()
  if not exe then
    reporter().error("`wrt` not found", {
      "cargo install --git https://github.com/pascalporedda/wrt-cli",
      "or set `opts.bin` to an absolute path",
    })
  else
    reporter().ok("`wrt` found: " .. exe)
    -- The CLI has no --version (disable_version_flag), so `help` is the only
    -- portable liveness probe.
    local res = vim.system({ exe, "help" }, { text = true }):wait()
    if res.code == 0 then
      reporter().ok("`wrt help` exits 0 (binary is runnable)")
    else
      reporter().error(("`wrt help` exited %d"):format(res.code), { vim.trim(res.stderr or "") })
    end
  end

  if vim.fn.executable("git") == 1 then
    local res = vim.system({ "git", "--version" }, { text = true }):wait()
    reporter().ok(vim.trim(res.stdout or "git found"))
  else
    reporter().error("`git` not found on $PATH")
  end
end

local function check_root()
  local cwd = vim.uv.cwd()
  local common = util.find_common_dir(cwd)
  if not common then
    reporter().warn("cwd is not inside a git repository: " .. tostring(cwd))
    return
  end

  local state_path = common .. "/.wrt/state.json"
  local raw = util.read_json(state_path)
  if not raw then
    reporter().warn("not a wrt managed root (no " .. state_path .. ")", {
      "create one with `wrt clone <url>` or `wrt root init <src> --root <dir>`",
    })
    return
  end

  if raw.version == state.STATE_VERSION then
    reporter().ok(("state version %d matches (expected %d)"):format(raw.version, state.STATE_VERSION))
  else
    reporter().error(
      ("state version %s is unsupported (expected %d)"):format(tostring(raw.version), state.STATE_VERSION),
      { "recreate the managed root with a matching wrt version" }
    )
    return
  end

  local root, err = state.root(cwd)
  if not root then
    reporter().error("managed root not usable: " .. tostring(err))
    return
  end

  reporter().ok("managed root: " .. root.managed_root)
  reporter().ok("main worktree: " .. tostring(root.main))
  local items = worktree.list(root)
  reporter().ok(("%d tracked worktree%s"):format(#items, #items == 1 and "" or "s"))
  local current = worktree.current(root)
  if current then
    reporter().ok(("cwd is inside `%s` (%s)"):format(current.name, current.branch))
  else
    reporter().info("cwd is not inside a tracked worktree (the managed root itself is fine)")
  end
end

local function check_pickers()
  local configured = config.get().picker
  local resolved = pickers.resolve()
  reporter().ok(("picker: %s (configured: %s)"):format(resolved, configured))
  if configured ~= "auto" and configured ~= resolved then
    reporter().warn(("`%s` is not available, falling back to `%s`"):format(configured, resolved))
  end
  for _, name in ipairs(pickers.BACKENDS) do
    if name ~= "select" then
      if pickers.available(name) then
        reporter().ok("optional: " .. name .. " available")
      else
        reporter().info("optional: " .. name .. " not installed")
      end
    end
  end
  local ok = pcall(require, "which-key")
  reporter().info("optional: which-key " .. (ok and "available" or "not installed"))
end

function M.check()
  reporter().start("wrt.nvim")
  check_neovim()
  check_binaries()
  reporter().start("wrt.nvim: managed root")
  check_root()
  reporter().start("wrt.nvim: ui")
  check_pickers()
end

return M
