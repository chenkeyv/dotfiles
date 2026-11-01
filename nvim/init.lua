vim.loader.enable(true)
vim.g.mapleader = ","
vim.o.termguicolors = true
vim.o.scrolloff = 5
vim.o.scrolloffpad = 1
vim.o.splitbelow = true
vim.o.splitright = true
vim.o.ignorecase = true
vim.o.conceallevel = 2
vim.o.mouse = "a"
vim.o.pumheight = 10
vim.o.cmdheight = 0
vim.o.updatetime = 250
vim.o.expandtab = true
vim.o.undofile = true
vim.o.smoothscroll = true
vim.o.mousemoveevent = true
vim.opt.shortmess:append("u")

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

local highlight_group = vim.api.nvim_create_augroup("DotfilesHighlightOps", { clear = true })
vim.api.nvim_create_autocmd({ "TextYankPost", "TextPutPost" }, {
	group = highlight_group,
	callback = function()
		vim.hl.hl_op({ higroup = "Visual", timeout = 150 })
	end,
	desc = "Briefly highlight yanked and pasted text",
})

-- ui2 is experimental. A change upstream must not take the whole config down.
local ui_ok, ui_err = pcall(require, "configs.ui")
if not ui_ok then
	vim.schedule(function()
		vim.notify("ui2 setup failed: " .. tostring(ui_err), vim.log.levels.WARN)
	end)
end

vim.g.loaded_node_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_python_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0

vim.keymap.set({ "n", "i" }, "<C-s>", "<Cmd>write<CR>", { noremap = true, silent = true, desc = "Save file" })

require("configs.plugins")

require("configs.lsp")
