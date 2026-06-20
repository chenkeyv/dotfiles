vim.pack.add({
	{
		src = "https://github.com/nvim-treesitter/nvim-treesitter",
		version = "main",
	},
	{
		src = "https://github.com/nvim-neo-tree/neo-tree.nvim",
		version = "main",
	},
	{
		src = "https://github.com/saghen/blink.cmp",
		version = vim.version.range("*"),
	},
	"https://github.com/saghen/blink.indent",
	"https://github.com/rebelot/kanagawa.nvim",
	"https://github.com/folke/snacks.nvim",
	"https://github.com/luukvbaal/statuscol.nvim",
	"https://github.com/MunifTanjim/nui.nvim",
	"https://github.com/rebelot/heirline.nvim",
	"https://github.com/linrongbin16/lsp-progress.nvim",
	"https://github.com/neovim/nvim-lspconfig",
	"https://github.com/nvim-tree/nvim-web-devicons",
	"https://github.com/nvim-lua/plenary.nvim",
	"https://github.com/folke/noice.nvim",
	"https://github.com/rcarriga/nvim-notify",
	"https://github.com/Bekaboo/dropbar.nvim",
	"https://github.com/lewis6991/gitsigns.nvim",
	"https://github.com/windwp/nvim-autopairs",
	"https://github.com/chrisgrieser/nvim-origami",
	"https://github.com/lewis6991/satellite.nvim",
	"https://github.com/NMAC427/guess-indent.nvim",
	"https://github.com/stevearc/conform.nvim",
})

vim.pack.add({ "https://github.com/olimorris/codecompanion.nvim" }, {
	load = function() end,
})

-- register PackUpdate to update plugins
vim.api.nvim_create_user_command("PackUpdate", function()
	vim.pack.update()
end, {})

require("plugins.colorscheme")
require("plugins.statusline")
require("plugins.ai")
require("plugins.git")
require("plugins.pairs")
require("plugins.fold")
require("plugins.scrollbar")
require("plugins.indent")

require("plugins.treesitter")
require("plugins.snacks")
require("plugins.statuscolumn")
require("plugins.blink")
require("plugins.noice")
require("plugins.notify")
require("plugins.dropbar")
require("plugins.neotree")
require("plugins.format")
