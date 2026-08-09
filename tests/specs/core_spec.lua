--- Pure unit tests: no fixtures, no wrt process, no UI.
return function(h)
  h.spec("core")

  local cli = require("wrt.cli")
  local config = require("wrt.config")
  local env = require("wrt.env")
  local state = require("wrt.state")
  local util = require("wrt.util")

  ----------------------------------------------------------------------------
  -- slug: must match the CLI's worktree::slug exactly
  ----------------------------------------------------------------------------
  local slug_vectors = {
    -- vectors taken verbatim from the Rust unit tests
    { "a/gpt/fix-login-timeout", "a-gpt-fix-login-timeout" },
    { "  Hello   World  ", "hello-world" },
    { "***", "wrt" },
    -- behaviour implied by the implementation
    { "", "wrt" },
    { "feature/demo", "feature-demo" },
    { "Agent 07: retry queue", "agent-07-retry-queue" },
    { "a--b", "a-b" },
    { "-lead-trail-", "lead-trail" },
    { "UPPER", "upper" },
    { "with.dots_and:colons", "with-dots-and-colons" },
    { "trailing///", "trailing" },
    { "123", "123" },
  }
  for _, vector in ipairs(slug_vectors) do
    h.eq(state.slug(vector[1]), vector[2], ("slug(%q)"):format(vector[1]))
  end

  ----------------------------------------------------------------------------
  -- normalize_branch: preserves case and slashes, unlike slug
  ----------------------------------------------------------------------------
  local branch_vectors = {
    { "refs/heads/a/b", "a/b" },
    { "hello world", "hello-world" },
    { "  spaced  ", "spaced" },
    { "feature/demo", "feature/demo" },
    { "a--b", "a--b" },
    { "MyBranch", "MyBranch" },
    { "Agent 07: retry queue", "Agent-07:-retry-queue" },
  }
  for _, vector in ipairs(branch_vectors) do
    h.eq(state.normalize_branch(vector[1]), vector[2], ("normalize_branch(%q)"):format(vector[1]))
  end

  h.check(
    state.slug("Feature/Demo") ~= state.normalize_branch("Feature/Demo"),
    "slug and normalize_branch differ on case and slashes"
  )
  h.eq(state.STATE_VERSION, 3, "state version constant is 3")

  ----------------------------------------------------------------------------
  -- argv tokenizer
  ----------------------------------------------------------------------------
  h.eq(cli.tokenize("new foo --from origin/main"), { "new", "foo", "--from", "origin/main" }, "tokenize plain words")
  h.eq(cli.tokenize("'a b' c"), { "a b", "c" }, "tokenize single quotes")
  h.eq(cli.tokenize('"a b" c'), { "a b", "c" }, "tokenize double quotes")
  h.eq(cli.tokenize("a\\ b"), { "a b" }, "tokenize backslash escape")
  h.eq(cli.tokenize("''"), { "" }, "tokenize preserves an empty quoted token")
  h.eq(cli.tokenize("'it'\\''s'"), { "it's" }, "tokenize sh-style embedded single quote")
  h.eq(cli.tokenize("'a\\b'"), { "a\\b" }, "backslash is literal inside single quotes")
  h.eq(cli.tokenize("   "), {}, "tokenize whitespace only")
  h.eq(cli.tokenize(""), {}, "tokenize empty string")

  ----------------------------------------------------------------------------
  -- name/flag partition: the bug that naive splitting caused
  ----------------------------------------------------------------------------
  local name, flags = cli.split_name_and_flags("Agent 07: retry queue --branch agent/retry")
  h.eq(name, "Agent 07: retry queue", "unquoted multi-word name stays one positional")
  h.eq(flags, { "--branch", "agent/retry" }, "flags are separated from the name")
  h.check(
    #vim.split("Agent 07: retry queue --branch agent/retry", "%s+") ~= (#flags + 1),
    "naive whitespace splitting would have produced extra positionals (exit 2)"
  )

  name, flags = cli.split_name_and_flags("feature/demo")
  h.eq(name, "feature/demo", "name without flags")
  h.eq(flags, {}, "no flags")

  name, flags = cli.split_name_and_flags("--branch x")
  h.eq(name, "", "leading flag leaves an empty name")
  h.eq(flags, { "--branch", "x" }, "leading flag is captured")

  name, flags = cli.split_name_and_flags("  spaced   name   --from HEAD~1  ")
  h.eq(name, "spaced name", "inner whitespace collapses to single spaces")
  h.eq(flags, { "--from", "HEAD~1" }, "flags after a multi-word name")

  ----------------------------------------------------------------------------
  -- wrt run argv: `--` must be exactly at raw argv index 3
  ----------------------------------------------------------------------------
  local run_args = cli.run_args("demo", { "/bin/zsh", "-lc", "echo hi" })
  h.eq(run_args, { "run", "demo", "--", "/bin/zsh", "-lc", "echo hi" }, "run_args shape")
  h.eq(run_args[3], "--", "separator is the third wrt argument (raw argv index 3)")

  h.falsy(vim.tbl_contains(cli.SUBCOMMANDS, "status"), "`status` is not a subcommand (it is `root status`)")
  h.truthy(vim.tbl_contains(cli.SUBCOMMANDS, "root"), "`root` is a subcommand")
  h.truthy(vim.tbl_contains(cli.SUBCOMMANDS, "housekeeping"), "`housekeeping` is a subcommand")

  ----------------------------------------------------------------------------
  -- wrt env output parsing
  ----------------------------------------------------------------------------
  h.eq(env.sh_unquote("'main'"), "main", "sh_unquote strips quotes")
  h.eq(env.sh_unquote("'it'\\''s'"), "it's", "sh_unquote rebuilds an embedded quote")
  h.eq(env.sh_unquote("''"), "", "sh_unquote of an empty value")
  h.eq(env.sh_unquote("bare"), "bare", "sh_unquote leaves unquoted input alone")

  local parsed = env.parse(table.concat({
    "export WRT_NAME='main'",
    "export WRT_PORT_BLOCK='0'",
    "export APP_URL='http://localhost:3100'",
    "export EMPTY=''",
    "export QUOTED='it'\\''s'",
    "export WITH_SPACES='a b c'",
    "export WITH_EQUALS='k=v'",
    "[wrt] some log line",
    "",
  }, "\n"))
  h.eq(parsed.WRT_NAME, "main", "parse simple value")
  h.eq(parsed.WRT_PORT_BLOCK, "0", "parse numeric value as string")
  h.eq(parsed.APP_URL, "http://localhost:3100", "parse url value")
  h.eq(parsed.EMPTY, "", "parse empty value")
  h.eq(parsed.QUOTED, "it's", "parse embedded quote")
  h.eq(parsed.WITH_SPACES, "a b c", "parse value with spaces")
  h.eq(parsed.WITH_EQUALS, "k=v", "parse value containing =")
  h.eq(vim.tbl_count(parsed), 7, "non-export lines are ignored")
  h.eq(env.parse(nil), {}, "parse handles nil")

  ----------------------------------------------------------------------------
  -- path helpers
  ----------------------------------------------------------------------------
  h.eq(util.rel_under("/a/b", "/a/b"), "", "rel_under identical paths")
  h.eq(util.rel_under("/a/b/c/d", "/a/b"), "c/d", "rel_under nested path")
  h.eq(util.rel_under("/a/bc", "/a/b"), nil, "rel_under respects the / boundary")
  h.eq(util.rel_under("/x", "/a/b"), nil, "rel_under outside")
  h.eq(util.rel_under(nil, "/a"), nil, "rel_under nil path")
  h.eq(util.rel_under("/a", ""), nil, "rel_under empty dir")

  ----------------------------------------------------------------------------
  -- align (replaces Snacks.picker.util.align)
  ----------------------------------------------------------------------------
  h.eq(util.align("ab", 5), "ab   ", "align pads right")
  h.eq(util.align("ab", 5, { align = "right" }), "   ab", "align pads left")
  h.eq(util.align("abcdef", 3, { truncate = true }), "abc", "align truncates")
  h.eq(#util.align("abcdef", 3, { truncate = true }), 3, "truncated width is exact")
  h.eq(util.align("abcdef", 3), "abcdef", "align without truncate keeps overflow")
  h.eq(util.align(nil, 3), "   ", "align handles nil")
  h.eq(vim.api.nvim_strwidth(util.align("日本語", 8, { truncate = true })), 8, "align is display-width aware")

  ----------------------------------------------------------------------------
  -- config defaults and validation
  ----------------------------------------------------------------------------
  config.reset()
  local defaults = config.get()
  h.eq(defaults.picker, "auto", "default picker is auto")
  h.eq(defaults.keymaps, false, "keymaps are opt-in")
  h.eq(defaults.keymap_prefix, "<leader>W", "default keymap prefix")
  h.eq(defaults.switch.migrate_buffers, true, "buffer migration on by default")
  h.eq(defaults.switch.apply_env, true, "env applied on switch by default")
  h.eq(defaults.create.switch_after, true, "auto-switch after create by default")
  h.eq(defaults.git.log_count, 12, "preview shows 12 commits")

  config.reset()
  local merged = config.setup({ picker = "select", switch = { notify = false } })
  h.eq(merged.picker, "select", "user picker wins")
  h.eq(merged.switch.notify, false, "nested override applies")
  h.eq(merged.switch.migrate_buffers, true, "sibling nested defaults survive the merge")

  local captured = h.capture_notify()
  config.reset()
  config.setup({ nonsense = true })
  captured.restore()
  h.matches(captured.text(), "unknown option `nonsense`", "unknown options are reported")

  captured = h.capture_notify()
  config.reset()
  config.setup({ keymap_prefix = 42 })
  captured.restore()
  h.matches(captured.text(), "`keymap_prefix` must be string", "wrong types are reported")

  captured = h.capture_notify()
  config.reset()
  local bad = config.setup({ picker = "nope" })
  captured.restore()
  h.matches(captured.text(), "`picker` must be one of", "invalid picker is reported")
  h.eq(bad.picker, "auto", "invalid picker falls back to the default")

  captured = h.capture_notify()
  config.reset()
  config.setup({ switch = { migrate_buffers = "yes" } })
  captured.restore()
  h.matches(captured.text(), "`switch%.migrate_buffers` must be boolean", "nested type errors are reported")

  config.reset()
end
