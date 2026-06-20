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
end, { noremap = true, silent = true })

vim.keymap.set({ "n" }, "<leader>ff", function()
	Snacks.picker.files()
end, { noremap = true, silent = true })

vim.keymap.set({ "n" }, "<leader>lg", function()
	Snacks.picker.grep()
end, { noremap = true, silent = true })

vim.keymap.set({ "n" }, "gd", function()
	Snacks.picker.lsp_definitions()
end, { noremap = true, silent = true })

vim.keymap.set({ "n" }, "<leader>rr", function()
	Snacks.picker.resume()
end, { noremap = true, silent = true })

vim.keymap.set({ "n" }, "<leader>sb", function()
	Snacks.picker.lines()
end, { noremap = true, silent = true })

vim.keymap.set({ "n" }, "<leader>fb", function()
	Snacks.picker.buffers()
end, { noremap = true, silent = true })

vim.keymap.set({ "n" }, "gr", function()
	Snacks.picker.lsp_references()
end, { noremap = true, silent = true })

vim.keymap.set({ "n" }, "gi", function()
	Snacks.picker.lsp_implementations()
end, { noremap = true, silent = true })

vim.keymap.set({ "n" }, "td", function()
	Snacks.picker.lsp_type_definitions()
end, { noremap = true, silent = true })
