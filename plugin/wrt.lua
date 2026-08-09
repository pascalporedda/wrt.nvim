if vim.g.loaded_wrt then
  return
end
vim.g.loaded_wrt = true

if vim.fn.has("nvim-0.11") == 0 then
  vim.notify("wrt.nvim requires Neovim >= 0.11", vim.log.levels.ERROR, { title = "wrt.nvim" })
  return
end

vim.api.nvim_create_user_command("Wrt", function(cmd)
  local args = require("wrt.cli").tokenize(cmd.args)
  if #args == 0 then
    return require("wrt").pick()
  end
  require("wrt.commands").passthrough(args)
end, {
  nargs = "*",
  desc = "Run a wrt command",
  complete = function(lead, line)
    return require("wrt.commands").complete(lead, line)
  end,
})
