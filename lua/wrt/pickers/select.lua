local format = require("wrt.format")
local git = require("wrt.git")
local worktree = require("wrt.worktree")

local M = {}

--- vim.ui.select fallback. Dirty flags are resolved before opening because
--- there is no way to refresh the list once vim.ui.select is on screen.
---@param opts? { prompt?: string }
function M.pick(opts)
  opts = opts or {}
  git.refresh_dirty(worktree.list(), function()
    local pickers = require("wrt.pickers")
    local items = pickers.items()
    if #items == 0 then
      return require("wrt.ui").error("no worktrees tracked by wrt")
    end
    vim.ui.select(items, {
      prompt = opts.prompt or "Worktrees (wrt)",
      format_item = function(item)
        return format.plain(item)
      end,
    }, function(item)
      if item then
        pickers.actions.switch(item)
      end
    end)
  end)
end

return M
