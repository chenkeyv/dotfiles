vim.lsp.config("*", {
	root_markers = { ".git" },
})

vim.lsp.config("sourcekit", {
	filetypes = { "swift" },
})

vim.lsp.config("ruff", {
	on_attach = function(client)
		-- Keep ty as the Python hover and type-information provider.
		client.server_capabilities.hoverProvider = false
	end,
})

vim.lsp.enable({
	"bashls",
	"clangd",
	"cssls",
	"gopls",
	"html",
	"jsonls",
	"lua_ls",
	"marksman",
	"ruff",
	"rust_analyzer",
	"sourcekit",
	"tombi",
	"tsc",
	"ty",
	"yamlls",
})

require("configs.lsp.server.lua_ls")
