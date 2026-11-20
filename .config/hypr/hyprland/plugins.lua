-- Reviewed builds. Update the path/hash here after deliberately upgrading.
local data = (os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/hypr"
local M = {
	required = {
		{
			name = "scrolloverview",
			version = "3eb62e3e0093-local-input-v4",
			path = data .. "/scrolloverview/scrolloverview-3eb62e3e0093-local-input-v4-1795149823460946465.so",
			sha256 = "99d5deb022197b36cdc70787cd06b7edeaa67ed0832ec42acbf07b5a16e3a2e6",
		},
		{
			name = "dynamic-share",
			version = "0.3.1-experimental",
			path = data .. "/dynamic-share/0.3.1-experimental-3e56775b772e/dynamic-share.so",
			sha256 = "dc63b64b56978ba99c249e1e025588d925d36394bb0e79a326ba8bb3ae26edbc",
		},
		{
			name = "edge-navigation",
			version = "0.1.2",
			path = data .. "/edge-navigation/0.1.2-232756cc8385-1795145798889799530/edge-navigation.so",
			sha256 = "232756cc838582d380e3f171d12a0ef2644b483e569c6e6d780b9be3edaaf2cb",
		},
	},
}

function M.start()
	local root = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr"
	local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
	local arguments = { "python3", quote(root .. "/scripts/start_plugins.py") }
	for _, plugin in ipairs(M.required) do
		for _, value in ipairs({ "--plugin", plugin.name, plugin.version, plugin.sha256, plugin.path }) do
			arguments[#arguments + 1] = quote(value)
		end
	end
	hl.exec_cmd(table.concat(arguments, " "))
end

return M
