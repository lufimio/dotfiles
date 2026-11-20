-- Runtime control:
-- hyprctl repl 'return require("hyprland.keybinds.recording").toggle()'
local M = { enabled = true }
local bindings = {
	hl.bind("ALT + D", hl.dsp.exec_cmd("obs-cmd audio toggle Mic/Aux"), { description = "Toggle OBS Microphone" }),
	hl.bind("SHIFT + KP_End", hl.dsp.exec_cmd("obs-cmd trigger-hotkey hotkey_split"), { description = "LiveSplit Split" }),
	hl.bind("SHIFT + KP_Next", hl.dsp.exec_cmd("obs-cmd trigger-hotkey hotkey_reset"), { description = "LiveSplit Reset" }),
	hl.bind("SHIFT + KP_Up", hl.dsp.exec_cmd("obs-cmd trigger-hotkey hotkey_undo"), { description = "LiveSplit Undo" }),
	hl.bind("SHIFT + KP_Down", hl.dsp.exec_cmd("obs-cmd trigger-hotkey hotkey_skip"), { description = "LiveSplit Skip" }),
	hl.bind("SHIFT + KP_Begin", hl.dsp.exec_cmd("obs-cmd trigger-hotkey hotkey_pause"), { description = "LiveSplit Pause" }),
	hl.bind("SHIFT + KP_Left", hl.dsp.exec_cmd("obs-cmd trigger-hotkey hotkey_previous_comparison"), { description = "LiveSplit Previous Comparison" }),
	hl.bind("SHIFT + KP_Right", hl.dsp.exec_cmd("obs-cmd trigger-hotkey hotkey_next_comparison"), { description = "LiveSplit Next Comparison" }),
	hl.bind("SHIFT + KP_Home", hl.dsp.exec_cmd("obs-cmd trigger-hotkey hotkey_toggle_timing_method"), { description = "LiveSplit Toggle Timing Method" }),
}

function M.set_enabled(enabled)
	assert(type(enabled) == "boolean", "enabled must be true or false")
	for _, binding in ipairs(bindings) do binding:set_enabled(enabled) end
	M.enabled = enabled
	hl.notification.create({ text = "OBS/LiveSplit bindings " .. (enabled and "enabled" or "disabled"), timeout = 2000 })
	return enabled
end

function M.toggle()
	return M.set_enabled(not M.enabled)
end

return M
