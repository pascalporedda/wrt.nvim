--- `wrt env` integration: real CLI output, vim.env application, restore
--- semantics and the out-of-order callback guard.
return function(h)
  h.spec("env")

  local env = require("wrt.env")
  local state = require("wrt.state")
  local util = require("wrt.util")
  local worktree = require("wrt.worktree")

  local fx = h.shared_fixture()
  local root = assert(state.root(fx.root))
  local main = assert(worktree.find(root, "main"))
  local demo = assert(worktree.find(root, "feature-demo"))

  ----------------------------------------------------------------------------
  -- real `wrt env` output
  ----------------------------------------------------------------------------
  local result, error_message
  env.get(main.name, root, function(e, err)
    result, error_message = e, err
  end)
  h.wait(function()
    return result ~= nil or error_message ~= nil
  end, "`wrt env main`")

  if h.truthy(result, "wrt env main succeeded (" .. tostring(error_message) .. ")") then
    h.eq(result.WRT_NAME, "main", "WRT_NAME")
    h.eq(result.WRT_BRANCH, "main", "WRT_BRANCH")
    h.eq(result.WRT_PORT_BLOCK, "0", "WRT_PORT_BLOCK for main is 0")
    h.eq(result.WRT_PORT_OFFSET, "0", "WRT_PORT_OFFSET for main is 0")
    h.eq(util.realpath(result.WRT_ROOT), util.realpath(fx.root), "WRT_ROOT is the managed root")
    h.eq(util.realpath(result.WRT_WORKTREE_PATH), util.realpath(fx.main), "WRT_WORKTREE_PATH")
    h.eq(util.realpath(result.WRT_MAIN_PATH), util.realpath(fx.main), "WRT_MAIN_PATH")
    h.truthy(result.COMPOSE_PROJECT_NAME, "COMPOSE_PROJECT_NAME is always emitted")
  end

  local demo_env
  env.get(demo.name, root, function(e)
    demo_env = e
  end)
  h.wait(function()
    return demo_env ~= nil
  end, "`wrt env feature-demo`")
  if h.truthy(demo_env, "wrt env feature-demo succeeded") then
    h.eq(demo_env.WRT_PORT_BLOCK, "2", "feature worktree port block")
    h.eq(demo_env.WRT_PORT_OFFSET, "200", "feature worktree offset is block * 100")
    h.eq(demo_env.WRT_BRANCH, "feature/demo", "branch keeps its slash in the env")
  end

  -- unknown worktree: exit 2, reported through the error argument
  local unknown_err, unknown_env = nil, nil
  local called = false
  env.get("does-not-exist", root, function(e, err)
    unknown_env, unknown_err, called = e, err, true
  end)
  h.wait(function()
    return called
  end, "`wrt env does-not-exist`")
  h.eq(unknown_env, nil, "no env table for an unknown worktree")
  h.matches(unknown_err, "unknown worktree", "the CLI error is surfaced")

  ----------------------------------------------------------------------------
  -- apply / restore
  ----------------------------------------------------------------------------
  env.reset()
  vim.env.WRT_NAME = nil
  vim.env.WRT_TEST_PRESET = "preset-value"

  env.apply(main, root, { notify = false })
  h.wait(function()
    return vim.env.WRT_NAME == "main"
  end, "apply(main) reaches vim.env")
  h.eq(vim.env.WRT_PORT_BLOCK, "0", "port block is exported to vim.env")
  h.truthy(env.backup, "a backup was recorded")
  h.eq(env.backup.WRT_NAME, false, "a previously unset key is backed up as false")

  -- switching worktrees must replace, not accumulate
  env.apply(demo, root, { notify = false })
  h.wait(function()
    return vim.env.WRT_NAME == "feature-demo"
  end, "apply(feature-demo) replaces the previous env")
  h.eq(vim.env.WRT_PORT_BLOCK, "2", "the new port block replaced the old one")

  env.restore()
  h.eq(vim.env.WRT_NAME, nil, "restore unsets keys that did not exist before")
  h.eq(vim.env.WRT_PORT_BLOCK, nil, "restore unsets all applied keys")
  h.eq(env.backup, nil, "the backup is cleared after restore")
  h.eq(vim.env.WRT_TEST_PRESET, "preset-value", "unrelated variables are untouched")

  -- a pre-existing value must come back, not be deleted
  vim.env.WRT_NAME = "pre-existing"
  env.apply(main, root, { notify = false })
  h.wait(function()
    return vim.env.WRT_NAME == "main"
  end, "apply overwrites a pre-existing value")
  h.eq(env.backup.WRT_NAME, "pre-existing", "the old value is remembered")
  env.restore()
  h.eq(vim.env.WRT_NAME, "pre-existing", "restore puts the old value back instead of deleting it")
  vim.env.WRT_NAME = nil
  vim.env.WRT_TEST_PRESET = nil

  ----------------------------------------------------------------------------
  -- generation guard: an older `wrt env` result must never win
  ----------------------------------------------------------------------------
  env.reset()
  vim.env.WRT_RACE = nil

  local original_get = env.get
  local pending = {}
  env.get = function(name, _, cb)
    pending[#pending + 1] = { name = name, cb = cb }
  end

  env.apply(main, root, { notify = false })
  env.apply(demo, root, { notify = false })
  h.eq(#pending, 2, "both applies requested an env")
  h.eq(env.seq, 2, "the generation counter advanced twice")

  -- newest result lands first, then the stale one
  pending[2].cb({ WRT_RACE = "newest" })
  h.eq(vim.env.WRT_RACE, "newest", "the newest result is applied")
  pending[1].cb({ WRT_RACE = "stale" })
  h.eq(vim.env.WRT_RACE, "newest", "the stale callback is ignored")

  -- a stale failure must not restore over a newer success either
  pending[1].cb(nil, "boom")
  h.eq(vim.env.WRT_RACE, "newest", "a stale failure does not roll back the newer env")

  env.get = original_get
  env.restore()
  h.eq(vim.env.WRT_RACE, nil, "race fixture cleaned up")
  env.reset()
end
