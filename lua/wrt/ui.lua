local config = require("wrt.config")

local M = {}

--- vim.ui.input / vim.ui.select / vim.notify are used directly rather than
--- through plugin-specific APIs: snacks, telescope and dressing all install
--- themselves there, so the baseline picks up whatever the user already has.

---@param msg string
---@param level integer
---@return nil
function M.notify(msg, level)
  local cfg = config.get().notify
  if not cfg.enabled then
    return nil
  end
  vim.notify(msg, level, { title = cfg.title })
  return nil
end

---@param msg string
---@return nil
function M.info(msg)
  return M.notify(msg, vim.log.levels.INFO)
end

---@param msg string
---@return nil
function M.warn(msg)
  return M.notify(msg, vim.log.levels.WARN)
end

---@param msg string
---@return nil
function M.error(msg)
  return M.notify(msg, vim.log.levels.ERROR)
end

---@param opts { prompt: string, default?: string }
---@param cb fun(value: string|nil)
function M.input(opts, cb)
  vim.ui.input(opts, cb)
end

---@generic T
---@param items T[]
---@param opts { prompt?: string, format_item?: fun(item: T): string }
---@param cb fun(item: T|nil, idx: integer|nil)
function M.select(items, opts, cb)
  vim.ui.select(items, opts, cb)
end

---@return boolean
function M.has_snacks()
  return pcall(require, "snacks") and _G.Snacks ~= nil and _G.Snacks.terminal ~= nil
end

---@param args string[]
---@param opts table
---@return string
local function terminal_title(args, opts)
  local title = opts.title or ("wrt " .. table.concat(args, " "))
  if #title > 70 then
    title = title:sub(1, 67) .. "..."
  end
  return title
end

---@param cmd string[]
---@param title string
---@param opts { cwd?: string, interactive?: boolean, on_exit?: fun(code: integer) }
local function snacks_terminal(cmd, title, opts)
  local cfg = config.get().terminal
  return Snacks.terminal.open(cmd, {
    cwd = opts.cwd,
    interactive = opts.interactive ~= false,
    win = {
      position = "float",
      border = cfg.border,
      title = " " .. title .. " ",
      title_pos = cfg.title_pos,
      width = cfg.width,
      height = cfg.height,
      backdrop = cfg.backdrop,
      wo = { winbar = "" },
      -- Snacks chains a caller-supplied on_buf before starting the job, so
      -- registering TermClose here cannot be raced by a fast-exiting process.
      on_buf = function(self)
        if not opts.on_exit then
          return
        end
        vim.api.nvim_create_autocmd("TermClose", {
          buffer = self.buf,
          once = true,
          callback = function()
            local code = type(vim.v.event) == "table" and vim.v.event.status or 0
            vim.schedule(function()
              opts.on_exit(code)
            end)
          end,
        })
      end,
    },
  })
end

---@param cmd string[]
---@param title string
---@param opts { cwd?: string, interactive?: boolean, on_exit?: fun(code: integer) }
local function plain_terminal(cmd, title, opts)
  local cfg = config.get().terminal
  local interactive = opts.interactive ~= false

  local buf = vim.api.nvim_create_buf(false, false)
  local width = math.max(1, math.floor(vim.o.columns * cfg.width))
  local height = math.max(1, math.floor(vim.o.lines * cfg.height))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = cfg.border,
    title = " " .. title .. " ",
    title_pos = cfg.title_pos,
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, desc = "Close wrt terminal" })

  -- jobstart({ term = true }) must run with the target buffer current.
  vim.api.nvim_buf_call(buf, function()
    vim.fn.jobstart(cmd, {
      cwd = opts.cwd,
      term = true,
      on_exit = function(_, code)
        vim.schedule(function()
          -- Mirrors snacks: a clean exit closes the float, a failure keeps it
          -- on screen so the output stays readable.
          if interactive and code == 0 then
            close()
          elseif code ~= 0 then
            M.error(("terminal exited with code %d"):format(code))
          end
          if opts.on_exit then
            opts.on_exit(code)
          end
        end)
      end,
    })
  end)

  if interactive then
    vim.cmd.startinsert()
  end

  return { buf = buf, win = win, close = close }
end

--- Run wrt in a floating terminal so prompts, progress and exit codes all work.
--- Uses Snacks.terminal when available and a plain float otherwise.
---@param args string[]
---@param opts? { cwd?: string, title?: string, interactive?: boolean, on_exit?: fun(code: integer) }
function M.terminal(args, opts)
  local cli = require("wrt.cli")
  local exe = cli.exe()
  if not exe then
    return M.error(cli.missing_message())
  end
  opts = opts or {}
  local cmd = { exe }
  vim.list_extend(cmd, args)
  local title = terminal_title(args, opts)
  if M.has_snacks() then
    return snacks_terminal(cmd, title, opts)
  end
  return plain_terminal(cmd, title, opts)
end

return M
