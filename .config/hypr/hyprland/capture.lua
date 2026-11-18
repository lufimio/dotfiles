-- Capture privacy and dynamic source selection. No blocking IPC in Lua binds.
local M = {}
local script = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/scripts/dynamic_cast.py"
local function quote(value)
	return "'" .. value:gsub("'", "'\\''") .. "'"
end
local function is_private(window)
	for _, tag in ipairs(window.tags or {}) do
		if tag:gsub("%*$", "") == "capture-private" then return true end
	end
	return false
end
local function command(operation, window, private)
	hl.exec_cmd("python3 " .. quote(script) .. " " .. operation .. " " .. quote(window.address) .. (private and " --private" or ""))
end
function M.target()
	local window = hl.get_active_window()
	if window and window.workspace and window.workspace.name ~= "dynamic-cast" then
		command("target", window, is_private(window))
	end
end
function M.privacy()
	local window = hl.get_active_window()
	if not window then return end
	local private = not is_private(window)
	hl.dispatch(hl.dsp.window.tag({ window = window, tag = (private and "+" or "-") .. "capture-private" }))
	command("privacy", window, private)
	hl.notification.create({ text = private and "Window excluded from capture" or "Window capture privacy disabled", timeout = 2500, icon = "info" })
end

-- Must pre-exist: XDPH builds its allowed workspace list before invoking a picker.
hl.workspace_rule({ workspace = "name:dynamic-cast", persistent = true })
hl.window_rule({
	name = "dynamic-cast-view",
	match = { initial_title = "^Hyprland Dynamic Cast$" },
	workspace = "name:dynamic-cast silent",
	float = true,
	maximize = true,
	no_initial_focus = true,
	render_unfocused = true,
	border_size = 0,
	rounding = 0,
	no_shadow = true,
})
hl.window_rule({ name = "capture-private", match = { tag = "capture-private" }, no_screen_share = true })
return M
