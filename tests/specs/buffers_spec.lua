--- Buffer migration on switch: files that exist in the target move (keeping
--- window layout and cursor), files that do not are closed, modified buffers
--- are left alone and counted.
return function(h)
  h.spec("buffers")

  local config = require("wrt.config")
  local state = require("wrt.state")
  local util = require("wrt.util")
  local worktree = require("wrt.worktree")

  local fx = h.fixture({ "feature/demo" })
  local root = assert(state.root(fx.root))
  local main = assert(worktree.find(root, "main"))
  local demo = assert(worktree.find(root, "feature-demo"))
  local main_path, demo_path = main.path, demo.path

  -- A file present in both, one present only in main, and one that is shorter
  -- in the target so the cursor has to be clamped.
  h.write_file(main_path .. "/main-only.txt", "only here\n")
  h.write_file(main_path .. "/short.txt", ("x\n"):rep(10))
  h.write_file(demo_path .. "/short.txt", "a\nb\nc\n")

  h.clean_buffers()
  vim.api.nvim_set_current_dir(main_path)

  vim.cmd.edit(main_path .. "/README.md")
  local readme_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(readme_win, { 3, 0 })

  vim.cmd.vsplit(main_path .. "/lib/a.lua")
  local lib_win = vim.api.nvim_get_current_win()

  vim.cmd.split(main_path .. "/main-only.txt")
  local only_win = vim.api.nvim_get_current_win()

  vim.cmd.split(main_path .. "/short.txt")
  local short_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(short_win, { 9, 0 })

  -- a modified buffer must be kept, not moved
  vim.cmd.split(main_path .. "/lib/b.lua")
  local dirty_win = vim.api.nvim_get_current_win()
  local dirty_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(dirty_buf, 0, 0, false, { "-- unsaved edit" })
  h.eq(vim.bo[dirty_buf].modified, true, "the test buffer is modified")

  local windows_before = #vim.api.nvim_list_wins()
  h.eq(windows_before, 5, "five windows are open before migrating")

  local stats = worktree.migrate_buffers(main_path, demo_path)

  h.eq(stats.moved, 3, "README.md, lib/a.lua and short.txt moved")
  h.eq(stats.dropped, 1, "main-only.txt was closed")
  h.eq(stats.dirty, 1, "the modified buffer was kept and counted")
  h.eq(#vim.api.nvim_list_wins(), windows_before, "the window layout is preserved")

  h.eq(
    util.realpath(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(readme_win))),
    util.realpath(demo_path .. "/README.md"),
    "the README window now shows the target worktree's file"
  )
  h.eq(
    util.realpath(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(lib_win))),
    util.realpath(demo_path .. "/lib/a.lua"),
    "the nested file moved to the same relative path"
  )
  h.eq(vim.api.nvim_win_get_cursor(readme_win)[1], 3, "the cursor line survived the move")

  local short_cursor = vim.api.nvim_win_get_cursor(short_win)[1]
  h.eq(short_cursor, 3, "a cursor past the end of the shorter target file is clamped")
  h.check(short_cursor <= 3, "the clamped cursor is inside the new buffer")

  local dropped_name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(only_win))
  h.eq(dropped_name, "", "the window of a dropped file shows an empty scratch buffer")

  h.truthy(vim.api.nvim_buf_is_valid(dirty_buf), "the modified buffer still exists")
  h.eq(
    util.realpath(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(dirty_win))),
    util.realpath(main_path .. "/lib/b.lua"),
    "the modified buffer still points at the source worktree"
  )
  vim.bo[dirty_buf].modified = false

  ----------------------------------------------------------------------------
  -- switch(): migration + cd + event, end to end
  ----------------------------------------------------------------------------
  h.clean_buffers()
  vim.api.nvim_set_current_dir(main_path)
  vim.cmd.edit(main_path .. "/README.md")

  local event
  local autocmd = vim.api.nvim_create_autocmd("User", {
    pattern = "WrtSwitch",
    callback = function(args)
      event = args.data
    end,
  })

  local switch_stats = worktree.switch(demo, { root = root, notify = false })

  h.eq(util.realpath(vim.uv.cwd()), util.realpath(demo_path), "switch changed the working directory")
  h.eq(switch_stats and switch_stats.moved, 1, "switch migrated the open buffer")
  h.eq(
    util.realpath(vim.api.nvim_buf_get_name(0)),
    util.realpath(demo_path .. "/README.md"),
    "the current buffer follows into the new worktree"
  )
  if h.truthy(event, "User WrtSwitch fired") then
    h.eq(event.name, "feature-demo", "event payload carries the name")
    h.eq(event.branch, "feature/demo", "event payload carries the branch")
    h.eq(util.realpath(event.path), util.realpath(demo_path), "event payload carries the path")
  end
  vim.api.nvim_del_autocmd(autocmd)

  ----------------------------------------------------------------------------
  -- migration can be turned off
  ----------------------------------------------------------------------------
  h.clean_buffers()
  vim.api.nvim_set_current_dir(main_path)
  vim.cmd.edit(main_path .. "/README.md")
  config.reset()
  config.setup({ switch = { migrate_buffers = false, notify = false, apply_env = false } })

  local no_migrate = worktree.switch(demo, { root = root })
  h.eq(no_migrate, nil, "no stats are returned when migration is disabled")
  h.eq(
    util.realpath(vim.api.nvim_buf_get_name(0)),
    util.realpath(main_path .. "/README.md"),
    "the buffer stays put when migration is disabled"
  )
  h.eq(util.realpath(vim.uv.cwd()), util.realpath(demo_path), "the directory still changes")

  config.reset()

  ----------------------------------------------------------------------------
  -- a vanished worktree is refused
  ----------------------------------------------------------------------------
  local captured = h.capture_notify()
  local gone = worktree.switch({ name = "ghost", branch = "x", path = fx.dir .. "/nope", is_main = false }, {
    root = root,
  })
  captured.restore()
  h.eq(gone, nil, "switching to a missing path does nothing")
  h.matches(captured.text(), "worktree path is gone", "the user is told the path vanished")
  h.matches(captured.text(), "wrt prune", "the message suggests prune")

  h.clean_buffers()
  vim.api.nvim_set_current_dir(vim.g.wrt_test_root)
end
