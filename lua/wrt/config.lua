local M = {}

M.PICKERS = { "auto", "snacks", "telescope", "fzf-lua", "select" }

---@class wrt.Config
local defaults = {
  --- Absolute path to the `wrt` binary. nil = look on $PATH, then ~/.cargo/bin/wrt.
  ---@type string|nil
  bin = nil,

  --- Picker backend. "auto" probes snacks -> telescope -> fzf-lua -> select.
  ---@type "auto"|"snacks"|"telescope"|"fzf-lua"|"select"
  picker = "auto",

  --- false = define nothing (default; the plugin never steals keys).
  --- true  = define the documented set under `keymap_prefix`.
  --- table = suffix -> action name, or suffix -> false to drop one entry.
  ---@type boolean|table<string, string|false>
  keymaps = false,

  keymap_prefix = "<leader>W",

  --- Register a which-key group for `keymap_prefix` when keymaps are enabled.
  which_key = true,
  which_key_group = "worktree (wrt)",

  switch = {
    --- Move listed file buffers to the same relative path in the target worktree.
    migrate_buffers = true,
    clear_jumps = true,
    --- Push `wrt env <name>` into vim.env after switching.
    apply_env = true,
    --- Notify with the worktree name and buffer migration counts.
    notify = true,
  },

  env = {
    --- Notify on every automatic env application (explicit calls always notify).
    notify = false,
  },

  create = {
    --- Switch into the new worktree when `wrt new` exits 0.
    switch_after = true,
  },

  notify = {
    enabled = true,
    title = "wrt",
  },

  --- Floating terminal geometry. Fractions are relative to the editor.
  terminal = {
    border = "rounded",
    width = 0.85,
    height = 0.8,
    backdrop = 60,
    title_pos = "center",
  },

  git = {
    --- Commits shown in the picker preview.
    log_count = 12,
  },
}

--- Flattened type schema. Unlisted keys are rejected so typos surface at setup().
local schema = {
  bin = { "nil", "string" },
  picker = { "string" },
  keymaps = { "boolean", "table" },
  keymap_prefix = { "string" },
  which_key = { "boolean" },
  which_key_group = { "string" },
  ["switch.migrate_buffers"] = { "boolean" },
  ["switch.clear_jumps"] = { "boolean" },
  ["switch.apply_env"] = { "boolean" },
  ["switch.notify"] = { "boolean" },
  ["env.notify"] = { "boolean" },
  ["create.switch_after"] = { "boolean" },
  ["notify.enabled"] = { "boolean" },
  ["notify.title"] = { "string" },
  ["terminal.border"] = { "string", "table" },
  ["terminal.width"] = { "number" },
  ["terminal.height"] = { "number" },
  ["terminal.backdrop"] = { "number", "boolean" },
  ["terminal.title_pos"] = { "string" },
  ["git.log_count"] = { "number" },
}

---@param value any
---@param allowed string[]
---@return boolean
local function type_ok(value, allowed)
  local t = type(value)
  for _, want in ipairs(allowed) do
    if t == want then
      return true
    end
  end
  return false
end

---@param opts table
---@param prefix string
---@param errors string[]
local function validate(opts, prefix, errors)
  for key, value in pairs(opts) do
    local path = prefix == "" and tostring(key) or (prefix .. "." .. tostring(key))
    local allowed = schema[path]
    if allowed then
      if not type_ok(value, allowed) then
        errors[#errors + 1] = ("wrt.nvim: `%s` must be %s, got %s"):format(
          path,
          table.concat(allowed, "|"),
          type(value)
        )
      end
    elseif type(value) == "table" and type(defaults[key]) == "table" and prefix == "" then
      validate(value, path, errors)
    else
      errors[#errors + 1] = ("wrt.nvim: unknown option `%s`"):format(path)
    end
  end
end

---@type wrt.Config|nil
local current = nil

--- Merge and validate user options. Invalid entries are reported once and the
--- defaults are kept for those keys.
---@param opts? table
---@return wrt.Config
function M.setup(opts)
  opts = opts or {}
  local errors = {}
  validate(opts, "", errors)

  if opts.picker and not vim.tbl_contains(M.PICKERS, opts.picker) then
    errors[#errors + 1] = ("wrt.nvim: `picker` must be one of %s"):format(table.concat(M.PICKERS, ", "))
    opts = vim.deepcopy(opts)
    opts.picker = nil
  end

  if #errors > 0 then
    vim.notify(table.concat(errors, "\n"), vim.log.levels.ERROR, { title = "wrt.nvim" })
  end

  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  return current
end

--- Effective config. Falls back to defaults so every entry point works without
--- an explicit setup() call.
---@return wrt.Config
function M.get()
  if not current then
    current = vim.deepcopy(defaults)
  end
  return current
end

---@return wrt.Config
function M.defaults()
  return vim.deepcopy(defaults)
end

--- Test seam.
function M.reset()
  current = nil
end

return M
