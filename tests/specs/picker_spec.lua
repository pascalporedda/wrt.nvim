--- Picker-layer behaviour that does not need a picker plugin: item building,
--- formatting, dirty/preview data and the vim.ui.select fallback.
return function(h)
  h.spec("picker")

  local config = require("wrt.config")
  local format = require("wrt.format")
  local git = require("wrt.git")
  local pickers = require("wrt.pickers")
  local state = require("wrt.state")
  local util = require("wrt.util")
  local worktree = require("wrt.worktree")

  local fx = h.shared_fixture()
  local root = assert(state.root(fx.root))
  local main = assert(worktree.find(root, "main"))
  local demo = assert(worktree.find(root, "feature-demo"))

  local previous_cwd = vim.uv.cwd()
  vim.api.nvim_set_current_dir(fx.main)

  ----------------------------------------------------------------------------
  -- items
  ----------------------------------------------------------------------------
  local items = pickers.items()
  h.eq(#items, 3, "one item per tracked worktree")
  for _, item in ipairs(items) do
    h.truthy(item.text, ("item %s has a text field (snacks matches on it)"):format(item.wt.name))
    h.truthy(item.wt, "item carries its worktree")
    h.truthy(item.root, "item carries its root")
    h.eq(type(item.current), "boolean", "item has a boolean current flag")
  end
  h.eq(items[1].wt.name, "main", "items keep the list ordering")
  h.eq(items[1].current, true, "the worktree containing the cwd is marked current")
  h.eq(items[3].current, false, "other worktrees are not marked current")
  h.eq(format.text(main), "main main", "match text is name plus branch")
  h.eq(format.text(demo), "feature-demo feature/demo", "match text for a slashed branch")

  ----------------------------------------------------------------------------
  -- plain rendering (vim.ui.select, telescope, fzf-lua)
  ----------------------------------------------------------------------------
  git.clear()
  local plain_main = format.plain(items[1])
  local plain_demo = format.plain(items[3])
  h.matches(plain_main, "^● ", "the current worktree gets a marker")
  h.matches(plain_demo, "^  ", "other worktrees are indented instead")
  h.matches(plain_main, "main", "the name is rendered")
  h.matches(plain_demo, "feature/demo", "the branch is rendered")
  h.matches(plain_main, "block 0/0", "the port block is rendered")
  h.matches(plain_demo, "block 2/200", "the feature port block is rendered")
  h.check(plain_main ~= plain_demo, "rendered lines are unique per worktree (fzf-lua keys on them)")

  ----------------------------------------------------------------------------
  -- snacks highlight rendering
  ----------------------------------------------------------------------------
  local hl = format.snacks(items[1])
  h.eq(#hl, 6, "six highlight chunks per row")
  h.eq(hl[1][1], "● ", "chunk 1 is the current marker")
  h.eq(hl[1].virtual, true, "the marker is virtual so it does not affect matching")
  h.matches(hl[2][1], "^main", "chunk 2 is the padded name")
  h.eq(#hl[2][1], format.NAME_WIDTH, "the name column has a fixed width")
  h.eq(hl[2][2], "SnacksPickerSpecial", "main is highlighted as special")
  h.eq(format.snacks(items[3])[2][2], "SnacksPickerLabel", "feature worktrees use the label highlight")
  h.matches(hl[4][1], "^main", "chunk 4 is the branch")
  h.truthy(hl[6].virt_text, "chunk 6 is right-aligned virtual text")
  h.matches(hl[6].virt_text[1][1], "block 0/0", "the meta column shows the port block")
  h.eq(hl[6].virt_text_pos, "right_align", "the meta column is right aligned")

  ----------------------------------------------------------------------------
  -- dirty refresh
  ----------------------------------------------------------------------------
  git.clear()
  h.eq(git.dirty[main.path], nil, "dirty state starts empty")
  h.matches(format.plain(items[1]), "…", "an unknown dirty state renders as an ellipsis")

  local done = false
  git.refresh_dirty(worktree.list(root), function()
    done = true
  end)
  h.wait(function()
    return done
  end, "git status for every worktree")
  h.eq(git.dirty[main.path], "clean", "a pristine worktree is clean")
  h.eq(git.dirty[demo.path], "clean", "the second worktree is clean too")
  h.matches(format.plain(items[1]), "block", "a clean worktree renders without a dirty glyph")

  local scratch = demo.path .. "/untracked.txt"
  h.write_file(scratch, "dirty\n")
  done = false
  git.refresh_dirty(worktree.list(root), function()
    done = true
  end)
  h.wait(function()
    return done
  end, "git status after adding an untracked file")
  h.eq(git.dirty[demo.path], "dirty", "an untracked file makes the worktree dirty")
  h.eq(git.dirty[main.path], "clean", "the other worktree is unaffected")
  h.matches(format.plain(items[3]), "±", "a dirty worktree renders the ± glyph")

  vim.fn.delete(scratch)
  done = false
  git.refresh_dirty(worktree.list(root), function()
    done = true
  end)
  h.wait(function()
    return done
  end, "git status after cleaning up")
  h.eq(git.dirty[demo.path], "clean", "the fixture is clean again")

  -- a path that is not a repository must not throw
  git.clear()
  done = false
  git.refresh_dirty({ { name = "ghost", path = fx.dir .. "/nope" } }, function()
    done = true
  end)
  h.wait(function()
    return done
  end, "git status for a missing path")
  h.eq(git.dirty[fx.dir .. "/nope"], "?", "an unusable path is reported as unknown")

  ----------------------------------------------------------------------------
  -- preview data
  ----------------------------------------------------------------------------
  git.clear()
  local loading = format.preview_lines(main)
  h.eq(loading[1], "# main", "the preview is titled with the name")
  h.matches(table.concat(loading, "\n"), "branch    `main`", "the preview lists the branch")
  h.matches(table.concat(loading, "\n"), "ports     block 0, offset 0", "the preview lists the ports")
  h.matches(table.concat(loading, "\n"), "supabase  none", "the preview lists supabase state")
  h.matches(table.concat(loading, "\n"), "_loading git info…_", "the preview shows a placeholder until git answers")

  local info
  git.info(main.path, function(result)
    info = result
  end)
  h.wait(function()
    return info ~= nil
  end, "git status + log for the preview")
  h.truthy(git.cache[main.path], "the git result is cached")
  h.truthy(info.log and #info.log > 0, "the commit log is populated")
  h.matches(info.log[1], "init", "the log shows the fixture commit")

  local cached = table.concat(format.preview_lines(main), "\n")
  h.matches(cached, "## commits", "the preview gains a commits section once cached")
  h.falsy(cached:match("_loading git info…_"), "the placeholder is gone")

  git.cache[main.path] = { status = { "?? untracked.txt" }, log = { "abc1234 init" } }
  local with_status = table.concat(format.preview_lines(main), "\n")
  h.matches(with_status, "## status", "a dirty worktree gets a status section")
  h.matches(with_status, "?? untracked.txt", "the status body is included")

  ----------------------------------------------------------------------------
  -- snacks preview logic, driven through a mock context
  ----------------------------------------------------------------------------
  local snacks_picker = require("wrt.pickers.snacks")

  ---@param wt wrt.Worktree
  local function mock_ctx(wt)
    local calls = { reset = 0, minimal = 0, renders = 0 }
    local item = { wt = wt }
    calls.ctx = {
      item = item,
      preview = {
        reset = function(_)
          calls.reset = calls.reset + 1
        end,
        minimal = function(_)
          calls.minimal = calls.minimal + 1
        end,
        set_title = function(_, title)
          calls.title = title
        end,
        set_lines = function(_, lines)
          calls.lines = lines
          calls.renders = calls.renders + 1
        end,
        highlight = function(_, opts)
          calls.highlight = opts
        end,
      },
      picker = { closed = false, preview = { item = item } },
    }
    calls.item = item
    return calls
  end

  git.clear()
  local mock = mock_ctx(main)
  snacks_picker.preview(mock.ctx)
  h.eq(mock.reset, 1, "the preview resets before drawing")
  h.eq(mock.minimal, 1, "the preview uses a minimal window")
  h.eq(mock.title, "main", "the preview title is the worktree name")
  h.eq(mock.highlight.ft, "markdown", "the preview is highlighted as markdown")
  h.eq(mock.renders, 1, "the preview paints immediately from cache")
  h.matches(table.concat(mock.lines, "\n"), "_loading git info…_", "the first paint shows the placeholder")

  h.wait(function()
    return mock.renders > 1
  end, "the async preview redraw")
  h.matches(table.concat(mock.lines, "\n"), "## commits", "the redraw includes the commit log")
  h.truthy(git.cache[main.path], "the preview filled the git cache")

  -- a cached worktree paints once and does not re-query
  mock = mock_ctx(main)
  snacks_picker.preview(mock.ctx)
  h.eq(mock.renders, 1, "a cached preview paints exactly once")
  h.matches(table.concat(mock.lines, "\n"), "## commits", "the cached paint already has git info")

  -- staleness guard: scrolling away must not repaint the new item's window
  git.clear()
  mock = mock_ctx(demo)
  mock.ctx.picker.preview.item = { wt = main }
  snacks_picker.preview(mock.ctx)
  h.eq(mock.renders, 1, "the stale-item preview paints its first frame")
  h.wait(function()
    return git.cache[demo.path] ~= nil
  end, "the git cache to be filled even when the redraw is skipped")
  vim.wait(200, function()
    return false
  end)
  h.eq(mock.renders, 1, "no redraw happens once the previewed item changed")

  -- closed guard
  git.clear()
  mock = mock_ctx(demo)
  mock.ctx.picker.closed = true
  snacks_picker.preview(mock.ctx)
  h.wait(function()
    return git.cache[demo.path] ~= nil
  end, "the git cache to be filled after the picker closed")
  vim.wait(200, function()
    return false
  end)
  h.eq(mock.renders, 1, "no redraw happens after the picker closed")

  ----------------------------------------------------------------------------
  -- backend resolution
  ----------------------------------------------------------------------------
  h.eq(pickers.available("select"), true, "the select backend is always available")
  h.eq(pickers.available("nonsense"), false, "an unknown backend is not available")

  config.reset()
  config.setup({ picker = "select" })
  h.eq(pickers.resolve(), "select", "an explicit backend is honoured")

  if not pickers.available("fzf-lua") then
    config.reset()
    config.setup({ picker = "fzf-lua" })
    h.eq(pickers.resolve(), "select", "an unavailable backend falls back to select")
  end

  config.reset()
  local expected = "select"
  for _, name in ipairs(pickers.BACKENDS) do
    if pickers.available(name) then
      expected = name
      break
    end
  end
  h.eq(pickers.resolve(), expected, ("auto resolves to the first available backend (%s)"):format(expected))
  h.eq(pickers.BACKENDS[#pickers.BACKENDS], "select", "select is the last resort in the probe order")

  ----------------------------------------------------------------------------
  -- the vim.ui.select fallback really switches
  ----------------------------------------------------------------------------
  config.reset()
  config.setup({ picker = "select", switch = { notify = false, apply_env = false } })
  h.eq(pickers.resolve(), "select", "the fallback backend is selected")

  local offered
  local restore_select = h.stub_select(function(list)
    offered = list
    for _, item in ipairs(list) do
      if item.wt.name == "feature-demo" then
        return item
      end
    end
  end)
  pickers.pick()
  h.wait(function()
    return offered ~= nil
  end, "vim.ui.select to be offered the worktrees")
  restore_select()

  h.eq(#offered, 3, "the fallback offers every worktree")
  h.wait(function()
    return util.realpath(vim.uv.cwd()) == util.realpath(demo.path)
  end, "the fallback switch to change directory")
  h.eq(util.realpath(vim.uv.cwd()), util.realpath(demo.path), "choosing an entry switches worktree")

  -- cancelling must do nothing
  vim.api.nvim_set_current_dir(fx.main)
  restore_select = h.stub_select(function()
    return nil
  end)
  pickers.pick()
  vim.wait(300, function()
    return false
  end)
  restore_select()
  h.eq(util.realpath(vim.uv.cwd()), util.realpath(fx.main), "cancelling the fallback keeps the cwd")

  ----------------------------------------------------------------------------
  -- refusal outside a managed root
  ----------------------------------------------------------------------------
  vim.api.nvim_set_current_dir(fx.src)
  local captured = h.capture_notify()
  pickers.pick()
  captured.restore()
  h.matches(captured.text(), "not a wrt managed root", "picking outside a managed root explains why")

  ----------------------------------------------------------------------------
  -- snacks source shape (checked without snacks installed)
  ----------------------------------------------------------------------------
  local source = require("wrt.pickers.snacks").source()
  h.eq(source.title, "Worktrees (wrt)", "the source has a title")
  h.eq(type(source.finder), "function", "the source has a finder")
  h.eq(type(source.format), "function", "the source has a formatter")
  h.eq(type(source.preview), "function", "the source has a previewer")
  h.eq(type(source.confirm), "function", "the source overrides confirm (items are not files)")
  for _, action in ipairs({ "wrt_new", "wrt_remove", "wrt_reload", "wrt_env", "wrt_shell", "wrt_db", "wrt_yank" }) do
    h.eq(type(source.actions[action]), "function", ("action %s exists"):format(action))
  end

  local reserved = {
    "<c-n>",
    "<c-p>",
    "<c-r>",
    "<c-a>",
    "<c-t>",
    "<c-d>",
    "<a-d>",
    "<a-f>",
    "<a-h>",
    "<a-i>",
    "<a-r>",
    "<a-m>",
    "<a-p>",
    "<a-w>",
  }
  for _, key in ipairs(reserved) do
    h.eq(source.win.input.keys[key], nil, ("snacks default key %s is not overridden"):format(key))
  end
  h.truthy(source.win.input.keys["<c-x>"], "remove is bound in the input window")
  h.truthy(source.win.list.keys["x"], "remove is bound in the list window")

  config.reset()
  vim.api.nvim_set_current_dir(previous_cwd)
end
