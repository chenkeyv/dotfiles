local M = {}

local u = require("plugins.statusline.utils.colors")

local git_icon = {
	provider = " \u{e702} ",
	hl = {
		fg = u.colors.darkblue,
		bg = u.colors.purple,
	},
	condition = function()
		return vim.g.gitsigns_head
	end,
}

local git_branch = {
	provider = function()
		return vim.g.gitsigns_head
	end,
	hl = {
		fg = u.colors.darkblue,
		bg = u.colors.purple,
	},
	condition = function()
		return vim.g.gitsigns_head
	end,
}

local git_add = {
	{
		provider = function()
			-- icon
			return " \u{f457} "
		end,
		condition = function()
			return vim.b.gitsigns_status_dict ~= nil
				and vim.b.gitsigns_status_dict.added ~= nil
				and vim.b.gitsigns_status_dict.added > 0
		end,
		hl = {
			fg = u.colors.green,
			bg = u.colors.purple,
		},
	},
	{
		provider = function()
			local count = vim.b.gitsigns_status_dict.added or 0
			return count > 0 and count
		end,
		hl = {
			fg = u.colors.green,
			bg = u.colors.purple,
		},
		condition = function()
			return vim.b.gitsigns_status_dict ~= nil
				and vim.b.gitsigns_status_dict.added ~= nil
				and vim.b.gitsigns_status_dict.added > 0
		end,
	},
}

local git_removed = {
	{
		provider = function()
			-- icon
			return " \u{f458} "
		end,
		condition = function()
			return vim.b.gitsigns_status_dict ~= nil
				and vim.b.gitsigns_status_dict.removed ~= nil
				and vim.b.gitsigns_status_dict.removed > 0
		end,
		hl = {
			fg = u.colors.pink,
			bg = u.colors.purple,
		},
	},
	{
		provider = function()
			local count = vim.b.gitsigns_status_dict.removed or 0
			return count > 0 and count
		end,
		hl = {
			fg = u.colors.pink,
			bg = u.colors.purple,
		},
		condition = function()
			return vim.b.gitsigns_status_dict ~= nil
				and vim.b.gitsigns_status_dict.removed ~= nil
				and vim.b.gitsigns_status_dict.removed > 0
		end,
	},
}

local git_changed = {
	{
		provider = function()
			-- icon
			return " \u{f459} "
		end,
		condition = function()
			return vim.b.gitsigns_status_dict ~= nil
				and vim.b.gitsigns_status_dict.changed ~= nil
				and vim.b.gitsigns_status_dict.changed > 0
		end,
		hl = {
			fg = u.colors.yellow,
			bg = u.colors.purple,
		},
	},
	{
		provider = function()
			local count = vim.b.gitsigns_status_dict.changed or 0
			return count > 0 and count
		end,
		hl = {
			fg = u.colors.yellow,
			bg = u.colors.purple,
		},
		condition = function()
			return vim.b.gitsigns_status_dict ~= nil
				and vim.b.gitsigns_status_dict.changed ~= nil
				and vim.b.gitsigns_status_dict.changed > 0
		end,
	},
}
M.git = {
	-- git icon
	git_icon,
	-- git branch
	git_branch,
	-- git add
	git_add,
	-- git removed
	git_removed,
	-- git changed
	git_changed,
	{
		provider = function()
			return " "
		end,
		hl = {
			fg = u.colors.purple,
			bg = u.colors.purple,
		},
	},
}

return M
