--- Real telescope integration. Skipped unless WRT_TEST_TELESCOPE and
--- WRT_TEST_PLENARY point at checkouts.
return function(h)
  h.spec("telescope")

  if not vim.g.wrt_test_telescope then
    print("  telescope: WRT_TEST_TELESCOPE/WRT_TEST_PLENARY not set, specs skipped")
    return
  end

  local config = require("wrt.config")
  local format = require("wrt.format")
  local git = require("wrt.git")
  local pickers = require("wrt.pickers")
  local state = require("wrt.state")
  local util = require("wrt.util")
  local worktree = require("wrt.worktree")

  require("telescope").setup({})

  h.eq(pickers.available("telescope"), true, "the telescope backend is detected")

  local fx = h.shared_fixture()
  local root = assert(state.root(fx.root))
  local demo = assert(worktree.find(root, "feature-demo"))
  vim.api.nvim_set_current_dir(fx.main)
  vim.o.columns = 200
  vim.o.lines = 50

  config.reset()
  config.setup({ picker = "telescope", switch = { notify = false, apply_env = false } })
  h.eq(pickers.resolve(), "telescope", "an explicit telescope backend is honoured")

  ----------------------------------------------------------------------------
  -- the picker opens and lists every worktree
  ----------------------------------------------------------------------------
  git.clear()
  pickers.pick()

  local action_state = require("telescope.actions.state")
  h.wait(function()
    local picker = action_state.get_current_picker(vim.api.nvim_get_current_buf())
    return picker ~= nil and picker.finder ~= nil
  end, "the telescope picker to open", 10000)

  local picker = action_state.get_current_picker(vim.api.nvim_get_current_buf())
  if not h.truthy(picker, "telescope picker instance") then
    return
  end
  -- new_table applies the entry_maker up front, so results are already entries.
  h.eq(#picker.finder.results, 3, "the finder holds every worktree")
  h.eq(picker.finder.results[1].value.wt.name, "main", "ordering is preserved")

  local entry = picker.finder.results[3]
  h.eq(entry.value.wt.name, "feature-demo", "the entry keeps the item")
  h.eq(entry.ordinal, format.text(demo), "the ordinal is the match text")
  h.matches(entry.display, "feature/demo", "the display line shows the branch")

  ----------------------------------------------------------------------------
  -- the previewer renders this plugin's lines
  ----------------------------------------------------------------------------
  git.clear()
  h.truthy(picker.previewer, "the picker has a previewer")

  local adapter = require("wrt.pickers.telescope")
  local preview_buf = vim.api.nvim_create_buf(false, true)
  adapter.render(preview_buf, demo)

  local text = table.concat(vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false), "\n")
  h.matches(text, "^# feature%-demo", "the previewer renders the heading")
  h.matches(text, "branch    `feature/demo`", "the previewer renders the branch")
  h.matches(text, "_loading git info…_", "the first paint shows the placeholder")
  h.eq(vim.bo[preview_buf].filetype, "markdown", "the preview buffer is markdown")

  h.wait(function()
    return table.concat(vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false), "\n"):match("## commits") ~= nil
  end, "the previewer to repaint with git info", 10000)
  h.truthy(git.cache[demo.path], "the previewer filled the git cache")

  -- staleness guard: a late result must not overwrite a repurposed buffer
  git.clear()
  local stale_buf = vim.api.nvim_create_buf(false, true)
  adapter.render(stale_buf, demo, function()
    return false
  end)
  h.eq(vim.api.nvim_buf_get_lines(stale_buf, 0, -1, false), { "" }, "nothing is drawn when the buffer moved on")
  h.wait(function()
    return git.cache[demo.path] ~= nil
  end, "the cache to fill even when the repaint is skipped", 10000)
  h.eq(vim.api.nvim_buf_get_lines(stale_buf, 0, -1, false), { "" }, "the stale repaint was suppressed")

  ----------------------------------------------------------------------------
  -- selecting switches worktree
  ----------------------------------------------------------------------------
  local actions = require("telescope.actions")
  picker:set_selection(2)
  local selected = action_state.get_selected_entry()
  if h.truthy(selected, "an entry is selected") then
    local target = selected.value.wt
    actions.select_default(vim.api.nvim_get_current_buf())
    h.wait(function()
      return util.realpath(vim.uv.cwd()) == util.realpath(target.path)
    end, "the telescope selection to switch worktree", 10000)
    h.eq(
      util.realpath(vim.uv.cwd()),
      util.realpath(target.path),
      ("selecting %s switched the working directory"):format(target.name)
    )
  end

  pcall(function()
    actions.close(vim.api.nvim_get_current_buf())
  end)
  config.reset()
  h.clean_buffers()
  vim.api.nvim_set_current_dir(vim.g.wrt_test_root)
end
