require("kanagawa").setup({
	compile = true, -- enable compiling the colorscheme
	transparent = true, -- do not set background color
	theme = "wave", -- Load "wave" theme when 'background' option is not set
	overrides = function(colors)
		local theme = colors.theme
		return {
			NormalFloat = { bg = "none" },
			FloatBorder = { bg = "none" },
			FloatTitle = { bg = "none" },
			SignColumn = { bg = "none" },
			CursorLineSign = { bg = "none" },
			FoldColumn = { bg = "none" },
			CursorLineFold = { bg = "none" },
			StatusLineNC = { bg = "none" },
			StatusLine = { bg = "none" },
			LineNr = { fg = theme.ui.special, bg = "none" },

			NormalDark = { fg = theme.ui.fg_dim },

			WinSeparator = { fg = theme.ui.special },

			TelescopeTitle = { fg = theme.ui.special, bold = true },
			TelescopePromptBorder = { fg = theme.ui.special },
			TelescopeResultsNormal = { fg = theme.ui.special },
			TelescopeResultsBorder = { fg = theme.ui.special },
			TelescopePreviewBorder = { fg = theme.ui.special },

			BufferLineFill = { bg = "none" },
			TabLineFill = { bg = "none" },
			Pmenu = { fg = theme.ui.shade0, bg = theme.ui.bg_p1 },
			PmenuSel = { fg = "NONE", bg = theme.ui.bg_p2 },
			PmenuSbar = { bg = theme.ui.bg_m1 },
			PmenuThumb = { bg = theme.ui.bg_p2 },

			DiagnosticSignInfo = { bg = "none" },
			DiagnosticSignWarn = { bg = "none" },
			DiagnosticSignError = { bg = "none" },
			DiagnosticSignHint = { bg = "none" },
		}
	end,
})
vim.cmd.colorscheme("kanagawa")

local statuscolumn_bg_groups = {
	"FoldColumn",
	"CursorLineFold",
	"GitSignsAdd",
	"GitSignsAddCul",
	"GitSignsChange",
	"GitSignsChangeCul",
	"GitSignsDelete",
	"GitSignsDeleteCul",
	"GitSignsTopdelete",
	"GitSignsTopdeleteCul",
	"GitSignsChangedelete",
	"GitSignsChangedeleteCul",
	"GitSignsUntracked",
	"GitSignsUntrackedCul",
}

local function clear_statuscolumn_backgrounds()
	for _, group in ipairs(statuscolumn_bg_groups) do
		local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
		if ok and next(hl) then
			hl.bg = nil
			hl.ctermbg = nil
			vim.api.nvim_set_hl(0, group, hl)
		end
	end
end

vim.api.nvim_create_autocmd("ColorScheme", {
	callback = clear_statuscolumn_backgrounds,
})

clear_statuscolumn_backgrounds()
