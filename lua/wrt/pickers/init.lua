local commands = require("wrt.commands")
local config = require("wrt.config")
local env = require("wrt.env")
local format = require("wrt.format")
local git = require("wrt.git")
local state = require("wrt.state")
local ui = require("wrt.ui")
local worktree = require("wrt.worktree")

local M = {}

--- Probe order for `picker = "auto"`.
M.BACKENDS = { "snacks", "telescope", "fzf-lua", "select" }

local modules = {
  snacks = "wrt.pickers.snacks",
  telescope = "wrt.pickers.telescope",
  ["fzf-lua"] = "wrt.pickers.fzf_lua",
  select = "wrt.pickers.select",
}

--- Is a backend usable right now? `select` always is: vim.ui.select is core.
---@param name string
---@return boolean
function M.available(name)
  if name == "select" then
    return true
  end
  if name == "snacks" then
    return _G.Snacks ~= nil and _G.Snacks.picker ~= nil
  end
  if name == "telescope" then
    return package.loaded["telescope"] ~= nil or pcall(require, "telescope")
  end
  if name == "fzf-lua" then
    return package.loaded["fzf-lua"] ~= nil or pcall(require, "fzf-lua")
  end
  return false
end

--- Backend that will actually be used, honouring `opts.picker`.
---@return string
function M.resolve()
  local want = config.get().picker
  if want ~= "auto" then
    if M.available(want) then
      return want
    end
    return "select"
  end
  for _, name in ipairs(M.BACKENDS) do
    if M.available(name) then
      return name
    end
  end
  return "select"
end

---@class wrt.PickerItem
---@field text string
---@field wt wrt.Worktree
---@field root wrt.Root
---@field current boolean

--- Items for every backend. Shared so all of them show identical data.
---@return wrt.PickerItem[]
function M.items()
  local root = state.root()
  if not root then
    return {}
  end
  local current = worktree.current(root)
  return vim.tbl_map(function(wt)
    return {
      text = format.text(wt),
      wt = wt,
      root = root,
      current = current ~= nil and current.path == wt.path,
    }
  end, worktree.list(root))
end

--- Backend-independent actions. `ctx.refresh` and `ctx.close` are optional.
---@type table<string, fun(item: wrt.PickerItem, ctx?: { refresh?: fun(), close?: fun() })>
M.actions = {
  switch = function(item)
    worktree.switch(item.wt, { root = item.root })
  end,
  remove = function(item, ctx)
    commands.remove(item.wt, item.root, function(ok)
      if ok then
        git.cache[item.wt.path] = nil
        git.dirty[item.wt.path] = nil
        if ctx and ctx.refresh then
          ctx.refresh()
        end
      end
    end)
  end,
  env = function(item)
    env.apply(item.wt, item.root, { notify = true })
  end,
  shell = function(item)
    commands.shell(item.wt, item.root)
  end,
  db = function(item)
    commands.db(item.wt, item.root)
  end,
  yank = function(item)
    commands.yank(item.wt)
  end,
}

--- Open the worktree picker with the resolved backend.
---@param opts? table backend-specific options, passed through untouched
function M.pick(opts)
  local root, err = state.root()
  if not root then
    return ui.error(err or "no wrt managed root")
  end
  if #worktree.list(root) == 0 then
    return ui.error("no worktrees tracked by wrt")
  end
  git.clear()
  local backend = M.resolve()
  return require(modules[backend]).pick(opts)
end

return M
