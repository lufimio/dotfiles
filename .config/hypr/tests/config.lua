-- Offline regression tests. Run from .config/hypr: lua tests/config.lua
-- These mocks do NOT prove compositor rendering/gesture behavior.
package.path = "./?.lua;./?/init.lua;" .. package.path

local binds, events, options, calls, rules, gestures = {}, {}, {}, {}, {}, {}
local selected = arg[1] or "dms"
assert(selected == "dms" or selected == "noctalia")
local plugin_loaded = arg[2] == "scrolloverview" or arg[2] == "old-scrolloverview"
local plugin_supported = arg[2] == "scrolloverview"
local struts_enabled = arg[3] ~= "no-struts"
local submaps, current_submap = {}, ""
if plugin_supported then
	options["plugin.scrolloverview.scale"] = 0.5
end
local active, monitor, workspace, special
local windows, spaces = {}, {}
local function namespace(prefix)
	return setmetatable({}, { __index = function(t, name)
		local value = function(args) return { name = prefix .. name, args = args } end
		rawset(t, name, value)
		return value
	end })
end
local function merge(table, prefix)
	for key, value in pairs(table) do
		local full = prefix and (prefix .. "." .. key) or key
		if type(value) == "table" and not value.colors and full ~= "general.gaps_out" then
			merge(value, full)
		else
			options[full] = value
		end
	end
end

