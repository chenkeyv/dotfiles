vim.g.neo_tree_remove_legacy_commands = 1
vim.keymap.set({ "n" }, "\\", function()
	require("neo-tree.command").execute({ toggle = true })
end, { noremap = true, silent = true, desc = "Toggle file explorer" })

vim.keymap.set({ "n" }, "|", function()
	require("neo-tree.command").execute({ action = "focus" })
end, { noremap = true, silent = true, desc = "Focus file explorer" })

require("neo-tree").setup({
	close_if_last_window = true,
	filesystem = {
		follow_current_file = {
			enabled = true,
		},
		use_libuv_file_watcher = true,
	},
	source_selector = {
		winbar = true,
		content_layout = "center",
		truncation_character = "…", -- character to use when truncating the tab label
		sources = {
			{ source = "filesystem" },
			{ source = "buffers" },
			{ source = "git_status" },
			{ source = "document_symbols" },
		},
	},
	sources = {
		"filesystem",
		"buffers",
		"git_status",
		"document_symbols",
	},
})
