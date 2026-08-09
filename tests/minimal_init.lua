-- Minimal init for headless tests: wrt.nvim plus, when available, the optional
-- picker plugins so their adapters get real coverage.
local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>:p"), ":h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/tests/?.lua;" .. root .. "/tests/?/init.lua;" .. package.path

vim.opt.swapfile = false
vim.opt.more = false
vim.opt.shortmess:append("A")
vim.g.wrt_test_root = root

--- Optional dependencies are opt-in via env vars so the default run proves the
--- plugin works with nothing but core Neovim.
local function add(path)
  if path and path ~= "" and vim.uv.fs_stat(path) then
    vim.opt.runtimepath:append(path)
    return true
  end
  return false
end

vim.g.wrt_test_snacks = add(vim.env.WRT_TEST_SNACKS)
vim.g.wrt_test_telescope = add(vim.env.WRT_TEST_TELESCOPE) and add(vim.env.WRT_TEST_PLENARY)
