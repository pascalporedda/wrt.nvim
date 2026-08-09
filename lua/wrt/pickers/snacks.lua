local format = require("wrt.format")
local git = require("wrt.git")
local worktree = require("wrt.worktree")

local M = {}

--- Paint from cache immediately, then fill in git details once they arrive.
--- The redraw is skipped when the picker closed or moved on, but the cache is
--- filled either way so scrolling back is instant.
---@param ctx snacks.picker.preview.ctx
function M.preview(ctx)
  local wt = ctx.item.wt ---@type wrt.Worktree
  ctx.preview:reset()
  ctx.preview:minimal()
  ctx.preview:set_title(wt.name)
  ctx.preview:set_lines(format.preview_lines(wt))
  ctx.preview:highlight({ ft = "markdown" })
  if git.cache[wt.path] then
    return
  end
  git.info(wt.path, function()
    if ctx.picker.closed or ctx.picker.preview.item ~= ctx.item then
      return
    end
    ctx.preview:set_lines(format.preview_lines(wt))
    ctx.preview:highlight({ ft = "markdown" })
  end)
end

---@param name string
---@return fun(picker: table, item: table)
local function action(name)
  return function(picker, item)
    if not item then
      return
    end
    picker:close()
    require("wrt.pickers").actions[name](item)
  end
end

--- The snacks.picker source. Hooks re-require lazily so reloading the plugin
--- during development cannot leave a stale module captured in a closure.
---@return snacks.picker.Config
function M.source()
  return {
    title = "Worktrees (wrt)",
    finder = function()
      return require("wrt.pickers").items()
    end,
    format = function(item)
      return require("wrt.format").snacks(item)
    end,
    preview = function(ctx)
      return require("wrt.pickers.snacks").preview(ctx)
    end,
    -- Items are not files, so the default `jump` confirm would assert.
    confirm = function(picker, item)
      picker:close()
      if item then
        require("wrt.pickers").actions.switch(item)
      end
    end,
    actions = {
      wrt_new = function(picker)
        picker:close()
        require("wrt.commands").create()
      end,
      wrt_remove = function(picker, item)
        if not item then
          return
        end
        require("wrt.pickers").actions.remove(item, {
          refresh = function()
            if not picker.closed then
              picker:refresh()
            end
          end,
        })
      end,
      wrt_reload = function(picker)
        git.clear()
        git.refresh_dirty(worktree.list(), function()
          if not picker.closed then
            picker:refresh()
          end
        end)
      end,
      wrt_env = action("env"),
      wrt_shell = action("shell"),
      wrt_db = action("db"),
      wrt_yank = action("yank"),
    },
    -- Deliberately avoids snacks defaults: <c-n>/<c-p> (list nav), <c-r>,
    -- <c-a>, <c-t>, <c-d> and <a-d/f/h/i/r/m/p/w>.
    win = {
      input = {
        keys = {
          ["<c-x>"] = { "wrt_remove", mode = { "n", "i" }, desc = "Remove worktree" },
          ["<a-n>"] = { "wrt_new", mode = { "n", "i" }, desc = "New worktree" },
          ["<a-e>"] = { "wrt_env", mode = { "n", "i" }, desc = "Apply wrt env" },
          ["<a-t>"] = { "wrt_shell", mode = { "n", "i" }, desc = "Shell in worktree" },
          ["<a-b>"] = { "wrt_db", mode = { "n", "i" }, desc = "Database task" },
          ["<a-y>"] = { "wrt_yank", mode = { "n", "i" }, desc = "Yank path" },
          ["<c-l>"] = { "wrt_reload", mode = { "n", "i" }, desc = "Reload" },
        },
      },
      list = {
        keys = {
          ["x"] = "wrt_remove",
          ["n"] = "wrt_new",
          ["e"] = "wrt_env",
          ["t"] = "wrt_shell",
          ["b"] = "wrt_db",
          ["y"] = "wrt_yank",
          ["r"] = "wrt_reload",
        },
      },
    },
  }
end

--- Make `Snacks.picker.wrt()` and `Snacks.picker.pick("wrt")` work. Optional:
--- pick() passes the source inline, so this only adds discoverability.
function M.register()
  pcall(function()
    require("snacks.picker.config.sources").wrt = M.source()
  end)
end

---@param opts? snacks.picker.Config
function M.pick(opts)
  local picker = Snacks.picker.pick(vim.tbl_deep_extend("force", M.source(), opts or {}))
  if not picker then
    return
  end
  git.refresh_dirty(worktree.list(), function()
    if not picker.closed then
      picker:find()
    end
  end)
  return picker
end

return M
