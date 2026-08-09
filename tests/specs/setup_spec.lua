--- setup(), the opt-in keymaps and the public API surface.
return function(h)
  h.spec("setup")

  local config = require("wrt.config")
  local wrt = require("wrt")

  --- Every normal-mode mapping whose description belongs to a wrt action.
  local function wrt_maps()
    local descs = {}
    for _, action in pairs(wrt.actions) do
      descs[action.desc] = true
    end
    local found = {}
    for _, map in ipairs(vim.api.nvim_get_keymap("n")) do
      if map.desc and descs[map.desc] then
        found[#found + 1] = map
      end
    end
    return found
  end

  local function clear_maps()
    for _, map in ipairs(wrt_maps()) do
      pcall(vim.keymap.del, "n", map.lhs)
    end
  end

  ---@param prefix string
  ---@return string
  local function translate(prefix)
    local leader = vim.g.mapleader or "\\"
    return (prefix:gsub("<leader>", leader))
  end

  ----------------------------------------------------------------------------
  -- no side effects at require time
  ----------------------------------------------------------------------------
  clear_maps()
  config.reset()
  package.loaded["wrt"] = nil
  wrt = require("wrt")
  h.eq(#wrt_maps(), 0, "requiring wrt does not define any keymaps")

  ----------------------------------------------------------------------------
  -- keymaps are opt-in
  ----------------------------------------------------------------------------
  config.reset()
  wrt.setup({})
  h.eq(#wrt_maps(), 0, "setup() without options defines no keymaps")

  config.reset()
  wrt.setup({ keymaps = true })
  local maps = wrt_maps()
  h.eq(#maps, 15, "keymaps = true defines all fifteen mappings")

  local prefix = translate("<leader>W")
  local all_prefixed = true
  for _, map in ipairs(maps) do
    if map.lhs:sub(1, #prefix) ~= prefix then
      all_prefixed = false
    end
  end
  h.check(all_prefixed, "every mapping sits under the configured prefix")

  local by_lhs = {}
  for _, map in ipairs(maps) do
    by_lhs[map.lhs] = map.desc
  end
  h.eq(by_lhs[prefix .. "w"], "Worktrees (switch)", "w opens the picker")
  h.eq(by_lhs[prefix .. "W"], "Worktrees (switch)", "W also opens the picker")
  h.eq(by_lhs[prefix .. "n"], "New worktree", "n creates a worktree")
  h.eq(by_lhs[prefix .. "x"], "Remove current worktree", "x removes the current worktree")
  h.eq(by_lhs[prefix .. "m"], "Go to main worktree", "m goes to main")
  h.eq(by_lhs[prefix .. "p"], "Prune missing worktrees", "p prunes")
  h.eq(by_lhs[prefix .. "h"], "Housekeeping (dry run)", "h is the dry run")
  h.eq(by_lhs[prefix .. "H"], "Housekeeping (apply)", "H applies")
  h.eq(by_lhs[prefix .. "s"], "Root status", "s shows root status")
  h.eq(by_lhs[prefix .. "i"], "Discover .wrt.json (codex)", "i runs discovery")
  h.eq(by_lhs[prefix .. "c"], "Clone a new managed root", "c clones")
  h.eq(by_lhs[prefix .. "e"], "Apply worktree env", "e applies the env")
  h.eq(by_lhs[prefix .. "t"], "Shell in worktree", "t opens a shell")
  h.eq(by_lhs[prefix .. "r"], "Run command in worktree", "r runs a command")
  h.eq(by_lhs[prefix .. "d"], "Database task", "d opens the db menu")

  ----------------------------------------------------------------------------
  -- prefix is configurable
  ----------------------------------------------------------------------------
  clear_maps()
  config.reset()
  wrt.setup({ keymaps = true, keymap_prefix = "<leader>gw" })
  maps = wrt_maps()
  h.eq(#maps, 15, "a custom prefix still defines fifteen mappings")
  local custom = translate("<leader>gw")
  local custom_ok = true
  for _, map in ipairs(maps) do
    if map.lhs:sub(1, #custom) ~= custom then
      custom_ok = false
    end
  end
  h.check(custom_ok, "every mapping moved to the custom prefix")

  ----------------------------------------------------------------------------
  -- per-entry overrides
  ----------------------------------------------------------------------------
  clear_maps()
  config.reset()
  wrt.setup({ keymaps = { x = false } })
  maps = wrt_maps()
  h.eq(#maps, 14, "an entry set to false is dropped")
  by_lhs = {}
  for _, map in ipairs(maps) do
    by_lhs[map.lhs] = map.desc
  end
  h.eq(by_lhs[prefix .. "x"], nil, "the dropped mapping is gone")
  h.eq(by_lhs[prefix .. "w"], "Worktrees (switch)", "the other defaults survive")

  clear_maps()
  config.reset()
  wrt.setup({ keymaps = { z = "goto_main" } })
  maps = wrt_maps()
  h.eq(#maps, 16, "an extra entry is added on top of the defaults")
  by_lhs = {}
  for _, map in ipairs(maps) do
    by_lhs[map.lhs] = map.desc
  end
  h.eq(by_lhs[prefix .. "z"], "Go to main worktree", "the extra mapping uses the named action")

  clear_maps()
  config.reset()
  local captured = h.capture_notify()
  wrt.setup({ keymaps = { q = "does_not_exist" } })
  captured.restore()
  h.matches(captured.text(), "unknown keymap actions", "an unknown action name is reported")
  h.matches(captured.text(), "q %-> does_not_exist", "the report names the offending entry")

  clear_maps()
  config.reset()

  ----------------------------------------------------------------------------
  -- action registry consistency
  ----------------------------------------------------------------------------
  for suffix, name in pairs(wrt.DEFAULT_KEYMAPS) do
    h.truthy(wrt.actions[name], ("default keymap %q maps to a real action (%s)"):format(suffix, name))
  end
  for name, action in pairs(wrt.actions) do
    h.eq(type(action.fn), "function", ("action %s has a function"):format(name))
    h.eq(type(action.desc), "string", ("action %s has a description"):format(name))
  end

  ----------------------------------------------------------------------------
  -- public API surface
  ----------------------------------------------------------------------------
  local api = {
    "setup",
    "pick",
    "switch",
    "create",
    "create_named",
    "remove",
    "list",
    "current",
    "main",
    "goto_main",
    "root",
    "slug",
    "apply_env",
    "restore_env",
    "prune",
    "housekeeping",
    "status",
    "discover",
    "clone",
    "shell",
    "run",
    "db",
    "with_root",
    "with_current",
  }
  for _, name in ipairs(api) do
    h.eq(type(wrt[name]), "function", ("require('wrt').%s is a function"):format(name))
  end

  ----------------------------------------------------------------------------
  -- :Wrt is registered and idempotent
  ----------------------------------------------------------------------------
  h.eq(vim.fn.exists(":Wrt"), 2, ":Wrt is defined")
  h.eq(vim.g.loaded_wrt, true, "the plugin guard is set")
  local ok, err = pcall(vim.cmd, "source " .. vim.g.wrt_test_root .. "/plugin/wrt.lua")
  h.check(ok, "re-sourcing plugin/wrt.lua is safe: " .. tostring(err))
  h.eq(vim.fn.exists(":Wrt"), 2, ":Wrt survives re-sourcing")

  local command = vim.api.nvim_get_commands({})["Wrt"]
  if h.truthy(command, ":Wrt is introspectable") then
    h.eq(command.nargs, "*", ":Wrt accepts any number of arguments")
  end

  config.reset()
end