hl = {
	dsp = namespace(""),
	notification = { create = function() end },
	config = function(values) merge(values) end,
	get_config = function(key) return options[key] end,
	bind = function(keys, action, flags)
		local scope = current_submap == "" and binds or submaps[current_submap]
		assert(not scope[keys], "duplicate binding: " .. current_submap .. ":" .. keys)
		scope[keys] = { action = action, flags = flags }
	end,
	get_current_submap = function() return current_submap end,
	define_submap = function(name, callback)
		assert(not submaps[name], "duplicate submap")
		submaps[name], current_submap = {}, name
		callback()
		current_submap = ""
	end,
	get_loaded_plugins = function() return plugin_loaded and { { name = "scrolloverview" } } or {} end,
	plugin = {},
	on = function(event, fn)
		events[event] = events[event] or {}
		table.insert(events[event], fn)
	end,
	env = function() end,
	curve = function() end,
	animation = function() end,
	monitor = function() end,
	device = function() end,
	gesture = function(spec) gestures[spec.fingers .. ":" .. spec.direction] = spec end,
	permission = function() end,
	layer_rule = function() end,
	window_rule = function(rule)
		if rule.name then rules[rule.name] = rule else rules[#rules + 1] = rule end
	end,
	workspace_rule = function(rule)
		table.insert(calls, { name = "workspace_rule", args = rule })
		local handle = { enabled = true }
		function handle:is_enabled() return self.enabled end
		function handle:set_enabled(value) self.enabled = value end
		return handle
	end,
	timer = function() return {} end,
	exec_cmd = function() error("external command unexpectedly executed") end,
	get_active_window = function() return active end,
	get_active_monitor = function() return monitor end,
	get_monitors = function()
		local found, result = {}, {}
		for _, space in ipairs(spaces) do
			if space.monitor and not found[space.monitor.name] then
				found[space.monitor.name] = true
				result[#result + 1] = space.monitor
			end
		end
		return result
	end,
	get_active_workspace = function() return workspace end,
	get_active_special_workspace = function() return special end,
	get_workspace_windows = function() return windows end,
	get_workspaces = function()
		local result = {}
		for i, value in ipairs(spaces) do result[i] = value end
		return result
	end,
	get_workspace = function(id)
		for _, value in ipairs(spaces) do
			if value.id == id then return value end
		end
	end,
	dispatch = function(action)
		if type(action) == "function" then action(); return { success = true } end
		table.insert(calls, action)
		if action.name == "workspace.change_id" then
			assert(not hl.get_workspace(action.args.id), "workspace ID collision")
			local space = assert(hl.get_workspace(action.args.workspace))
			space.id, space.name = action.args.id, tostring(action.args.id)
		end
		return { success = true }
	end,
}
hl.dsp.window = namespace("window.")
hl.dsp.workspace = namespace("workspace.")
hl.dsp.group = namespace("group.")
if plugin_loaded then
	hl.plugin.scrolloverview = {}
	for _, name in ipairs({ "overview", "navigate", "window", "gesture" }) do
		hl.plugin.scrolloverview[name] = function(args)
			if name == "gesture" then
				gestures[args.fingers .. ":" .. args.direction] = args
				return
			end
			return function() calls[#calls + 1] = { name = "scrolloverview." .. name, args = args } end
		end
	end
end

-- Do not read the user's live workspace dictionary during tests.
-- Select both modes in memory, without editing the real config or starting shells.
local real_open = io.open
local file = assert(real_open("hyprland.lua"))
local source = file:read("*a")
file:close()
local substitutions
source, substitutions = source:gsub('local shell = "dms"', 'local shell = "' .. selected .. '"', 1)
assert(substitutions == 1, "keep the one-line shell selector easy to find")
if not struts_enabled then
	source, substitutions = source:gsub('require%("hyprland%.struts"%)', '-- require("hyprland.struts")', 1)
	assert(substitutions == 1)
end
io.open = function() return nil end
assert(load(source, "@hyprland.lua"))()
io.open = real_open
local nav = require("hyprland.navigation")
local workspaces = require("hyprland.workspaces")
local function last(name)
	local call = calls[#calls]
	assert(call and call.name == name, "expected dispatch " .. name)
	return call.args
end

if selected == "dms" then
	assert(options["decoration.rounding"] == 16, "DMS must override manual rounding")
	assert(options["general.col.active_border"] == "rgb(a8dfff)", "DMS colors must win")
	assert(binds["SUPER + CTRL + D"].action.args:find("toggleDoNotDisturb", 1, true))
	assert(binds["SUPER + SHIFT + S"].action.args:find("screenshot region", 1, true))
	assert(rules["niri-urgent-border"].border_color == "rgb(ffb4ab)")
	assert((gestures["4:up"] or gestures["4:vertical"]) and binds["SUPER + Tab"] and binds["SUPER + O"])
	assert(binds["SUPER + SHIFT + slash"])
	assert(not package.loaded.noctalia and not rules["noctalia-settings"])
else
	assert(options["decoration.rounding"] == 15, "Noctalia retains manual layout fallbacks")
	assert(options["general.col.active_border"] == "rgb(39bae6)")
	assert(rules["niri-urgent-border"].border_color == "rgb(d95757)")
	assert(rules["noctalia-settings"] and not rules["dms-floating-windows"])
	assert(not package.loaded["dms.colors"] and not package.loaded["dms.binds-user"])
	if not plugin_supported then
		assert(not gestures["4:up"] and not binds["SUPER + Tab"] and not binds["SUPER + O"])
	end
	assert(not binds["SUPER + SHIFT + slash"], "no incompatible legacy cheatsheet")
	for _, key in ipairs({ "SUPER + CTRL + Delete", "SUPER + N", "SUPER + Escape", "SUPER + Delete", "SUPER + CTRL + D",
		"SUPER + SHIFT + S", "SUPER + CTRL + S", "SUPER + CTRL + SHIFT + S" }) do
		assert(binds[key].action.args:match("^noctalia msg "), "Noctalia UI command must not invoke DMS")
	end
end
local expected_in, expected_out = 3, 6
if selected == "dms" then
	-- DMS can regenerate its layout independently; don't enforce the old seed
	-- over newer GUI choices. Verify that the current generated values win.
	local generated = assert(real_open("dms/layout.lua"))
	local layout_source = generated:read("*a")
	generated:close()
	expected_in = tonumber(layout_source:match("gaps_in%s*=%s*(%d+)")) or expected_in
	expected_out = tonumber(layout_source:match("gaps_out%s*=%s*(%d+)")) or expected_out
end
assert(options["general.gaps_in"] == expected_in)
if struts_enabled then
	local gaps = options["general.gaps_out"]
	assert(gaps.left == expected_out + 18 and gaps.right == expected_out + 18)
	assert(gaps.top == expected_out + 3 and gaps.bottom == expected_out + 3)
else
	assert(options["general.gaps_out"] == expected_out, "one commented include must disable struts completely")
end
assert(options["input.kb_options"] == "lv5:caps_switch")
assert(options["scrolling.wrap_focus"] == false)
assert(type(binds["SUPER + SHIFT + R"].action) == "function")
assert(type(binds["SUPER + ALT + B"].action) == "function")
assert(binds["SUPER + ALT + S"].action.args.workspace == "special:magic")
assert(binds["SUPER + SHIFT + F12"].flags.dont_inhibit)
assert(binds.XF86AudioRaiseVolume.flags.locked)

assert(require("hyprland.scrolloverview").enabled == plugin_supported)
assert(not package.loaded["hyprland.hyprexpo"], "do not configure both overview plugins")
if plugin_supported then
	assert(options["plugin.scrolloverview.scale"] == 0.5)
	assert(options["plugin.scrolloverview.layout"] == "vertical")
	assert(options["plugin.scrolloverview.shadow.enabled"] == false)
	assert(options["plugin.scrolloverview.input.scrolling_mode"] == 2)
	assert(options["plugin.scrolloverview.cross_monitor_drag"] == false)
	local overview_gesture = gestures["4:vertical"] or gestures["4:up"]
	assert(overview_gesture and overview_gesture.action == "overview")
	assert(gestures["3:horizontal"].action == "scroll_move")
	binds["SUPER + Tab"].action()
	assert(last("scrolloverview.overview") == "toggle")
	for key, direction in pairs({ Left = "left", H = "left", Right = "right", L = "right",
		Up = "up", K = "up", Down = "down", J = "down" }) do
		for _, prefix in ipairs({ "", "SUPER + " }) do
			submaps.scrolloverview[prefix .. key].action()
			assert(last("scrolloverview.navigate") == direction)
		end
	end
	submaps.scrolloverview.Return.action()
	assert(last("scrolloverview.overview") == "close")
	submaps.scrolloverview.Escape.action()
	assert(last("scrolloverview.overview") == "close")
	for key in pairs(submaps.scrolloverview) do assert(not key:match("^%d$"), "don't confuse visible rows with local numbers") end
else
	assert(not submaps.scrolloverview and not gestures["4:down"])
	assert(options["plugin.scrolloverview.layout"] == nil, "do not configure incompatible/absent plugins")
end
assert(gestures["3:horizontal"].scale == 0.8)
assert(options["gestures.workspace_swipe_distance"] == 360)
assert(options["gestures.workspace_swipe_cancel_ratio"] == 0.2)
assert(options["gestures.workspace_swipe_min_speed_to_force"] == 8)
assert(options["gestures.workspace_swipe_forever"] == false)
assert(options["gestures.scrolling.move_snap_cursor"] == false)

local controls = require("hyprland.controls")
local control_keys = {
	XF86AudioRaiseVolume = "volume_up", XF86AudioLowerVolume = "volume_down", XF86AudioMute = "mute", XF86AudioMicMute = "mic_mute",
	XF86MonBrightnessUp = "brightness_up", XF86MonBrightnessDown = "brightness_down",
	XF86AudioNext = "next", XF86AudioPrev = "previous", XF86AudioPlay = "play_pause", XF86AudioPause = "play_pause",
	["SUPER + SHIFT + N"] = "next", ["SUPER + SHIFT + B"] = "previous", ["SUPER + SHIFT + P"] = "play_pause",
	["SUPER + SHIFT + period"] = "player_volume_up", ["SUPER + SHIFT + comma"] = "player_volume_down",
}
for key, action in pairs(control_keys) do
	local binding = binds[key]
	assert(binding.action.args == controls[action], "hardware/keyboard aliases must share direct commands")
	assert(binding.flags.submap_universal, "hardware/media aliases must work inside the overview")
	assert(not binding.action.args:find("dms") and not binding.action.args:find("noctalia"))
	if key:match("^XF86") then assert(binding.flags.locked) end
	if os.getenv("PRINT_CONTROLS") then print("CONTROL\t" .. key .. "\t" .. binding.action.args) end
end
assert(not binds.XF86AudioMute.flags.repeating, "do not repeatedly toggle mute on key hold")
assert(not binds.XF86AudioPlay.flags.repeating, "do not repeatedly toggle playback on key hold")
assert(binds.XF86AudioRaiseVolume.flags.repeating and binds.XF86MonBrightnessUp.flags.repeating)

-- No shell startup (or service stop) is attached to config.reloaded.
assert(require("hyprland.shell").name == selected)
local exec = hl.exec_cmd
local startup = {}
hl.exec_cmd = function(command) startup[#startup + 1] = command end
for _, callback in ipairs(events["config.reloaded"] or {}) do callback() end
assert(#startup == 0, "never tear down a lock provider on reload")
for _, callback in ipairs(events["hyprland.start"] or {}) do callback() end
assert(startup[#startup]:find("start_shell.py' " .. selected, 1, true))
hl.exec_cmd = exec

monitor = { name = "eDP-1", x = 0, y = 0, mode = { width = 1000, height = 800 },
	reserved = { left = 10, right = 20, top = 30, bottom = 10 } }
local external = { name = "HDMI-A-1", x = 1000, y = 0 }
workspace = { id = 1, name = "1", monitor = monitor, tiled_layout = "scrolling" }
spaces = { workspace, { id = 2, name = "2", monitor = external } }
local a = { mapped = true, at = { x = 10, y = 30 }, size = { x = 200, y = 300 }, workspace = workspace, monitor = monitor }
local b = { mapped = true, at = { x = 10, y = 400 }, size = { x = 200, y = 300 }, workspace = workspace, monitor = monitor }
local column = { index = 0, windows = { a, b } }
a.layout = { name = "scrolling", column = column, index_in_column = 0 }
b.layout = { name = "scrolling", column = column, index_in_column = 1 }
windows, active = { a, b }, a

nav.vertical("down")
assert(last("focus").window == b, "focus the next row, not an adjacent monitor")
nav.vertical("down", true)
assert(last("window.move").direction == "down")
active = b
nav.vertical("down")
assert(last("focus").workspace == 2, "compact actual IDs into monitor clusters")
active = a
calls = {}
nav.vertical("up")
assert(#calls == 0, "do not wrap above workspace 1")

workspaces.number(2)
assert(last("focus").workspace == 2, "reuse dictionary entry")
monitor, workspace = external, spaces[2]
workspaces.number(2)
assert(last("focus").workspace == 4, "same local number on another monitor needs its own global ID")
monitor, workspace = spaces[1].monitor, spaces[1]
workspaces.number(9, true)
assert(last("window.move").workspace == 3, "allocate on demand and recluster actual IDs")
assert(last("window.move").follow == true)

local saved
local real_rename = os.rename
io.open = function(_, mode)
	assert(mode == "w")
	return { write = function(_, text) saved = (saved or "") .. text end, close = function() end }
end
os.rename = function() return true end
events["config.unload"][1]()
io.open, os.rename = real_open, real_rename
assert(saved:find("eDP-1\t2\t2\n", 1, true))
assert(saved:find("HDMI-A-1\t2\t5\n", 1, true))

for key, direction in pairs({ Left = "l", H = "l", Right = "r", L = "r", Up = "u", K = "u", Down = "d", J = "d" }) do
	binds["SUPER + ALT + SHIFT + " .. key].action()
	assert(last("workspace.move").monitor == direction)
	assert(last("workspace.move").workspace == workspace, "transfer the whole active workspace")
end

local c = { mapped = true, at = { x = 410, y = 30 }, size = { x = 200, y = 700 }, layout = { name = "scrolling" } }
local offscreen = { mapped = true, at = { x = -400, y = 30 }, size = { x = 200, y = 700 }, layout = { name = "scrolling" } }
windows = { a, b, c, offscreen }
nav.center_visible()
assert(last("layout") == "move +185", "center only viewport-intersecting columns using logical reserved space")
special = { special = true, tiled_layout = "scrolling", monitor = monitor }
calls = {}
nav.center_visible()
assert(#calls == 0, "do not move the regular tape behind a special workspace")
special = nil

active = a
nav.resize_height(0.1)
assert(last("window.resize").y == 76, "height changes use the logical workarea")
nav.reset_height()
assert(last("window.resize").y == 380 - 2 * expected_in)
calls = {}
nav.pin_floating()
assert(#calls == 0, "never silently float a tiled window for pinning")
a.floating = true
nav.pin_floating()
last("window.pin")
a.floating = false

events["window.urgent"][1](a)
assert(last("window.tag").tag == "+niri-urgent")
events["window.active"][1](a)
assert(last("window.tag").tag == "-niri-urgent")

local count = 0
for key in pairs(binds) do
	count = count + 1
	if os.getenv("PRINT_BINDINGS") then print("BIND\t" .. key) end
end
assert(count >= 100)
print("Offline config/helper tests passed (" .. selected .. ": " .. count .. " unique bindings)")
if os.getenv("PRINT_PLUGIN_OPTIONS") then
	for key, value in pairs(options) do
		if key:match("^plugin%.scrolloverview%.") then print("PLUGIN_OPTION\t" .. key .. "\t" .. type(value) .. "\t" .. tostring(value)) end
	end
end
