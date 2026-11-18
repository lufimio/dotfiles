-- https://wiki.hypr.land/0.57.0/configuring/core/config-options/
hl.config({
	input = {
		kb_options = "lv5:caps_switch",
		numlock_by_default = true,
		repeat_delay = 400,
		repeat_rate = 50,
		follow_mouse = 1,
		sensitivity = 0,
		scroll_factor = 1,
		scroll_method = "2fg",
		touchpad = {
			tap_to_click = true,
			disable_while_typing = true,
			tap_and_drag = true,
			drag_lock = 1,
			natural_scroll = true,
			middle_button_emulation = true,
		},
	},
	cursor = {
		no_warps = true,
		warp_on_change_workspace = 0,
		warp_on_monitor_change = 0,
	},
})

require("hyprland.gestures")
-- workspaces.lua owns vertical gestures: native r±1 wherever local order agrees.
-- scrolloverview.lua owns the four-finger overview gesture (or shell fallback).
