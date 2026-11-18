-- yayuuu/hyprland-scroll-overview. Checked against the installed revision:
-- 3eb62e3e0093d54cbdcf4f58c831b5b53b3b1ff2 (Hyprland 0.57.2).
-- Only configure an already loaded plugin; never install/load/unload libraries.
local M = { enabled = false }
local shell = require("hyprland.shell")
for _, plugin in ipairs(hl.get_loaded_plugins()) do
	if plugin.name == "scrolloverview" then
		local api = hl.plugin.scrolloverview
		local ok, scale = pcall(hl.get_config, "plugin.scrolloverview.scale")
		M.enabled = api ~= nil and ok and type(scale) == "number"
		for _, name in ipairs({ "overview", "navigate", "window", "gesture" }) do
			M.enabled = M.enabled and type(api[name]) == "function"
		end
		break
	end
end

if not M.enabled then
	-- Same shell fallback as before; Noctalia's overview stays unbound.
	if shell.command("overview") then
		hl.bind("SUPER + Tab", hl.dsp.exec_cmd(shell.command("overview")), { description = "Overview" })
		hl.bind("SUPER + O", hl.dsp.exec_cmd(shell.command("overview")), { description = "Overview" })
		hl.gesture({
			fingers = 4,
			direction = "up",
			action = function()
				hl.exec_cmd(shell.command("overview"))
			end,
		})
	end
	return M
end

local api = hl.plugin.scrolloverview
hl.config({
	plugin = {
		scrolloverview = {
			scale = 0.5,
			layout = "vertical", -- Workspaces vertically, scrolling columns horizontally.
			workspace_gap = 100,
			gesture_distance = 240,
			wallpaper = 0, -- One global background, no repeated per-workspace wallpaper.
			wallpaper_layer = "auto",
			blur = false,
			shadow = { enabled = false }, -- Match the niri overview's disabled shadows.
			cross_monitor_drag = false, -- Don't adopt unrelated native move drags.
			input = {
				scrolling_mode = 2, -- Wheel: vertical = workspace, horizontal = columns.
				scroll_event_delay = 120,
				touchpad_scroll_factor = 1.25,
				drag_mode = 0, -- Primary drag moves windows, middle drag pans the tape.
				drag_threshold = 10,
			},
		},
	},
})

-- Factories return bind actions during config evaluation; they do not open UI.
hl.bind("SUPER + Tab", api.overview("toggle"), { description = "Scrolling Workspace Overview" })
hl.bind("SUPER + O", api.overview("toggle"), { description = "Scrolling Workspace Overview" })

hl.define_submap("scrolloverview", function()
	hl.bind("Left", api.navigate("left"), { description = "Overview Left", repeating = true })
	hl.bind("H", api.navigate("left"), { description = "Overview Left", repeating = true })
	hl.bind("Right", api.navigate("right"), { description = "Overview Right", repeating = true })
	hl.bind("L", api.navigate("right"), { description = "Overview Right", repeating = true })
	hl.bind("Up", api.navigate("up"), { description = "Overview Up", repeating = true })
	hl.bind("K", api.navigate("up"), { description = "Overview Up", repeating = true })
	hl.bind("Down", api.navigate("down"), { description = "Overview Down", repeating = true })
	hl.bind("J", api.navigate("down"), { description = "Overview Down", repeating = true })
	hl.bind("SUPER + Left", api.navigate("left"), { description = "Overview Left", repeating = true })
	hl.bind("SUPER + H", api.navigate("left"), { description = "Overview Left", repeating = true })
	hl.bind("SUPER + Right", api.navigate("right"), { description = "Overview Right", repeating = true })
	hl.bind("SUPER + L", api.navigate("right"), { description = "Overview Right", repeating = true })
	hl.bind("SUPER + Up", api.navigate("up"), { description = "Overview Up", repeating = true })
	hl.bind("SUPER + K", api.navigate("up"), { description = "Overview Up", repeating = true })
	hl.bind("SUPER + Down", api.navigate("down"), { description = "Overview Down", repeating = true })
	hl.bind("SUPER + J", api.navigate("down"), { description = "Overview Down", repeating = true })
	-- Close commits the keyboard-selected target. "select" alone uses the cursor.
	hl.bind("Return", api.overview("close"), { description = "Select Overview Window" })
	hl.bind("Escape", api.overview("close"), { description = "Close Overview" })
	hl.bind("SUPER + Tab", api.overview("close"), { description = "Close Overview" })
	hl.bind("SUPER + O", api.overview("close"), { description = "Close Overview" })
	hl.bind("mouse:272", function()
		api.overview("select")
		api.window("select")
		api.overview("close")
	end, { description = "Select Clicked Overview Window", mouse = true })
end)

api.gesture({ fingers = 4, direction = "vertical", action = "overview" })
return M
