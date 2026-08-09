--- End-to-end: the real terminal adapter driving real `wrt new` and `wrt rm`
--- against a throwaway managed root.
return function(h)
  h.spec("e2e")

  local commands = require("wrt.commands")
  local config = require("wrt.config")
  local env = require("wrt.env")
  local state = require("wrt.state")
  local ui = require("wrt.ui")
  local util = require("wrt.util")
  local worktree = require("wrt.worktree")

  --- Works for both the plain float (close is a bare function) and a snacks.win
  --- (close is a method).
  local function close_terminal(term)
    if type(term) == "table" and type(term.close) == "function" then
      pcall(term.close, term)
    end
  end

  local fx = h.fixture()
  local root = assert(state.root(fx.root))

  config.reset()
  config.setup({ switch = { notify = false } })

  ----------------------------------------------------------------------------
  -- terminal adapter: exit codes must reach on_exit
  ----------------------------------------------------------------------------
  h.eq(ui.has_snacks(), vim.g.wrt_test_snacks == true, "the snacks terminal is used only when snacks is present")

  local code
  local term = ui.terminal({ "help" }, {
    interactive = false,
    on_exit = function(c)
      code = c
    end,
  })
  h.wait(function()
    return code ~= nil
  end, "`wrt help` in a terminal")
  h.eq(code, 0, "a successful command reports exit 0")
  close_terminal(term)

  code = nil
  local captured = h.capture_notify()
  term = ui.terminal({ "path", "definitely-not-a-worktree" }, {
    cwd = fx.root,
    interactive = false,
    on_exit = function(c)
      code = c
    end,
  })
  h.wait(function()
    return code ~= nil
  end, "`wrt path <unknown>` in a terminal")
  captured.restore()
  h.eq(code, 2, "a usage/precondition failure reports exit 2")
  close_terminal(term)
  h.clean_buffers()

  ----------------------------------------------------------------------------
  -- `wrt new` end to end: prompt -> tokenizer -> CLI -> switch -> env
  ----------------------------------------------------------------------------
  vim.api.nvim_set_current_dir(fx.main)
  vim.cmd.edit(fx.main .. "/README.md")
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  env.reset()
  vim.env.WRT_NAME = nil

  -- Deliberately unquoted: everything before the first flag is one positional.
  -- Naive whitespace splitting produced four positionals here and exit 2.
  local restore_input = h.stub_input("Agent 09: e2e --branch agent/e2e --install false --supabase none --db false")
  commands.create()
  restore_input()

  local expected_path = fx.root .. "/agent-09-e2e"
  -- `git worktree add` creates the directory before the allocation is saved, so
  -- the directory existing is not a sufficient wait condition.
  h.wait(function()
    local probe = state.root(fx.root)
    local item = probe and worktree.find(probe, "agent-09-e2e")
    return item ~= nil and item.status == "active"
  end, "`wrt new` to register an active allocation")
  h.truthy(util.exists(expected_path), "the worktree directory was created")

  local fresh = assert(state.root(fx.root))
  local created = worktree.find(fresh, "agent-09-e2e")
  if h.truthy(created, "the new worktree is tracked in state.json") then
    h.eq(created.branch, "agent/e2e", "the explicit --branch was used")
    h.eq(created.block, 1, "the new worktree got port block 1")
    h.eq(created.offset, 100, "the new worktree got offset 100")
    h.eq(created.status, "active", "the new worktree is active")
  end

  h.wait(function()
    return util.realpath(vim.uv.cwd()) == util.realpath(expected_path)
  end, "the auto-switch into the new worktree")
  h.eq(util.realpath(vim.uv.cwd()), util.realpath(expected_path), "creating switched the working directory")
  h.eq(
    util.realpath(vim.api.nvim_buf_get_name(0)),
    util.realpath(expected_path .. "/README.md"),
    "the open buffer migrated into the new worktree"
  )
  h.eq(vim.api.nvim_win_get_cursor(0)[1], 2, "the cursor position survived the migration")

  h.wait(function()
    return vim.env.WRT_NAME == "agent-09-e2e"
  end, "`wrt env` to be applied after the switch")
  h.eq(vim.env.WRT_PORT_BLOCK, "1", "the new worktree's port block is in vim.env")

  ----------------------------------------------------------------------------
  -- auto-switch can be disabled
  ----------------------------------------------------------------------------
  config.reset()
  config.setup({ create = { switch_after = false }, switch = { notify = false } })
  vim.api.nvim_set_current_dir(fx.main)

  restore_input = h.stub_input("second --install false --supabase none --db false")
  commands.create()
  restore_input()
  h.wait(function()
    local probe = state.root(fx.root)
    local item = probe and worktree.find(probe, "second")
    return item ~= nil and item.status == "active"
  end, "the second worktree to be created")
  vim.wait(500, function()
    return false
  end)
  h.eq(util.realpath(vim.uv.cwd()), util.realpath(fx.main), "the cwd stays put when switch_after is false")

  config.reset()
  config.setup({ switch = { notify = false } })

  ----------------------------------------------------------------------------
  -- `wrt rm --delete-branch` end to end
  ----------------------------------------------------------------------------
  fresh = assert(state.root(fx.root))
  local target = assert(worktree.find(fresh, "agent-09-e2e"))
  vim.api.nvim_set_current_dir(target.path)

  local branches = h.sh({ "git", "--git-dir", fx.root .. "/.git", "branch", "--list", "agent/e2e" })
  h.matches(branches.stdout, "agent/e2e", "the branch exists before removal")

  local removed = nil
  local restore_select = h.stub_select(function(choices)
    for _, choice in ipairs(choices) do
      if choice.label == "remove + delete branch" then
        return choice
      end
    end
  end)
  commands.remove(target, fresh, function(ok)
    removed = ok
  end)
  restore_select()

  h.wait(function()
    return removed ~= nil
  end, "`wrt rm --delete-branch` to finish")
  h.eq(removed, true, "removal succeeded")
  h.falsy(util.exists(target.path), "the worktree directory is gone")

  local after = assert(state.root(fx.root))
  h.eq(worktree.find(after, "agent-09-e2e"), nil, "the allocation was dropped from state.json")

  branches = h.sh({ "git", "--git-dir", fx.root .. "/.git", "branch", "--list", "agent/e2e" })
  h.eq(vim.trim(branches.stdout or ""), "", "--delete-branch removed the branch")

  h.eq(
    util.realpath(vim.uv.cwd()),
    util.realpath(fx.main),
    "removing the active worktree switched to main first, so the cwd stayed valid"
  )

  ----------------------------------------------------------------------------
  -- main is protected
  ----------------------------------------------------------------------------
  local main = assert(worktree.main(after))
  captured = h.capture_notify()
  local refused = false
  commands.remove(main, after, function()
    refused = true
  end)
  captured.restore()
  h.matches(captured.text(), "main worktree cannot be removed", "removing main is refused")
  h.falsy(refused, "the removal callback never ran for main")
  h.truthy(util.exists(fx.main), "the main worktree still exists")

  ----------------------------------------------------------------------------
  -- :Wrt passthrough and completion
  ----------------------------------------------------------------------------
  local passthrough_args
  local restore_terminal = h.stub_terminal(function(args, opts)
    passthrough_args = { args = args, opts = opts }
  end)
  commands.passthrough({ "ls" })
  restore_terminal()
  h.eq(passthrough_args.args, { "ls" }, ":Wrt forwards its arguments verbatim")
  h.eq(
    util.realpath(passthrough_args.opts.cwd),
    util.realpath(fx.root),
    ":Wrt runs at the managed root, which is always a valid cwd for the CLI"
  )

  local subcommands = commands.complete("h", "Wrt h")
  h.truthy(vim.tbl_contains(subcommands, "help"), "completion offers matching subcommands")
  h.truthy(vim.tbl_contains(subcommands, "housekeeping"), "completion offers housekeeping")
  h.falsy(vim.tbl_contains(subcommands, "new"), "completion filters by the current prefix")

  local names = commands.complete("", "Wrt rm ")
  h.truthy(vim.tbl_contains(names, "main"), "completion offers worktree names after a subcommand")
  h.truthy(vim.tbl_contains(names, "second"), "completion offers the created worktree")

  ----------------------------------------------------------------------------
  -- prune reports through notifications
  ----------------------------------------------------------------------------
  captured = h.capture_notify()
  local before = #captured.list
  commands.prune()
  h.wait(function()
    return #captured.list > before
  end, "`wrt prune` to report")
  captured.restore()
  h.check(#captured.list > before, "prune produced user feedback")

  env.restore()
  env.reset()
  config.reset()
  h.clean_buffers()
  vim.api.nvim_set_current_dir(vim.g.wrt_test_root)
end
