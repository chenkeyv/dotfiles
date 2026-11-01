local ui = require("vim._core.ui2")
local group = vim.api.nvim_create_augroup("DotfilesUi2", { clear = true })
local M = {}

-- ui.wins, ui.bufs, ui.msg, and ui.cmd are undocumented ui2 internals, so
-- tolerate them changing shape instead of raising on every command-line use.
local function cmdline_window()
	local win = ui.wins and ui.wins.cmd
	if type(win) == "number" and vim.api.nvim_win_is_valid(win) then
		return win
	end
end

local function default_cmdline_position()
	if vim.g.ui_cmdline_pos ~= nil then
		return { vim.g.ui_cmdline_pos[1] - 1, vim.g.ui_cmdline_pos[2] }
	end

	local height = vim.o.cmdheight == 0 and 1 or vim.o.cmdheight
	return { vim.o.lines - height, 0 }
end

function M.cmdline_position()
	local win = cmdline_window()
	if not win then
		return default_cmdline_position()
	end

	local config = vim.api.nvim_win_get_config(win)
	if config.hide or config.relative ~= "editor" or config.anchor ~= "NW" then
		return default_cmdline_position()
	end

	local border = type(config.border) == "table" and #config.border > 0
	local border_offset = border and 1 or 0
	-- Blink adds one row when placing the menu below this anchor. Returning
	-- the final content row makes the menu cover the popup's bottom border.
	local row = config.row + vim.api.nvim_win_get_height(win) - 1 + border_offset

	return { row, config.col + border_offset }
end

function M.cmdline_cursor_position()
	local position = M.cmdline_position()
	local win = cmdline_window()
	local buf = ui.bufs and ui.bufs.cmd
	if not win or type(buf) ~= "number" or not vim.api.nvim_buf_is_valid(buf) then
		return position
	end

	local config = vim.api.nvim_win_get_config(win)
	if config.hide or config.relative ~= "editor" or config.anchor ~= "NW" then
		return position
	end

	local cursor = vim.api.nvim_win_get_cursor(win)
	local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
	position[2] = position[2] + vim.fn.strdisplaywidth(line:sub(1, cursor[2]))

	return position
end

local function keep_cmdline_floating()
	if ui.cmdheight ~= 0 or vim.o.cmdheight == 0 then
		return
	end

	-- UI2 temporarily reserves a command-line row while showing its floating
	-- window. Restore cmdheight before UI2 redraws so the layout stays fixed.
	vim._with({ noautocmd = true, o = { splitkeep = "screen" } }, function()
		vim.o.cmdheight = 0
	end)
	if ui.msg and ui.msg.set_pos then
		ui.msg.set_pos()
	end
end

local function configure_cmdline()
	local win = cmdline_window()
	if not win then
		return
	end

	local max_width = math.max(1, vim.o.columns - 4)
	local width = math.min(max_width, math.max(20, math.floor(vim.o.columns * 0.6)))

	vim.api.nvim_win_set_config(win, {
		relative = "editor",
		anchor = "NW",
		row = math.max(1, math.floor(vim.o.lines * 0.2)),
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		border = "rounded",
	})
	vim.api.nvim_set_option_value(
		"winhighlight",
		"Normal:NormalFloat,FloatBorder:FloatBorder,Search:,CurSearch:,IncSearch:",
		{ win = win }
	)
end

vim.api.nvim_create_autocmd("FileType", {
	group = group,
	pattern = "cmd",
	callback = configure_cmdline,
})

vim.api.nvim_create_autocmd({ "CmdlineEnter", "VimResized" }, {
	group = group,
	callback = function()
		vim.schedule(configure_cmdline)
	end,
})

ui.enable({
	msg = {
		targets = {
			default = "msg",
			progress = "msg",
			list_cmd = "pager",
			shell_cmd = "pager",
			shell_err = "pager",
			shell_out = "pager",
			shell_ret = "pager",
		},
	},
})

if ui.cmd and ui.cmd.cmdline_show then
	local cmdline_show = ui.cmd.cmdline_show
	ui.cmd.cmdline_show = function(...)
		cmdline_show(...)
		keep_cmdline_floating()
	end
end

return M
