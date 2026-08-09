# wrt.nvim

Neovim integration for [`wrt`](https://github.com/pascalporedda/wrt-cli), a Git worktree helper
built for parallel and agentic development.

`wrt` owns more than `git worktree` does: reserved port blocks, generated `.env` / `.wrt.env`
files and Supabase allocations, all recorded in `<managed-root>/.git/.wrt/state.json`. This plugin
drives it from inside the editor, and — crucially — **moves your open buffers with you** when you
switch worktrees.

- Pick and switch worktrees, with dirty markers and a git preview.
- Open buffers follow you to the same relative path in the target worktree, keeping window layout
  and cursor position. Missing files close; unsaved buffers are left alone.
- `wrt env` is pushed into `vim.env` on every switch, so terminals, tasks and LSP children inherit
  that worktree's port block.
- Create, remove, prune, housekeeping, `root status`, database tasks, a worktree shell, and a
  `:Wrt` passthrough for everything else.

## Requirements

- **Neovim >= 0.11**
- **The `wrt` CLI.** There are no tagged releases yet, so install from source:

  ```sh
  cargo install --locked --git https://github.com/pascalporedda/wrt-cli
  ```

  It lands in `~/.cargo/bin/wrt`, which the plugin finds even if it is not on `$PATH`.
- `git`

Optional, for a nicer picker — the plugin detects whichever you have and falls back to
`vim.ui.select` when you have none:

- [snacks.nvim](https://github.com/folke/snacks.nvim) (`Snacks.picker`)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)

Run `:checkhealth wrt` after installing. It reports the resolved `wrt` path and whether the binary
runs, the git version, whether the current directory is inside a managed root, the `state.json`
version compatibility, the picker backend that will be used, and which optional dependencies are
present.

> Neovim discovers health checks from the runtimepath, and lazy.nvim only adds a plugin to the
> runtimepath once it loads. If you lazy-load this plugin with `cmd`/`keys`, `:checkhealth wrt`
> reports "no healthcheck found" until you have used it once in that session. Install without lazy
> triggers (as above) to have it always available.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "pascalporedda/wrt.nvim", opts = {} }
```

That gives you `:Wrt` and the full Lua API but **no keymaps** — a published plugin should not claim
a prefix you may already use. To get the documented set under `<leader>W`:

```lua
{
  "pascalporedda/wrt.nvim",
  opts = { keymaps = true },
}
```

Lazy-loading works without eager setup:

```lua
{
  "pascalporedda/wrt.nvim",
  cmd = "Wrt",
  keys = {
    { "<leader>Ww", function() require("wrt").pick() end, desc = "Worktrees (switch)" },
    { "<leader>Wn", function() require("wrt").create() end, desc = "New worktree" },
  },
  opts = {},
}
```

## Keymaps

`keymaps = true` defines these under `keymap_prefix` (default `<leader>W`):

| Key | Action | Description |
| --- | --- | --- |
| `<leader>Ww` / `<leader>WW` | `pick` | Worktrees (switch) |
| `<leader>Wn` | `create` | New worktree |
| `<leader>Wx` | `remove_current` | Remove current worktree |
| `<leader>Wm` | `goto_main` | Go to main worktree |
| `<leader>Wp` | `prune` | Prune missing worktrees |
| `<leader>Wh` | `housekeeping_dry` | Housekeeping (dry run) |
| `<leader>WH` | `housekeeping_apply` | Housekeeping (apply) |
| `<leader>Ws` | `status` | Root status |
| `<leader>Wi` | `discover` | Discover `.wrt.json` (codex) |
| `<leader>Wc` | `clone` | Clone a new managed root |
| `<leader>We` | `apply_env_current` | Apply worktree env |
| `<leader>Wt` | `shell_current` | Shell in worktree |
| `<leader>Wr` | `run_current` | Run command in worktree |
| `<leader>Wd` | `db_current` | Database task |

Override individual entries by suffix; `false` removes one:

```lua
opts = {
  keymaps = {
    x = false,        -- drop the remove mapping
    z = "goto_main",  -- add <leader>Wz
  },
  keymap_prefix = "<leader>gw",
}
```

### Inside the picker

Available with the snacks and telescope backends:

| Key | Action |
| --- | --- |
| `<cr>` | Switch to the worktree |
| `<c-x>` | Remove worktree |
| `<a-n>` | New worktree |
| `<a-e>` | Apply that worktree's `wrt env` |
| `<a-t>` | Shell in the worktree |
| `<a-b>` | Database task |
| `<a-y>` | Yank the path |
| `<c-l>` | Reload (snacks only) |

With snacks these also work from normal mode in the list: `x`, `n`, `e`, `t`, `b`, `y`, `r`.

## Configuration

Defaults in full:

```lua
require("wrt").setup({
  -- Absolute path to the wrt binary. nil = $PATH, then ~/.cargo/bin/wrt.
  bin = nil,

  -- "auto" probes snacks -> telescope -> fzf-lua -> select.
  picker = "auto", -- "auto"|"snacks"|"telescope"|"fzf-lua"|"select"

  -- false = define nothing. true = the table above. table = per-suffix overrides.
  keymaps = false,
  keymap_prefix = "<leader>W",
  which_key = true,
  which_key_group = "worktree (wrt)",

  switch = {
    migrate_buffers = true, -- move open buffers into the target worktree
    clear_jumps = true,
    apply_env = true,       -- push `wrt env` into vim.env
    notify = true,          -- report the worktree and migration counts
  },

  env = {
    notify = false, -- notify on every automatic env application
  },

  create = {
    switch_after = true, -- switch into the new worktree when `wrt new` exits 0
  },

  notify = {
    enabled = true,
    title = "wrt",
  },

  -- Floating terminal geometry. Fractions are relative to the editor.
  terminal = {
    border = "rounded",
    width = 0.85,
    height = 0.8,
    backdrop = 60, -- snacks only
    title_pos = "center",
  },

  git = {
    log_count = 12, -- commits in the picker preview
  },
})
```

## Commands

`:Wrt` with no arguments opens the picker. With arguments it runs any `wrt` command in a floating
terminal at the managed root, which is always a valid working directory for the CLI:

```vim
:Wrt ls
:Wrt new feat/login --from origin/main
:Wrt db feature-demo reset --yes
:Wrt root status
```

Completion offers subcommands first, then worktree names.

Arguments are tokenized like a shell, so quotes and escapes work as typed.

## API

```lua
local wrt = require("wrt")

wrt.pick(opts)              -- open the picker
wrt.switch("feature-demo")  -- switch by name or by item
wrt.create()                -- prompt, then `wrt new`
wrt.create_named(name, flags)
wrt.remove(target)          -- nil = the worktree containing the cwd
wrt.list(root)              -- wrt.Worktree[], main first then alphabetical
wrt.current()               -- wrt.Worktree|nil
wrt.main()
wrt.goto_main()
wrt.root(path)              -- wrt.Root|nil, string|nil (reason)
wrt.slug(name)              -- mirrors the CLI's slug()
wrt.apply_env(target, opts)
wrt.restore_env()
wrt.prune()
wrt.housekeeping(apply)
wrt.status()                -- `wrt root status`
wrt.discover()              -- `wrt init`
wrt.clone()
wrt.shell(target)
wrt.run(target)
wrt.db(target)
```

Names are slugged for you, so `wrt.switch("Feature/Demo")` finds `feature-demo`.

### Events

Switching fires a `User` autocommand:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "WrtSwitch",
  callback = function(args)
    -- args.data = { name = "feature-demo", path = "/…/feature-demo", branch = "feature/demo" }
  end,
})
```

It fires after buffer migration, the `:cd` and `:clearjumps`, but `wrt env` is applied
asynchronously, so those variables may land in `vim.env` shortly afterwards.

## Notes on behaviour

- **Multi-word names need no quoting.** In the `wrt new` prompt everything before the first
  `-flag` is the name, so `Agent 07: retry queue --branch agent/retry` is one positional plus two
  flags. Note that a name containing a colon produces an illegal branch name, so pass `--branch`
  as in that example.
- **`main` is an allocation key, not a directory name.** The primary checkout is tracked as `main`
  even when its directory is named after a different default branch, and it cannot be removed.
  Removing the worktree you are standing in switches to main first.
- **`wrt env` may legitimately fail** when a Supabase-bound worktree's stack is not running. That
  happens routinely while switching, so it is silent unless you ask for notifications.
- **Environment restore, not delete.** Values that `wrt env` overwrites are remembered and put
  back on the next switch, and a generation counter stops a slow `wrt env` from clobbering a newer
  switch.

## Local development

Point lazy.nvim at a checkout instead of GitHub:

```lua
{
  dir = "~/src/wrt.nvim", -- or: "pascalporedda/wrt.nvim", dev = true
  opts = {},
}
```

With `dev = true`, lazy.nvim resolves the plugin under your `dev.path` (`~/projects` by default);
set `dev = { path = "~/src" }` in your lazy.nvim setup to match.

## Tests

The suite runs headless against a **real `wrt` binary** and throwaway managed roots that it
creates and deletes itself.

```sh
make test-bare   # core Neovim only, proves the vim.ui.select fallback works
make test-all    # clones snacks + telescope into .tests/ and exercises those adapters
make lint        # stylua --check
```

## License

MIT
