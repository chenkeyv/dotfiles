require("gitsigns").setup({
	signs = {
		add = {
			text = "▍",
		},
		change = {
			text = "▍",
		},
		delete = {
			text = "▸",
		},
		topdelete = {
			text = "▾",
		},
		changedelete = {
			text = "▍",
		},
		untracked = {
			text = "▍",
		},
	},
	current_line_blame = true,
	current_line_blame_opts = {
		delay = 500,
	},
	on_attach = function(bufnr)
		local gs = package.loaded.gitsigns

		local function map(mode, l, r, opts)
			opts = opts or {}
			if type(opts) == "string" then
				opts = { desc = opts }
			end
			opts.buf = bufnr
			vim.keymap.set(mode, l, r, opts)
		end

		-- Navigation
		map("n", "]h", function()
			if vim.wo.diff then
				return "]c"
			end
			vim.schedule(function()
				gs.nav_hunk("next")
			end)
			return "<Ignore>"
		end, { expr = true, desc = "Next Hunk" })

		map("n", "[h", function()
			if vim.wo.diff then
				return "[c"
			end
			vim.schedule(function()
				gs.nav_hunk("prev")
			end)
			return "<Ignore>"
		end, { expr = true, desc = "Prev Hunk" })

		-- Actions
		map("n", "<leader>ghs", gs.stage_hunk, "Stage Hunk")
		map("v", "<leader>ghs", function()
			gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
		end, "Stage Hunk")
		map("n", "<leader>ghr", gs.reset_hunk, "Reset Hunk")
		map("v", "<leader>ghr", function()
			gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
		end, "Reset Hunk")
		map("n", "<leader>ghS", gs.stage_buffer, "Stage Buffer")
		map("n", "<leader>ghu", gs.undo_stage_hunk, "Undo Stage Hunk")
		map("n", "<leader>ghR", gs.reset_buffer, "Reset Buffer")
		map("n", "<leader>ghp", gs.preview_hunk, "Preview Hunk")
		map("n", "<leader>ghb", function()
			gs.blame_line({ full = true })
		end, "Blame Line")
		map("n", "<leader>ghd", gs.diffthis, "Diff This")
		map("n", "<leader>ghD", function()
			gs.diffthis("~")
		end, "Diff This ~")

		-- Text object
		map({ "o", "x" }, "ih", gs.select_hunk, "GitSigns Select Hunk")
	end,
})
