--- :checkhealth wrt — reported content and a real end-to-end run.
return function(h)
  h.spec("health")

  local config = require("wrt.config")
  local health = require("wrt.health")
  local state = require("wrt.state")

  local fx = h.shared_fixture()

  --- Swap vim.health for a recorder.
  ---@return table
  local function record()
    local original = vim.health
    local log = { sections = {}, entries = {} }
    local function push(kind)
      return function(msg, extra)
        log.entries[#log.entries + 1] = { kind = kind, msg = msg, extra = extra }
      end
    end
    vim.health = {
      start = function(name)
        log.sections[#log.sections + 1] = name
      end,
      ok = push("ok"),
      warn = push("warn"),
      error = push("error"),
      info = push("info"),
    }
    log.restore = function()
      vim.health = original
    end
    log.text = function()
      return table.concat(
        vim.tbl_map(function(entry)
          return entry.kind .. ": " .. tostring(entry.msg) .. " " .. vim.inspect(entry.extra or "")
        end, log.entries),
        "\n"
      )
    end
    log.kinds = function(pattern)
      local kinds = {}
      for _, entry in ipairs(log.entries) do
        if tostring(entry.msg):match(pattern) then
          kinds[#kinds + 1] = entry.kind
        end
      end
      return kinds
    end
    return log
  end

  ----------------------------------------------------------------------------
  -- inside a managed root
  ----------------------------------------------------------------------------
  local previous_cwd = vim.uv.cwd()
  vim.api.nvim_set_current_dir(fx.main)
  config.reset()

  local log = record()
  health.check()
  log.restore()
  local text = log.text()

  h.eq(log.sections[1], "wrt.nvim", "the first health section is the plugin")
  h.truthy(#log.sections >= 3, "health is split into sections")
  h.matches(text, "ok: `wrt` found: ", "health reports the resolved wrt path")
  h.matches(text, "ok: `wrt help` exits 0", "health probes that the binary runs")
  h.matches(text, "git version", "health reports the git version")
  h.matches(text, "ok: state version 3 matches %(expected 3%)", "health reports state version compatibility")
  h.matches(text, "ok: managed root: ", "health reports the managed root")
  h.matches(text, "ok: main worktree: ", "health reports the main worktree")
  h.matches(text, "3 tracked worktrees", "health counts the worktrees")
  h.matches(text, "cwd is inside `main`", "health reports the current worktree")
  h.matches(text, "ok: picker: ", "health reports the picker backend")
  h.matches(text, "optional: telescope", "health reports optional picker backends")
  h.matches(text, "optional: fzf%-lua", "health reports fzf-lua availability")
  h.matches(text, "optional: which%-key", "health reports which-key availability")
  h.matches(text, "Neovim ", "health reports the Neovim version")
  h.eq(log.kinds("Neovim "), { "ok" }, "a supported Neovim version is an ok")

  ----------------------------------------------------------------------------
  -- outside a managed root
  ----------------------------------------------------------------------------
  vim.api.nvim_set_current_dir(fx.src)
  log = record()
  health.check()
  log.restore()
  text = log.text()
  h.matches(text, "warn: not a wrt managed root", "health warns when the cwd is not a managed root")
  h.matches(text, "wrt root init", "the warning suggests how to create one")
  h.matches(text, "ok: `wrt` found", "health still reports the binary outside a managed root")

  ----------------------------------------------------------------------------
  -- unsupported state version
  ----------------------------------------------------------------------------
  local util = require("wrt.util")
  local state_path = fx.root .. "/.git/.wrt/state.json"
  local original = util.read_file(state_path)
  h.write_file(state_path, (original:gsub('"version": 3', '"version": 42', 1)))
  vim.api.nvim_set_current_dir(fx.main)

  log = record()
  health.check()
  log.restore()
  text = log.text()
  h.matches(text, "error: state version 42 is unsupported", "health errors on an unsupported state version")
  h.matches(text, "recreate the managed root", "the error says how to fix it")

  h.write_file(state_path, original)
  h.truthy(state.root(fx.root), "the fixture state file was restored")

  ----------------------------------------------------------------------------
  -- a configured but unavailable backend is flagged
  ----------------------------------------------------------------------------
  local pickers = require("wrt.pickers")
  if not pickers.available("fzf-lua") then
    config.reset()
    config.setup({ picker = "fzf-lua" })
    log = record()
    health.check()
    log.restore()
    h.matches(log.text(), "warn: `fzf%-lua` is not available, falling back to `select`", "health flags a fallback")
    config.reset()
  end

  ----------------------------------------------------------------------------
  -- the real :checkhealth wrt must run without error
  ----------------------------------------------------------------------------
  vim.api.nvim_set_current_dir(fx.main)
  local ok, err = pcall(vim.cmd, "checkhealth wrt")
  h.check(ok, ":checkhealth wrt runs without error: " .. tostring(err))
  if ok then
    local lines = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    h.matches(lines, "wrt.nvim", "the health buffer contains the plugin section")
    h.matches(lines, "managed root", "the health buffer reports the managed root")
    h.falsy(lines:match("ERROR"), "a healthy setup reports no errors")
  end

  h.clean_buffers()
  config.reset()
  vim.api.nvim_set_current_dir(previous_cwd)
end
