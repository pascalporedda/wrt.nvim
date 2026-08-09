local format = require("wrt.format")
local git = require("wrt.git")
local worktree = require("wrt.worktree")

local M = {}

---@param opts? table fzf-lua options
function M.pick(opts)
  local fzf = require("fzf-lua")
  opts = opts or {}

  git.refresh_dirty(worktree.list(), function()
    local pickers = require("wrt.pickers")
    local items = pickers.items()

    -- Allocation names are unique state.json keys, so the rendered lines are
    -- unique too and can be used as the lookup key.
    local by_line, entries = {}, {}
    for _, item in ipairs(items) do
      local line = format.plain(item)
      by_line[line] = item
      entries[#entries + 1] = line
    end

    ---@param name string
    local function run(name)
      return function(selected)
        local item = selected and selected[1] and by_line[selected[1]]
        if item then
          pickers.actions[name](item)
        end
      end
    end

    fzf.fzf_exec(
      entries,
      vim.tbl_deep_extend("force", {
        prompt = "Worktrees> ",
        winopts = { title = " Worktrees (wrt) ", preview = { hidden = "nohidden" } },
        previewer = false,
        preview = function(selected)
          local item = selected and selected[1] and by_line[selected[1]]
          if not item then
            return ""
          end
          return table.concat(format.preview_lines(item.wt), "\n")
        end,
        actions = {
          ["default"] = run("switch"),
          ["ctrl-x"] = run("remove"),
          ["alt-e"] = run("env"),
          ["alt-t"] = run("shell"),
          ["alt-b"] = run("db"),
          ["alt-y"] = run("yank"),
          ["alt-n"] = function()
            require("wrt.commands").create()
          end,
        },
      }, opts)
    )
  end)
end

return M
