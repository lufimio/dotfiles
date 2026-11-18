-- https://wiki.hypr.land/0.57.0/configuring/core/config-options/

hl.config({
	general = {
		-- Hyprland adds this on both sides of an internal edge: 3 + 3 = 6.
		gaps_in = 3,
		gaps_out = 6,

		border_size = 2,

		col = {
			active_border = "rgb(ac82e9)",
			inactive_border = "rgb(d8cab8)",
		},

		resize_on_border = false,

		-- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
		allow_tearing = false,

		layout = "scrolling",
	},

	decoration = {
		rounding = 15,
		rounding_power = 2,

		-- Change transparency of focused and unfocused windows
		active_opacity = 1.0,
		inactive_opacity = 1.0,

		shadow = {
			enabled = true,
			-- Approximation of niri softness=10 / spread=5.
			range = 15,
			render_power = 3,
			offset = { 0, 0 },
			color = "rgba(1a1a1aee)",
		},

		blur = {
			enabled = true,
			size = 3,
			passes = 1,
			vibrancy = 0.1696,
		},
	},

	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		focus_on_activate = true,
	},

	binds = {
		workspace_back_and_forth = 2, -- Per monitor, like niri.
		movefocus_cycles_fullscreen = true,
		window_direction_monitor_fallback = false,
	},

	group = {
		col = { border_locked_active = "rgb(da70d6)" }, -- Manual urgent-palette fallback.
		groupbar = { disable_when_only = true },
	},
	xwayland = { enabled = true },
})
