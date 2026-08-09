local format = require("wrt.format")
local git = require("wrt.git")
local worktree = require("wrt.worktree")

local M = {}

--- Render a worktree preview into `bufnr`, painting cached data immediately and
--- refreshing once git answers. `is_current` guards the async repaint: telescope
--- reuses one preview buffer, so a late result must not overwrite a worktree the
--- user has already scrolled past.
---@param bufnr integer
---@param wt wrt.Worktree
---@param is_current? fun(): boolean
function M.render(bufnr, wt, is_current)
  local function draw()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if is_current and not is_current() then
      return
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, format.preview_lines(wt))
    vim.bo[bufnr].filetype = "markdown"
  end
  draw()
  if not git.cache[wt.path] then
    git.info(wt.path, draw)
  end
end

---@param opts? table telescope picker options
function M.pick(opts)
  local telescope_pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  opts = opts or {}

  git.refresh_dirty(worktree.list(), function()
    local pickers = require("wrt.pickers")
    local items = pickers.items()

    local previewer = previewers.new_buffer_previewer({
      title = "Worktree",
      define_preview = function(self, entry)
        local wt = entry.value.wt
        self.state.wrt_path = wt.path
        M.render(self.state.bufnr, wt, function()
          return self.state.wrt_path == wt.path
        end)
      end,
    })

    telescope_pickers
      .new(opts, {
        prompt_title = "Worktrees (wrt)",
        finder = finders.new_table({
          results = items,
          entry_maker = function(item)
            return { value = item, display = format.plain(item), ordinal = item.text }
          end,
        }),
        sorter = conf.generic_sorter(opts),
        previewer = previewer,
        attach_mappings = function(prompt_bufnr, map)
          local function run(name)
            return function()
              local entry = action_state.get_selected_entry()
              if not entry then
                return
              end
              actions.close(prompt_bufnr)
              pickers.actions[name](entry.value)
            end
          end
          actions.select_default:replace(run("switch"))
          map({ "i", "n" }, "<c-x>", run("remove"))
          map({ "i", "n" }, "<a-e>", run("env"))
          map({ "i", "n" }, "<a-t>", run("shell"))
          map({ "i", "n" }, "<a-b>", run("db"))
          map({ "i", "n" }, "<a-y>", run("yank"))
          map({ "i", "n" }, "<a-n>", function()
            actions.close(prompt_bufnr)
            require("wrt.commands").create()
          end)
          return true
        end,
      })
      :find()
  end)
end

return M
