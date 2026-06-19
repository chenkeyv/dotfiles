local M = { vi = {} }

local colors = require("kanagawa.colors").setup({ theme = "wave" })
local palette_colors = colors.palette

M.vi.text = {
	n = "NORMAL",
	no = "NORMAL",
	i = "INSERT",
	v = "VISUAL",
	V = "V-LINE",
	["\22"] = "V-BLOCK",
	c = "COMMAND",
	cv = "COMMAND",
	ce = "COMMAND",
	R = "REPLACE",
	Rv = "REPLACE",
	s = "SELECT",
	S = "SELECT",
	t = "TERMINAL",
}
M.colors = {
	bg = "#282c34",
	cyan = "#008080",
	darkblue = "#081633",
	darkblue2 = "#2c82b8",
	magenta = "#d16d9e",
	blue = "#71ace7",
	white = "#FFFFFF",
	black = "#272822",
	lightblack = "#2D2E27",
	lightblack2 = "#383a3e",
	arkblack = "#211F1C",
	grey = "#8F908A",
	lightgrey = "#575b61",
	darkgrey = "#64645e",
	warmgrey = "#75715E",
	pink = "#F93C80",
	green = "#84F57D",
	darkgreen = "#a1c181",
	aqua = "#66d9ef",
	darkaqua = "#4EADE5",
	yellow = "#FFFF43",
	orange = "#FFBD37",
	deepOrange = "#FF8C00",
	purple = palette_colors.springViolet1,
	darkpurple = "#855dcf",
	red = "#FF1919",
	darkred = "#F44747",
	addfg = "#d7ffaf",
	addbg = "#5f875f",
	delbg = "#f75f5f",
	changefg = "#d7d7ff",
	changebg = "#5f5f87",
}

return M
