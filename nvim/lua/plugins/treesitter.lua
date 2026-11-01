local treesitter = require("nvim-treesitter")
local group = vim.api.nvim_create_augroup("DotfilesTreesitter", { clear = true })
local M = {}

-- Languages to keep installed. Add one here to get highlighting for it.
M.parsers = {
	"acp",
	"bash",
	"c",
	"cpp",
	"css",
	"diff",
	"dockerfile",
	"git_config",
	"git_rebase",
	"gitattributes",
	"gitcommit",
	"gitignore",
	"go",
	"gomod",
	"gosum",
	"gowork",
	"html",
	"ini",
	"javascript",
	"jsdoc",
	"json",
	"kdl",
	"lua",
	"luadoc",
	"make",
	"markdown",
	"markdown_inline",
	"printf",
	"python",
	"query",
	"regex",
	"ruby",
	"rust",
	"sql",
	"swift",
	"toml",
	"tsx",
	"typescript",
	"vim",
	"vimdoc",
	"xml",
	"yaml",
	"zsh",
}

local function start_parsers()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			pcall(vim.treesitter.start, bufnr)
		end
	end
end

function M.missing()
	local installed = {}
	for _, parser in ipairs(treesitter.get_installed()) do
		installed[parser] = true
	end

	return vim.tbl_filter(function(parser)
		return not installed[parser]
	end, M.parsers)
end

--- Returns the install task, or nil when there is nothing it can do.
function M.install_missing()
	local missing = M.missing()
	if #missing == 0 then
		return nil
	end

	if vim.fn.executable("tree-sitter") == 0 then
		vim.notify(
			("tree-sitter CLI not found; %d parsers are not installed. Run setup.sh to install it."):format(#missing),
			vim.log.levels.WARN
		)
		return nil
	end

	return treesitter.install(missing, { summary = true })
end

vim.api.nvim_create_autocmd("FileType", {
	group = group,
	callback = function(event)
		pcall(vim.treesitter.start, event.buf)
	end,
})

vim.api.nvim_create_autocmd("PackChanged", {
	group = group,
	callback = function(event)
		local data = event.data or {}
		local spec = data.spec or {}
		if spec.name ~= "nvim-treesitter" or data.kind ~= "update" then
			return
		end

		vim.schedule(function()
			treesitter.update(nil, { summary = true }):raise_on_error()
		end)
	end,
})

vim.api.nvim_create_autocmd("VimEnter", {
	group = group,
	once = true,
	callback = function()
		vim.schedule(function()
			local task = M.install_missing()
			if not task then
				return
			end

			task:await(function(err, success)
				if not err and success then
					start_parsers()
				end
			end)
			task:raise_on_error()
		end)
	end,
})

return M
