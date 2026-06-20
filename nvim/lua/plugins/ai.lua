local M = {}
local configured = false

local commands = {
	CodeCompanion = {
		desc = "Use the CodeCompanion Inline Assistant",
		range = true,
		nargs = "*",
	},
	CodeCompanionChat = {
		desc = "Work with a CodeCompanion chat buffer",
		range = true,
		nargs = "*",
	},
	CodeCompanionCmd = {
		desc = "Prompt the LLM to write a command for the command-line",
		nargs = "*",
	},
	CodeCompanionCLI = {
		desc = "Send a prompt to a CLI agent or open the CLI input buffer",
		bang = true,
		range = true,
		nargs = "*",
	},
	CodeCompanionActions = {
		desc = "Open the CodeCompanion actions palette",
		range = true,
		nargs = "*",
	},
}

function M.setup()
	require("codecompanion").setup({
		opts = {
			log_level = "DEBUG", -- or "TRACE"
		},
		interactions = {
			chat = {
				adapter = "gemini",
			},
			inline = {
				adapter = "gemini",
			},
		},
		adapters = {
			http = {
				gemini = function()
					return require("codecompanion.adapters").extend("gemini", {
						env = {
							api_key = "GEMINI_API_KEY",
						},
					})
				end,
			},
			acp = {
				gemini_cli = function()
					return require("codecompanion.adapters").extend("gemini_cli", {
						defaults = {
							auth_method = "gemini-api-key", -- "oauth-personal"|"gemini-api-key"|"vertex-ai"
						},
					})
				end,
			},
		},
	})
end

function M.load()
	if configured then
		return
	end

	for command in pairs(commands) do
		pcall(vim.api.nvim_del_user_command, command)
	end

	if not vim.g.loaded_codecompanion then
		vim.cmd.packadd("codecompanion.nvim")
	end
	M.setup()
	configured = true
end

local function dispatch(command, opts)
	M.load()

	local cmd = {
		cmd = command,
		args = opts.fargs,
		bang = opts.bang or false,
	}

	if opts.range and opts.range > 0 then
		cmd.range = { opts.line1, opts.line2 }
	end

	vim.api.nvim_cmd(cmd, {})
end

for command, opts in pairs(commands) do
	local command_opts = vim.tbl_extend("force", opts, {
		complete = function()
			return {}
		end,
	})

	vim.api.nvim_create_user_command(command, function(callback_opts)
		dispatch(command, callback_opts)
	end, command_opts)
end

return M
