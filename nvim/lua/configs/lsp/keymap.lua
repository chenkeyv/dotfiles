vim.keymap.set({ "n" }, "<leader>lca", function()
	vim.lsp.buf.code_action()
end, { noremap = true, silent = true, desc = "Code action" })

-- diagnostic keymap
local function open_diagnostic_float(_, bufnr)
	vim.diagnostic.open_float({ bufnr = bufnr, scope = "cursor", focus = false })
end

vim.keymap.set("n", "<C-p>", function()
	vim.diagnostic.jump({
		count = -1,
		on_jump = open_diagnostic_float,
	})
end, { desc = "Previous diagnostic" })

vim.keymap.set("n", "<C-n>", function()
	vim.diagnostic.jump({
		count = 1,
		on_jump = open_diagnostic_float,
	})
end, { desc = "Next diagnostic" })
