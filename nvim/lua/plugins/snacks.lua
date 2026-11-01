require("snacks").setup({
	picker = {},
	input = { enabled = true },
	-- indent = {},
	statuscolumn = {
		enabled = false,
	},
	terminal = {},
	words = {
		debounce = 100,
	},
})

vim.keymap.set({ "n" }, "<leader><leader>", function()
	Snacks.picker()
end, { noremap = true, silent = true, desc = "Open picker" })

vim.keymap.set({ "n" }, "<leader>ff", function()
	Snacks.picker.files()
end, { noremap = true, silent = true, desc = "Find files" })

vim.keymap.set({ "n" }, "<leader>lg", function()
	Snacks.picker.grep()
end, { noremap = true, silent = true, desc = "Live grep" })

vim.keymap.set({ "n" }, "gd", function()
	Snacks.picker.lsp_definitions()
end, { noremap = true, silent = true, desc = "Find definitions" })

vim.keymap.set({ "n" }, "<leader>rr", function()
	Snacks.picker.resume()
end, { noremap = true, silent = true, desc = "Resume picker" })

vim.keymap.set({ "n" }, "<leader>sb", function()
	Snacks.picker.lines()
end, { noremap = true, silent = true, desc = "Search buffer lines" })

vim.keymap.set({ "n" }, "<leader>fb", function()
	Snacks.picker.buffers()
end, { noremap = true, silent = true, desc = "Find buffers" })

-- These replace Neovim's own gr* LSP defaults. A bare "gr" would wait for
-- 'timeoutlen', and "gi" and "td" would shadow built-in motions.
vim.keymap.set({ "n" }, "grr", function()
	Snacks.picker.lsp_references()
end, { noremap = true, silent = true, desc = "Find references" })

vim.keymap.set({ "n" }, "gri", function()
	Snacks.picker.lsp_implementations()
end, { noremap = true, silent = true, desc = "Find implementations" })

vim.keymap.set({ "n" }, "grt", function()
	Snacks.picker.lsp_type_definitions()
end, { noremap = true, silent = true, desc = "Find type definitions" })
