require("bufferline").setup({
	options = {
		indicator = {
			style = "underline",
		},
		always_show_bufferline = true,
		show_duplicate_prefix = false,
		truncate_names = false,
		offsets = {
			{
				filetype = "neo-tree",
				text = "NEO-TREE",
				highlight = "Directory",
				separator = true,
			},
		},
	},
})

-- Ghostty keeps ctrl+tab for its own tabs, so <C-Tab> would never arrive here.
vim.keymap.set("n", "]b", "<Cmd>BufferLineCycleNext<CR>", {
	noremap = true,
	silent = true,
	desc = "Cycle to next buffer",
})

vim.keymap.set("n", "[b", "<Cmd>BufferLineCyclePrev<CR>", {
	noremap = true,
	silent = true,
	desc = "Cycle to previous buffer",
})

vim.keymap.set("n", "<leader>bd", "<Cmd>bdelete<CR>", {
	noremap = true,
	silent = true,
	desc = "Close buffer",
})
