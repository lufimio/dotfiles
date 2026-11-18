-- Shell UI only. Hardware/media actions belong to controls.lua, not shell IPC.
local M = {}
local commands = {
	dms = {
		overview = "dms ipc call hypr toggleOverview",
		power_menu = "dms ipc call powermenu toggle",
		notifications = "dms ipc call notifications toggle",
		dismiss = "dms ipc call notifications dismiss",
		cheatsheet = "dms ipc call keybinds toggle hyprland",
		lock = "loginctl lock-session",
		dnd = "dms ipc call notifications toggleDoNotDisturb",
		screenshot_region = 'dms screenshot region --cursor=off --dir "$HOME/Pictures/Screenshots"',
		screenshot_window = 'dms screenshot window --cursor=off --dir "$HOME/Pictures/Screenshots"',
		screenshot_output = 'dms screenshot full --cursor=off --dir "$HOME/Pictures/Screenshots"',
	},
	-- Installed Noctalia 5.4.1: NOT the old qs -c noctalia-shell IPC API.
	noctalia = {
		power_menu = "noctalia msg panel-toggle session",
		notifications = "noctalia msg panel-toggle control-center notifications",
		dismiss = "noctalia msg notification-clear-active",
		lock = "noctalia msg session lock",
		dnd = "noctalia msg notification-dnd-toggle",
		screenshot_region = 'noctalia msg screenshot-region --no-show-cursor --save-to-file --directory "$HOME/Pictures/Screenshots"',
		screenshot_window = 'noctalia msg screenshot-window --no-show-cursor --save-to-file --directory "$HOME/Pictures/Screenshots"',
		screenshot_output = 'noctalia msg screenshot-fullscreen --no-show-cursor --save-to-file --directory "$HOME/Pictures/Screenshots"',
		-- No workspace overview or compatible legacy cheatsheet plugin: unbound.
	},
}

function M.select(name)
	assert(commands[name], 'shell must be "dms" or "noctalia"')
	M.name = name
end

function M.command(action)
	assert(M.name, "select a desktop shell before loading bindings")
	return commands[M.name][action]
end

function M.start()
	local root = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr"
	local script = root .. "/scripts/start_shell.py"
	hl.exec_cmd("python3 '" .. script:gsub("'", "'\\''") .. "' " .. M.name)
end

return M
