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
