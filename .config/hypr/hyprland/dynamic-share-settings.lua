-- Dynamic Share configuration, included directly by hyprland.lua.
-- Production sharing bindings live in hyprland/keybinds/capture.lua.
local settings = {
	empty_text = "Nothing is being shared", -- Plain text; edit this message freely.
	empty_font_size = 32,
	sizing = "source", -- "fixed" retains the helper-sized canvas for picky encoders.
	picker = {
		backend = "xdph", -- Stock graphical dialog; use "dmenu" for the command below.
		command = "vicinae dmenu -p 'Dynamic Share'", -- stdin: lines; stdout: chosen line.
	},
	indicator = {
		enabled = true, -- Experimental local indicator; capture exclusion needs live testing.
		windows = true,
		workspaces = true,
		monitors = true,
		-- Styles are independent. Sizes are logical pixels; width/size 0 disables that effect.
		window = {
			border_color = "#f38ba8",
			border_width = 2,
			glow_color = "#f38ba8",
			glow_size = 16,
			glow_opacity = 0.5,
			radius = 15,
		},
		workspace = { -- Outlines the work area, excluding shell-reserved panels/bars.
			border_color = "#f38ba8",
			border_width = 0,
			glow_color = "#f38ba8",
			glow_size = 24,
			glow_opacity = 0.75,
			radius = 0,
		},
		monitor = { -- Outlines the entire output, including its shell.
			border_color = "#f38ba8",
			border_width = 0,
			glow_color = "#f38ba8",
			glow_size = 24,
			glow_opacity = 0.75,
			radius = 0,
		},
	},
}
hl.workspace_rule({ workspace = "special:dynamic-share-anchor", persistent = true })
hl.window_rule({
	name = "dynamic-share-idle-anchor",
	match = { initial_class = "^local\\.hypr\\.dynamic-share$" },
	workspace = "special:dynamic-share-anchor silent",
	float = true,
	size = "1280 720",
	no_initial_focus = true,
	no_anim = true,
	border_size = 0,
	rounding = 0,
	no_shadow = true,
})
-- Configure/start only an already loaded plugin; the login loader is separate.
if hl.plugin.dynamic_share then
	local configured, reason = hl.plugin.dynamic_share.configure(settings)
	if not configured then
		hl.notification.create({ text = reason, timeout = 5000 })
	end
	local ok, message = hl.plugin.dynamic_share.start()
	if not ok then
		hl.notification.create({ text = message, timeout = 5000 })
	end
end
return settings -- Also used by the production picker keybind; not just native settings.
