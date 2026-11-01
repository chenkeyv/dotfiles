local source_priority = {
	lsp = 3,
	cmdline = 3,
	path = 2,
	buffer = 1,
}
local ui_ok, ui = pcall(require, "configs.ui")

local function cmdline_position()
	local position = ui.cmdline_cursor_position()
	local ok, menu = pcall(require, "blink.cmp.completion.windows.menu")
	if not ok or menu.context == nil or menu.renderer == nil then
		return position
	end

	position[2] = position[2] - menu.context.bounds.start_col + menu.renderer:get_alignment_start_col()
	return position
end

require("blink.cmp").setup({
	fuzzy = {
		sorts = {
			function(a, b)
				local a_priority = source_priority[a.source_id] or 0
				local b_priority = source_priority[b.source_id] or 0
				if a_priority ~= b_priority then
					return a_priority > b_priority
				end
			end,
			"score",
			"sort_text",
		},
		-- Its library version check needs git and, if that fails, skips completion setup.
		implementation = vim.fn.executable("git") == 1 and "prefer_rust" or "lua",
		-- prebuilt_binaries = {
		-- 	force_version = "*",
		-- },
	},
	completion = {
		list = {
			selection = {
				preselect = false,
				auto_insert = true,
			},
		},
		accept = {
			auto_brackets = {
				enabled = false,
			},
		},
		menu = {
			border = "none",
			cmdline_position = ui_ok and cmdline_position or nil,
		},
		documentation = {
			auto_show = true,
			auto_show_delay_ms = 100,
		},
	},
	keymap = {
		preset = "enter",
		["<Tab>"] = { "select_next", "fallback" },
		["<S-Tab>"] = { "select_prev", "fallback" },
		["<CR>"] = { "fallback" },
		-- Only accept applies auto-imports and snippets; selecting just previews.
		["<C-y>"] = { "accept", "fallback" },
		["<C-e>"] = { "cancel", "fallback" },
	},

	appearance = {
		nerd_font_variant = "mono",
	},

	sources = {
		default = { "lsp", "path", "buffer" },
		providers = {
			path = {
				opts = {
					trailing_slash = true,
					label_trailing_slash = true,
				},
			},
		},
	},
	signature = { enabled = true },
	cmdline = {
		keymap = {
			preset = "enter",
			["<Tab>"] = { "select_next", "fallback" },
			["<S-Tab>"] = { "select_prev", "fallback" },
			["<CR>"] = { "fallback" },
			["<C-y>"] = { "accept", "fallback" },
		},
		completion = {
			list = {
				selection = {
					preselect = false,
					auto_insert = true,
				},
			},
			menu = { auto_show = true },
		},
	},
})
