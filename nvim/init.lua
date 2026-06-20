vim.loader.enable(true)
vim.g.mapleader = ","
vim.o.termguicolors = true
vim.o.scrolloff = 5
vim.o.splitbelow = true
vim.o.splitright = true
vim.o.ignorecase = true
vim.o.conceallevel = 2
vim.o.mouse = "a"
vim.o.pumheight = 10
vim.o.cmdheight = 0
vim.o.updatetime = 50
vim.o.expandtab = true
vim.o.undofile = true
vim.o.smoothscroll = true
vim.o.mousemoveevent = true

vim.o.tabstop = 4
vim.o.softtabstop = 4
vim.o.shiftwidth = 4
vim.o.signcolumn = "yes:2"
vim.o.foldcolumn = "1"
vim.o.numberwidth = 4
vim.opt.fillchars:append({
	foldopen = "",
	foldclose = "",
	foldsep = " ",
})
vim.o.number = true
vim.o.relativenumber = true
vim.o.laststatus = 3
vim.o.winborder = "rounded"

vim.g.loaded_node_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_python_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0

vim.keymap.set({ "n", "i" }, "<C-s>", function()
	vim.api.nvim_command("write!")
end, { noremap = true, silent = true })

require("configs.plugins")

require("configs.lsp")
