-- Run by scripts/nvim-smoke.sh after the config has loaded. Exits non-zero on any
-- failure, which a headless Neovim would otherwise not do for a broken init.lua.

local failures = {}

local function check(condition, message)
	if not condition then
		failures[#failures + 1] = message
	end
end

local function description(lhs)
	return vim.fn.maparg(lhs, "n", false, true).desc
end

local function run()
	check(vim.v.errmsg == "", "startup error: " .. vim.v.errmsg)
	check(not vim.fn.execute("messages"):find("E5113", 1, true), "init.lua raised an error")

	for _, module in ipairs({ "blink.cmp", "conform", "gitsigns", "kanagawa", "lualine", "neo-tree" }) do
		check(package.loaded[module] ~= nil, "plugin did not load: " .. module)
	end
	check(_G.Snacks ~= nil, "plugin did not load: snacks")
	check(package.loaded["configs.ui"] ~= nil, "ui2 setup failed")

	check(vim.fn.maparg("<C-S>", "n") == "<Cmd>write<CR>", "<C-s> must not force-write")
	for lhs, desc in pairs({
		grr = "Find references",
		gri = "Find implementations",
		grt = "Find type definitions",
		["]b"] = "Cycle to next buffer",
		["[b"] = "Cycle to previous buffer",
		[",bd"] = "Close buffer",
	}) do
		check(description(lhs) == desc, ("%s should map to %q"):format(lhs, desc))
	end
	-- These would wait for 'timeoutlen' or replace built-in motions and commands.
	for _, lhs in ipairs({ "gr", "gi", "td", "<C-X>", "<C-Tab>" }) do
		check(vim.fn.maparg(lhs, "n") == "", lhs .. " should stay unmapped")
	end

	for _, server in ipairs({
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
	}) do
		check(vim.lsp.is_enabled(server), "language server not enabled: " .. server)
		check(vim.lsp.config[server] ~= nil, "language server has no config: " .. server)
	end

	local treesitter = require("plugins.treesitter")
	local available = {}
	for _, parser in ipairs(require("nvim-treesitter").get_available()) do
		available[parser] = true
	end
	for _, parser in ipairs(treesitter.parsers) do
		check(available[parser], "parser is not available upstream: " .. parser)
	end

	if vim.env.DOTFILES_SMOKE_BUNDLE == "1" then
		local missing = treesitter.missing()
		check(#missing == 0, "bundle is missing parsers: " .. table.concat(missing, ", "))
		-- query.get returns nil, not an error, for a dangling or missing query link.
		for _, parser in ipairs(treesitter.parsers) do
			check(pcall(vim.treesitter.language.add, parser), "parser does not load: " .. parser)
			local query_ok, query = pcall(vim.treesitter.query.get, parser, "highlights")
			check(query_ok and query ~= nil, "parser has no highlight query: " .. parser)
		end
		local queries = vim.fn.stdpath("data") .. "/site/queries"
		for name, kind in vim.fs.dir(queries) do
			check(kind ~= "link" or vim.uv.fs_stat(queries .. "/" .. name) ~= nil, "dangling query link: " .. name)
		end
		-- A language whose highlights inherit from a query-only dependency.
		local javascript = vim.treesitter.query.get("javascript", "highlights")
		check(javascript ~= nil and vim.tbl_contains(javascript.captures, "keyword.function"), "ecma queries missing")

		-- blink.cmp sets up completion only after its asynchronous library check.
		local completion_ready = vim.wait(10000, function()
			return package.loaded["blink.cmp.completion"] ~= nil
		end, 100)
		check(completion_ready, "blink.cmp did not finish setting up")
		if vim.fn.executable("git") == 1 then
			check(
				require("blink.cmp.fuzzy").implementation_type == "rust",
				"blink.cmp did not load its bundled fuzzy matching library"
			)
		end
	end
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
	failures[#failures + 1] = tostring(err)
end

if #failures > 0 then
	io.stderr:write("Neovim smoke test failed:\n")
	for _, failure in ipairs(failures) do
		io.stderr:write("  - " .. failure .. "\n")
	end
	vim.cmd.cquit(1)
end

io.stdout:write("Neovim smoke test passed.")
vim.cmd("qa!")
