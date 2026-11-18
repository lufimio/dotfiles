-- sandwichfarm/hyprexpo, not the retired upstream plugin.
-- Checked against the Hyprland 0.57.2 hyprpm pin:
-- d54a70dcb75bd6812dc4609815e57943eafa8f51. Installation/loading is separate.
--
-- Scrolling rows preserve native columns, proportions, and offscreen targets.
-- There is NO supported "scrolling" overview_mode or configurable niri-style
-- zoom factor. "auto" selects the scrolling implementation; "grid" disables it.
local M = { enabled = false }
local shell = require("hyprland.shell")
local installed = false
for _, plugin in ipairs(hl.get_loaded_plugins()) do
	if plugin.name == "hyprexpo" then installed = true; break end
end

local api = installed and hl.plugin.hyprexpo
if api then
	-- Detect an older/different hyprexpo before setting unknown plugin options.
	local ok, mode = pcall(hl.get_config, "plugin.hyprexpo.overview_mode")
	local budget_ok, budget = pcall(hl.get_config, "plugin.hyprexpo.scrolling_thumbnail_budget")
	M.enabled = ok and type(mode) == "string" and budget_ok and type(budget) == "number"
	for _, name in ipairs({ "expo", "gesture", "kb_focus", "kb_confirm" }) do
		M.enabled = M.enabled and type(api[name]) == "function"
	end
end

if not M.enabled then
	-- Absent/incompatible plugin: preserve the selected shell's previous behavior.
	-- In particular, Noctalia keeps these shortcuts/gestures unbound.
	if shell.command("overview") then
		hl.bind("SUPER + Tab", hl.dsp.exec_cmd(shell.command("overview")), { description = "Overview" })
		hl.bind("SUPER + O", hl.dsp.exec_cmd(shell.command("overview")), { description = "Overview" })
		hl.gesture({
			fingers = 4, direction = "up",
			action = function() hl.exec_cmd(shell.command("overview")) end,
		})
	end
	return M
end

hl.config({
	plugin = {
		hyprexpo = {
			overview_mode = "auto",
			-- Capture resolution budget: 2 × monitor pixels, NOT a window-count
			-- limit. Offscreen columns remain in the scene. Raise to 4 for sharper
			-- thumbnails if GPU memory/bandwidth permit.
			scrolling_thumbnail_budget = 2,
			scrolling_input_debug = 0,
			show_cursor = 1,
			show_pinned_windows = 0, -- Avoid repeated PiP previews.
			-- No synchronous image decode/blur work when opening the overview.
			bg_image = "",
			bg_image_blur = 0,
			keynav_enable = 1,
			keynav_wrap_h = 0,
			keynav_wrap_v = 0,
			keynav_reading_order = 0, -- Spatial window/column navigation.
			-- Do not mistake visible-row indices (which may include named
			-- workspaces) for the keyboard dictionary's monitor-local numbers.
			number_key_mode = "passthrough",
			cancel_key = "none", -- Escape is handled by the explicit submap below.
			gesture_distance = 240,
			gesture_fingers = 0, -- Lua gestures below own registration, once.

			-- GRID FALLBACK ONLY (non-scrolling workspaces): enumerate actual
			-- workspaces on this monitor, not a fixed 3×3 block of global IDs.
			dynamic_grid = 1,
			fill_gaps = 0,
			mru_sort = 0,
			cross_monitor = 0,
			workspace_method = "center current",
			bg_col = "rgb(262626)", -- Native scrolling has its own fixed backdrop.
			gaps_in = 6,
			label_text_mode = "id",
			show_workspace_numbers = 1,
			label_font_size = 16,
			label_position = "top-left",
			label_bg_enable = 0,
		},
	},
})

-- Native overview works with either shell; no DMS IPC or external helper process.
hl.bind("SUPER + Tab", function() api.expo("toggle") end, { description = "Scrolling Workspace Overview" })
hl.bind("SUPER + O", function() api.expo("toggle") end, { description = "Scrolling Workspace Overview" })

hl.define_submap("hyprexpo", function()
	hl.bind("Left", function() api.kb_focus("left") end, { description = "Overview Left", repeating = true })
	hl.bind("H", function() api.kb_focus("left") end, { description = "Overview Left", repeating = true })
	hl.bind("Right", function() api.kb_focus("right") end, { description = "Overview Right", repeating = true })
	hl.bind("L", function() api.kb_focus("right") end, { description = "Overview Right", repeating = true })
	hl.bind("Up", function() api.kb_focus("up") end, { description = "Overview Up", repeating = true })
	hl.bind("K", function() api.kb_focus("up") end, { description = "Overview Up", repeating = true })
	hl.bind("Down", function() api.kb_focus("down") end, { description = "Overview Down", repeating = true })
	hl.bind("J", function() api.kb_focus("down") end, { description = "Overview Down", repeating = true })
	-- Keep the existing Super+navigation muscle memory without moving real columns.
	hl.bind("SUPER + Left", function() api.kb_focus("left") end, { description = "Overview Left", repeating = true })
	hl.bind("SUPER + H", function() api.kb_focus("left") end, { description = "Overview Left", repeating = true })
	hl.bind("SUPER + Right", function() api.kb_focus("right") end, { description = "Overview Right", repeating = true })
	hl.bind("SUPER + L", function() api.kb_focus("right") end, { description = "Overview Right", repeating = true })
	hl.bind("SUPER + Up", function() api.kb_focus("up") end, { description = "Overview Up", repeating = true })
	hl.bind("SUPER + K", function() api.kb_focus("up") end, { description = "Overview Up", repeating = true })
	hl.bind("SUPER + Down", function() api.kb_focus("down") end, { description = "Overview Down", repeating = true })
	hl.bind("SUPER + J", function() api.kb_focus("down") end, { description = "Overview Down", repeating = true })
	hl.bind("Return", function() api.kb_confirm() end, { description = "Select Overview Window" })
	hl.bind("Escape", function() api.expo("cancel") end, { description = "Cancel Overview" })
	hl.bind("SUPER + Tab", function() api.expo("cancel") end, { description = "Close Overview" })
	hl.bind("SUPER + O", function() api.expo("cancel") end, { description = "Close Overview" })
end)

-- Leave three-finger tape/workspace navigation untouched. These are native
-- follow-your-finger plugin gestures, not discrete shell IPC callbacks.
api.gesture({ fingers = 4, direction = "up", action = "expo" })
api.gesture({ fingers = 4, direction = "down", action = "cancel" })
return M
