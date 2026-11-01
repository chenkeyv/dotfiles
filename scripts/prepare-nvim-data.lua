-- Run by scripts/fetch-tools.sh inside headless Neovim with the config loaded.
-- Loading the config installs the plugins; this finishes what they download or
-- compile later, because the offline bundle's target host cannot do that itself.

local function prepare()
	if vim.v.errmsg ~= "" then
		error("config failed to load: " .. vim.v.errmsg)
	end

	local parsers = require("plugins.treesitter")
	local task = parsers.install_missing()
	if task then
		task:wait(30 * 60 * 1000)
	end
	local missing = parsers.missing()
	if #missing > 0 then
		error("parsers not installed: " .. table.concat(missing, ", "))
	end

	-- blink.cmp fetches its fuzzy matching library during setup.
	local release = vim.fn.stdpath("data") .. "/site/pack/core/opt/blink.cmp/target/release/"
	local ready = vim.wait(2 * 60 * 1000, function()
		local version = vim.uv.fs_stat(release .. "version")
		local library = vim.uv.fs_stat(release .. "libblink_cmp_fuzzy.so")
			or vim.uv.fs_stat(release .. "libblink_cmp_fuzzy.dylib")
		return version ~= nil and library ~= nil
	end, 200)
	if not ready then
		error("blink.cmp fuzzy library was not downloaded")
	end
end

local ok, err = xpcall(prepare, debug.traceback)
if not ok then
	io.stderr:write(tostring(err) .. "\n")
	vim.cmd.cquit(1)
end
vim.cmd("qa!")
