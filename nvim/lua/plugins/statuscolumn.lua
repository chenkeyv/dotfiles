local builtin = require("statuscol.builtin")

require("statuscol").setup({
	relculright = true,
	ft_ignore = {
		"neo-tree",
		"snacks_picker_input",
		"snacks_picker_list",
	},
	bt_ignore = {
		"nofile",
		"prompt",
		"terminal",
	},
	segments = {
		{
			sign = {
				namespace = { "diagnostic%.signs" },
				maxwidth = 1,
				colwidth = 1,
				auto = false,
			},
			click = "v:lua.ScSa",
		},
		{
			text = { builtin.lnumfunc, " " },
			condition = { true, builtin.not_empty },
			click = "v:lua.ScLa",
		},
		{
			sign = {
				namespace = { "gitsigns" },
				name = { "GitSign.*", "GitSigns.*" },
				maxwidth = 1,
				colwidth = 1,
				auto = false,
			},
			click = "v:lua.ScSa",
		},
		{
			text = { builtin.foldfunc, " " },
			click = "v:lua.ScFa",
		},
	},
})
