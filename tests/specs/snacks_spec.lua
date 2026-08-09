--- Real snacks.picker integration. Skipped unless WRT_TEST_SNACKS points at a
--- snacks.nvim checkout; the rest of the suite deliberately runs without it.
return function(h)
  h.spec("snacks")

  if not vim.g.wrt_test_snacks then
    print("  snacks: WRT_TEST_SNACKS not set, real-picker specs skipped")
    return
  end

  local config = require("wrt.config")
  local git = require("wrt.git")
  local pickers = require("wrt.pickers")
  local state = require("wrt.state")
  local util = require("wrt.util")
  local worktree = require("wrt.worktree")

  require("snacks").setup({
    picker = { enabled = true },
    notifier = { enabled = false },
    input = { enabled = false },
    dashboard = { enabled = false },
    explorer = { enabled = false },
    indent = { enabled = false },
    scroll = { enabled = false },
    statuscolumn = { enabled = false },
    quickfile = { enabled = false },
    words = { enabled = false },
  })

  h.truthy(_G.Snacks, "the Snacks global exists")
  h.truthy(_G.Snacks.picker, "Snacks.picker is available")
  h.eq(pickers.available("snacks"), true, "the snacks backend is detected")

  config.reset()
  h.eq(pickers.resolve(), "snacks", "auto resolves to snacks when it is installed")

  local fx = h.shared_fixture()
  local root = assert(state.root(fx.root))
  local demo = assert(worktree.find(root, "feature-demo"))
  vim.api.nvim_set_current_dir(fx.main)

  -- The default snacks layout drops the preview pane in a narrow window, and
  -- headless Neovim starts at 80x24.
  vim.o.columns = 200
  vim.o.lines = 50

  ----------------------------------------------------------------------------
  -- source registration
  ----------------------------------------------------------------------------
  require("wrt.pickers.snacks").register()
  h.eq(type(Snacks.picker.wrt), "function", "register() exposes Snacks.picker.wrt()")

  ----------------------------------------------------------------------------
  -- a real picker opens, finds and renders
  ----------------------------------------------------------------------------
  config.reset()
  config.setup({ picker = "snacks", switch = { notify = false, apply_env = false } })

  git.clear()
  local picker = pickers.pick()
  if not h.truthy(picker, "the snacks picker opened") then
    return
  end

  h.wait(function()
    return picker:count() >= 3
  end, "the picker to find every worktree")
  h.eq(picker:count(), 3, "the picker lists three worktrees")

  local names = {}
  for _, item in ipairs(picker:items()) do
    names[#names + 1] = item.wt.name
  end
  h.eq(names, { "main", "agent-07-retry-queue", "feature-demo" }, "the picker keeps the list ordering")

  local rendered = vim.api.nvim_buf_get_lines(picker.list.win.buf, 0, -1, false)
  local rendered_text = table.concat(rendered, "\n")
  h.matches(rendered_text, "main", "the list renders the main worktree")
  h.matches(rendered_text, "feature%-demo", "the list renders the feature worktree")
  h.matches(rendered_text, "agent/retry", "the list renders branch names")

  -- matching must not error on the first keystroke (this needs item.text)
  -- picker:count() is the finder total; the filtered count lives on the list.
  local ok_match = pcall(function()
    picker.input:set("feature")
  end)
  h.check(ok_match, "typing a query does not error")
  h.wait(function()
    return picker.list:count() == 1
  end, "the query to filter down to one worktree", 5000)
  h.eq(picker.list:count(), 1, "fuzzy matching works on the text field")
  h.eq(picker:count(), 3, "the finder still holds every worktree")

  -- the match text carries the branch too, not just the name
  picker.input:set("agent/retry")
  h.wait(function()
    return picker.list:count() == 1
  end, "a branch-only query to match", 5000)
  h.eq(picker.list:count(), 1, "worktrees can be found by branch name")

  ----------------------------------------------------------------------------
  -- an action on the real picker
  ----------------------------------------------------------------------------
  vim.fn.setreg('"', "")
  vim.fn.setreg("+", "")
  picker.input:set("feature")
  h.wait(function()
    return picker.list:count() == 1
  end, "the feature worktree to be the only match", 5000)

  local captured = h.capture_notify()
  picker:action("wrt_yank")
  captured.restore()
  h.wait(function()
    return vim.fn.getreg('"') ~= ""
  end, "the yank action to fill the register")
  h.eq(util.realpath(vim.fn.getreg('"')), util.realpath(demo.path), "wrt_yank copies the worktree path")
  h.matches(captured.text(), "yanked", "wrt_yank reports what it copied")
  h.eq(picker.closed, true, "the action closed the picker")

  ----------------------------------------------------------------------------
  -- confirm switches worktree
  ----------------------------------------------------------------------------
  git.clear()
  picker = pickers.pick()
  h.wait(function()
    return picker:count() >= 3
  end, "the picker to reopen")
  picker.input:set("feature-demo")
  h.wait(function()
    return picker.list:count() == 1
  end, "the feature worktree to be selected", 5000)

  picker:action("confirm")
  h.wait(function()
    return util.realpath(vim.uv.cwd()) == util.realpath(demo.path)
  end, "confirm to switch worktree")
  h.eq(util.realpath(vim.uv.cwd()), util.realpath(demo.path), "confirming an item switches to that worktree")
  h.eq(picker.closed, true, "confirming closed the picker")

  ----------------------------------------------------------------------------
  -- the real preview renders into a real window
  ----------------------------------------------------------------------------
  git.clear()
  vim.api.nvim_set_current_dir(fx.main)
  picker = pickers.pick()
  h.wait(function()
    return picker:count() >= 3
  end, "the picker to reopen for the preview test")
  h.wait(function()
    return picker.preview and picker.preview.win and picker.preview.win:valid()
  end, "the preview window to open", 10000)

  -- Headless Neovim never fires the list-cursor event that normally triggers the
  -- preview, so drive it explicitly. Everything below is the real snacks
  -- preview window rendering this plugin's preview function.
  h.eq(picker:current({ resolve = false }).wt.name, "main", "the picker has a current item")
  picker.preview:show(picker, { force = true })

  local preview_lines = vim.api.nvim_buf_get_lines(picker.preview.win.buf, 0, -1, false)
  local preview_text = table.concat(preview_lines, "\n")
  h.matches(preview_text, "^# main", "the preview renders a markdown heading with the name")
  h.matches(preview_text, "branch    `main`", "the preview shows the branch")
  h.matches(preview_text, "ports     block 0, offset 0", "the preview shows the port block")
  h.matches(preview_text, "supabase  none", "the preview shows the supabase mode")

  h.wait(function()
    picker.preview:show(picker, { force = true })
    local text = table.concat(vim.api.nvim_buf_get_lines(picker.preview.win.buf, 0, -1, false), "\n")
    return text:match("## commits") ~= nil
  end, "the async git preview to land in the real window", 10000)
  h.matches(
    table.concat(vim.api.nvim_buf_get_lines(picker.preview.win.buf, 0, -1, false), "\n"),
    "## commits",
    "the commit log reaches the real preview buffer"
  )

  picker:close()
  h.wait(function()
    return picker.closed
  end, "the picker to close")

  config.reset()
  vim.api.nvim_set_current_dir(vim.g.wrt_test_root)
end
