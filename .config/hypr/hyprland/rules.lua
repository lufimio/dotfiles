-- https://wiki.hypr.land/0.57.0/configuring/core/rules/window-rules/
-- General rules first; DMS-managed windowrules.lua is loaded last.
hl.window_rule({ name = "suppress-maximize-events", match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({
	name = "fix-xwayland-drags",
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

-- niri enables window background blur explicitly for terminals, not every app.
hl.window_rule({ name = "default-no-window-blur", match = { class = ".*" }, no_blur = true })
hl.window_rule({
	name = "terminal-blur",
	match = { class = "^(com\\.mitchellh\\.ghostty|kitty)$" },
	no_blur = false,
	xray = false,
})
hl.window_rule({ name = "floating-no-xray", match = { float = true }, xray = false })
hl.window_rule({ name = "dms-no-xray", match = { class = "^dev\\.duxlabs\\.shell$" }, xray = false })
hl.window_rule({
	name = "vicinae-settings",
	match = { class = "^vicinae$", title = "^Vicinae Settings$" },
	float = true,
	border_size = 0,
	xray = false,
})
hl.window_rule({
	name = "kando-menu",
	match = { class = "^menu\\.kando\\.Kando$", title = ".*Kando Menu.*" },
	float = true,
	border_size = 0,
	no_shadow = true,
	move = { 0, 0 },
})
hl.window_rule({
	name = "steam-notifications",
	match = { class = ".*steam.*", title = [[^notificationtoasts_\d+_desktop$]] },
	no_initial_focus = true,
	move = "monitor_w-window_w monitor_h-window_h",
})
hl.window_rule({
	name = "portal-dialogs",
	match = { class = ".*[xX]dg-[dD]esktop-[pP]ortal-.*" },
	border_size = 0,
	no_shadow = true,
})
hl.window_rule({
	name = "nautilus-previewer",
	match = { class = "org\\.gnome\\.NautilusPreviewer" },
	float = true,
	size = "monitor_w*0.5 monitor_h*0.5",
	no_shadow = true,
})
hl.window_rule({
	name = "nautilus-image-tools",
	match = { class = "org\\.gnome\\.Nautilus", title = ".*(Resize|Rotate) Images.*" },
	no_shadow = true,
	border_size = 0,
})
hl.window_rule({
	name = "picture-in-picture",
	match = { title = "^[pP]icture[- ]in[- ][pP]icture$" },
	float = true,
	size = "monitor_w*0.3 monitor_h*0.3",
	move = "monitor_w-window_w-7 monitor_h-window_h-7",
})

for _, namespace in ipairs({ "^dms:.*$", "^vicinae$" }) do
	hl.layer_rule({ name = "no-xray-" .. namespace, match = { namespace = namespace }, xray = false })
end

hl.layer_rule({ name = "disable-vicinae-animation", match = { namespace = "^vicinae$" }, no_anim = true })

-- scrolling_width accepts proportions only. Native resize at map preserves 500px.
hl.on("window.open", function(window)
	if window and window.class == "LiveSplitOne" and window.title == "LiveSplit One" then
		hl.dispatch(hl.dsp.window.resize({ window = window, x = 500, y = window.size.y, relative = false }))
	end
end)

require("hyprland.urgency")
