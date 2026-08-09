--- Managed-root discovery, state parsing, listing and current detection against
--- a real managed root built with the wrt binary.
return function(h)
  h.spec("root")

  local state = require("wrt.state")
  local util = require("wrt.util")
  local worktree = require("wrt.worktree")

  local fx = h.shared_fixture()
  local expected_root = util.realpath(fx.root)

  ----------------------------------------------------------------------------
  -- discovery from four vantage points
  ----------------------------------------------------------------------------
  local vantage = {
    { "managed root (bare .git)", fx.root },
    { "main worktree", fx.root .. "/main" },
    { "feature worktree", fx.root .. "/feature-demo" },
    { "nested dir inside a worktree", fx.root .. "/feature-demo/lib" },
  }
  for _, point in ipairs(vantage) do
    local root, err = state.root(point[2])
    if h.truthy(root, ("root resolves from %s (%s)"):format(point[1], tostring(err))) then
      h.eq(util.realpath(root.managed_root), expected_root, ("managed_root matches from %s"):format(point[1]))
      h.eq(root.state.version, 3, ("state version from %s"):format(point[1]))
    end
  end

  -- Same again through the realpath form, which is what git reports on macOS.
  local root_via_realpath = state.root(util.realpath(fx.root) .. "/main")
  h.truthy(root_via_realpath, "root resolves through the /private/var realpath form")

  local root = assert(state.root(fx.root))
  h.eq(util.realpath(root.main), util.realpath(fx.root .. "/main"), "root.main points at the default-branch checkout")
  h.eq(util.realpath(root.common_dir), util.realpath(fx.root .. "/.git"), "common_dir is the bare git dir")
  h.eq(
    util.realpath(root.state_path),
    util.realpath(fx.root .. "/.git/.wrt/state.json"),
    "state_path is .git/.wrt/state.json"
  )

  ----------------------------------------------------------------------------
  -- listing and ordering
  ----------------------------------------------------------------------------
  local items = worktree.list(root)
  h.eq(#items, 3, "three tracked worktrees")
  h.eq(
    vim.tbl_map(function(item)
      return item.name
    end, items),
    { "main", "agent-07-retry-queue", "feature-demo" },
    "main sorts first, then alphabetical"
  )

  local main = items[1]
  h.eq(main.is_main, true, "main is flagged")
  h.eq(main.branch, "main", "main branch name")
  h.eq(main.block, 0, "main reserves port block 0")
  h.eq(main.offset, 0, "main offset is 0")
  h.eq(main.status, "active", "main is active")
  h.eq(main.supabase, "none", "supabase disabled in the fixture")
  h.truthy(main.created_at, "createdAt is parsed")

  local agent = items[2]
  h.eq(agent.is_main, false, "feature worktree is not main")
  h.eq(agent.branch, "agent/retry", "explicit --branch is recorded verbatim")
  h.eq(agent.block, 1, "first feature worktree gets block 1")
  h.eq(agent.offset, 100, "offset is block * 100")
  h.eq(util.realpath(agent.path), util.realpath(fx.root .. "/agent-07-retry-queue"), "feature path is a root sibling")

  local demo = items[3]
  h.eq(demo.name, "feature-demo", "slashes in the name become dashes in the key")
  h.eq(demo.branch, "feature/demo", "the branch keeps its slash")
  h.eq(demo.block, 2, "second feature worktree gets block 2")

  ----------------------------------------------------------------------------
  -- slug parity with the directory names wrt actually created
  ----------------------------------------------------------------------------
  for _, name in ipairs(fx.names) do
    local key = state.slug(name)
    h.truthy(worktree.find(root, key), ("slug(%q) = %q matches a real allocation"):format(name, key))
    h.truthy(util.exists(fx.root .. "/" .. key), ("wrt created the directory %q"):format(key))
  end

  h.eq(worktree.main(root).name, "main", "main() finds the primary allocation")
  h.eq(worktree.find(root, "nope"), nil, "find() returns nil for an unknown name")

  ----------------------------------------------------------------------------
  -- current detection
  ----------------------------------------------------------------------------
  h.eq(worktree.current(root, fx.root), nil, "the managed root itself is not inside a worktree")
  h.eq(worktree.current(root, fx.root .. "/main").name, "main", "current from the main worktree")
  h.eq(worktree.current(root, fx.root .. "/feature-demo").name, "feature-demo", "current from a feature worktree")
  h.eq(worktree.current(root, fx.root .. "/feature-demo/lib").name, "feature-demo", "current from a nested directory")
  h.eq(
    worktree.current(root, util.realpath(fx.root) .. "/feature-demo").name,
    "feature-demo",
    "current matches when the cwd is the resolved /private/var form"
  )
  h.eq(worktree.current(root, "/tmp"), nil, "current is nil outside the managed root")

  -- and through the real process cwd, which libuv reports resolved on macOS
  local previous_cwd = vim.uv.cwd()
  vim.api.nvim_set_current_dir(fx.root .. "/agent-07-retry-queue")
  local from_cwd = worktree.current(state.root())
  h.eq(from_cwd and from_cwd.name, "agent-07-retry-queue", "current works from the real process cwd")
  vim.api.nvim_set_current_dir(previous_cwd)

  ----------------------------------------------------------------------------
  -- graceful degradation
  ----------------------------------------------------------------------------
  local outside, outside_err = state.root(fx.src)
  h.eq(outside, nil, "a plain git repo is not a managed root")
  h.matches(outside_err, "not a wrt managed root", "the reason names the missing managed root")

  local nogit, nogit_err = state.root(vim.fn.tempname())
  h.eq(nogit, nil, "a non-repository path has no root")
  h.matches(nogit_err, "not inside a git repository", "the reason names the missing repository")

  h.eq(worktree.list(nil, nil) and #worktree.list(state.root(fx.src)), 0, "list is empty without a root")

  ----------------------------------------------------------------------------
  -- state version gate
  ----------------------------------------------------------------------------
  local state_path = fx.root .. "/.git/.wrt/state.json"
  local original = util.read_file(state_path)
  local bumped = original:gsub('"version": 3', '"version": 99', 1)
  h.check(bumped ~= original, "test rewrote the version field")
  h.write_file(state_path, bumped)

  local stale, stale_err = state.root(fx.root)
  h.eq(stale, nil, "an unsupported state version is refused")
  h.matches(stale_err, "unsupported wrt state version 99", "the error names the found version")
  h.matches(stale_err, "expected 3", "the error names the expected version")

  h.write_file(state_path, original)
  h.truthy(state.root(fx.root), "root resolves again after restoring the state file")
end
