-- Native Dynamic Share controls and compositor-owned capture privacy.
-- No Quickshell mirror, portal wrapper, or blocking IPC in selection binds.
local M = {}
local function plugin()
	local api = hl.plugin.dynamic_share
	if not api then
		hl.notification.create({ text = "Dynamic Share plugin is not loaded", timeout = 3500 })
	end
	return api
end
local function control(method)
	local api = plugin()
	if not api then return end
	if type(api[method]) ~= "function" then
		hl.notification.create({ text = "Dynamic Share action unavailable: " .. method, timeout = 3500 })
		return
	end
	local _, message = api[method]()
	if message then hl.notification.create({ text = message, timeout = 3500 }) end
end
local function is_private(window)
	for _, tag in ipairs(window.tags or {}) do
		if tag:gsub("%*$", "") == "capture-private" then return true end
	end
	return false
end
function M.target()
	control("select_focused")
end
function M.monitor()
	control("select_monitor")
end
function M.workspace()
	control("select_workspace")
end
function M.clear()
	control("clear")
end
function M.picker()
	if not plugin() then return end
	local picker = require("hyprland.dynamic-share-settings").picker
	if type(picker) ~= "table" or (picker.backend ~= "xdph" and picker.backend ~= "dmenu")
		or type(picker.command) ~= "string" then
		hl.notification.create({ text = "Invalid Dynamic Share picker settings", timeout = 3500 })
		return
	end
	local script = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config"))
		.. "/hypr/plugins/dynamic-share/select-source.py"
	local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
	hl.exec_cmd("python3 " .. quote(script) .. " pick --backend " .. quote(picker.backend) .. " --command " .. quote(picker.command))
end
function M.reset()
	control("reset") -- Lua-only control; deliberately no global reset shortcut.
end
function M.privacy()
	local window = hl.get_active_window()
	if not window then return end
	local private = not is_private(window)
	hl.dispatch(hl.dsp.window.tag({ window = window, tag = (private and "+" or "-") .. "capture-private" }))
	hl.notification.create({ text = private and "Window excluded from capture" or "Window capture privacy disabled", timeout = 2500, icon = "info" })
end

hl.window_rule({ name = "capture-private", match = { tag = "capture-private" }, no_screen_share = true })
return M
