local cli = require("wrt.cli")
local config = require("wrt.config")
local env = require("wrt.env")
local state = require("wrt.state")
local ui = require("wrt.ui")
local worktree = require("wrt.worktree")

local M = {}

---@return string
local function shell()
  return vim.env.SHELL or vim.o.shell
end

--- `wrt new`. The prompt takes a name plus optional flags, e.g.
--- `feat/login --from origin/main` or `Agent 07: retry queue --branch agent/retry`.
function M.create()
  worktree.with_root(function(root)
    ui.input({ prompt = "wrt new (name [flags])" }, function(value)
      value = value and vim.trim(value) or ""
      if value == "" then
        return
      end
      local name, flags = cli.split_name_and_flags(value)
      if name == "" then
        return ui.error("a worktree name is required")
      end
      local slug = state.slug(name)
      M.create_named(name, flags, root, slug)
    end)
  end)
end

--- Non-interactive half of create(), so the API and tests can skip the prompt.
---@param name string
---@param flags? string[]
---@param root? wrt.Root
---@param slug? string
function M.create_named(name, flags, root, slug)
  root = root or state.root()
  if not root then
    return ui.error("no wrt managed root")
  end
  slug = slug or state.slug(name)
  local args = vim.list_extend({ "new", name }, flags or {})
  ui.terminal(args, {
    cwd = root.managed_root,
    on_exit = function(code)
      if code ~= 0 or not config.get().create.switch_after then
        return
      end
      local fresh = state.root(root.managed_root)
      local item = worktree.find(fresh, slug)
      if item then
        return worktree.switch(item, { root = fresh })
      end
      ui.warn(("created, but no worktree named `%s` in state"):format(slug))
    end,
  })
end

--- `wrt rm <name>` with a prompt for --force / --delete-branch.
---@param item wrt.Worktree
---@param root wrt.Root
---@param cb? fun(ok: boolean)
function M.remove(item, root, cb)
  if item.is_main then
    return ui.error("the main worktree cannot be removed")
  end
  local choices = {
    { label = "remove", args = {} },
    { label = "remove + delete branch", args = { "--delete-branch" } },
    { label = "force remove", args = { "--force" } },
    { label = "force remove + delete branch", args = { "--force", "--delete-branch" } },
  }
  ui.select(choices, {
    prompt = ("Remove worktree %s (%s)?"):format(item.name, item.branch),
    format_item = function(choice)
      return choice.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    -- The cwd is about to disappear, so leave it before removing and tell
    -- switch() where we came from; current() could not derive it afterwards.
    local current = worktree.current(root)
    if current and current.path == item.path then
      local main = worktree.main(root)
      if main then
        worktree.switch(main, { root = root, from = item.path })
      end
    end
    local args = vim.list_extend({ "rm", item.name }, choice.args)
    cli.system(args, { cwd = root.managed_root }, function(res)
      if res.code ~= 0 then
        ui.error(("`wrt rm %s` failed (exit %d)\n%s"):format(item.name, res.code, cli.detail(res)))
      else
        ui.info("removed " .. item.name)
      end
      if cb then
        cb(res.code == 0)
      end
    end)
  end)
end

function M.remove_current()
  worktree.with_current(function(item, root)
    M.remove(item, root)
  end)
end

--- `wrt prune`.
function M.prune()
  worktree.with_root(function(root)
    cli.system({ "prune" }, { cwd = root.managed_root }, function(res)
      local output = cli.detail(res)
      if res.code ~= 0 then
        return ui.error(("`wrt prune` failed (exit %d)\n%s"):format(res.code, output))
      end
      ui.info(output ~= "" and output or "prune: nothing to do")
    end)
  end)
end

--- `wrt housekeeping`. Applying deletes branches, so it asks first.
---@param apply? boolean
function M.housekeeping(apply)
  worktree.with_root(function(root)
    if apply then
      local ok = vim.fn.confirm("Delete merged branches not attached to a worktree?", "&No\n&Yes", 1)
      if ok ~= 2 then
        return
      end
    end
    ui.terminal(apply and { "housekeeping", "--apply" } or { "housekeeping" }, {
      cwd = root.managed_root,
      interactive = false,
    })
  end)
end

--- `wrt db <name> <op>`. Runs in an interactive terminal: `reset` prompts on a
--- TTY and refuses non-interactively without --yes.
---@param item wrt.Worktree
---@param root wrt.Root
function M.db(item, root)
  ui.select({ "reset", "seed", "migrate" }, { prompt = "wrt db " .. item.name }, function(op)
    if not op then
      return
    end
    ui.terminal({ "db", item.name, op }, { cwd = root.managed_root })
  end)
end

--- `wrt root status`.
function M.status()
  worktree.with_root(function(root)
    ui.terminal({ "root", "status" }, { cwd = root.managed_root, interactive = false })
  end)
end

--- `wrt init` — Codex-assisted `.wrt.json` discovery.
function M.discover()
  worktree.with_root(function(root)
    ui.terminal({ "init" }, {
      cwd = root.managed_root,
      title = "wrt init (codex discovery)",
    })
  end)
end

--- An interactive shell inside a worktree, carrying its port block and env.
---@param item wrt.Worktree
---@param root wrt.Root
function M.shell(item, root)
  ui.terminal(cli.run_args(item.name, { shell() }), {
    cwd = root.managed_root,
    title = ("wrt shell: %s"):format(item.name),
  })
end

--- Prompt for a command line and run it through the shell inside a worktree, so
--- quoting, pipes and globs behave as typed.
---@param item wrt.Worktree
---@param root wrt.Root
function M.run(item, root)
  ui.input({ prompt = ("wrt run %s -- "):format(item.name) }, function(value)
    value = value and vim.trim(value) or ""
    if value == "" then
      return
    end
    ui.terminal(cli.run_args(item.name, { shell(), "-lc", value }), {
      cwd = root.managed_root,
      title = ("wrt run %s: %s"):format(item.name, value),
    })
  end)
end

--- `wrt clone <url> --root <dir>`, then switch into the new main worktree.
function M.clone()
  ui.input({ prompt = "wrt clone (git url)" }, function(url)
    url = url and vim.trim(url) or ""
    if url == "" then
      return
    end
    local suggested = url:gsub("[?#].*$", ""):gsub("/+$", ""):gsub("%.git$", "")
    suggested = vim.fn.fnamemodify(suggested, ":t")
    ui.input({ prompt = "managed root directory", default = suggested }, function(dir)
      dir = dir and vim.trim(dir) or ""
      if dir == "" then
        return
      end
      local target = vim.fs.normalize(dir:match("^[/~]") and dir or (vim.uv.cwd() .. "/" .. dir))
      ui.terminal({ "clone", url, "--root", target }, {
        cwd = vim.fs.dirname(target),
        on_exit = function(code)
          if code ~= 0 then
            return
          end
          local fresh = state.root(target)
          local main = worktree.main(fresh)
          if main then
            worktree.switch(main, { root = fresh })
          end
        end,
      })
    end)
  end)
end

function M.goto_main()
  worktree.with_root(function(root)
    local main = worktree.main(root)
    if not main then
      return ui.error("state has no main worktree")
    end
    worktree.switch(main, { root = root })
  end)
end

--- Apply the current worktree's env, with feedback.
function M.apply_env_current()
  worktree.with_current(function(item, root)
    env.apply(item, root, { notify = true })
  end)
end

function M.shell_current()
  worktree.with_current(M.shell)
end

function M.run_current()
  worktree.with_current(M.run)
end

function M.db_current()
  worktree.with_current(M.db)
end

--- `:Wrt <args...>` — run any wrt command in a float at the managed root.
---@param args string[]
function M.passthrough(args)
  local root = state.root()
  ui.terminal(args, { cwd = root and root.managed_root or vim.uv.cwd() })
end

--- Completion for `:Wrt`: subcommands first, then worktree names.
---@param lead string
---@param line string
---@return string[]
function M.complete(lead, line)
  if line:match("^%s*Wrt%s+%S+%s") then
    return vim.tbl_map(function(item)
      return item.name
    end, worktree.list())
  end
  return vim.tbl_filter(function(name)
    return name:find(lead, 1, true) == 1
  end, cli.SUBCOMMANDS)
end

--- Yank a worktree path to the unnamed and system registers.
---@param item wrt.Worktree
function M.yank(item)
  vim.fn.setreg(vim.v.register or '"', item.path)
  vim.fn.setreg("+", item.path)
  ui.info("yanked " .. item.path)
end

return M
