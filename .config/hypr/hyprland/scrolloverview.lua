-- Configure the pinned local v4 plugin only. No shell/older-plugin fallback.
local M = { enabled = false }
local api = hl.plugin.scrolloverview
for _, plugin in ipairs(hl.get_loaded_plugins()) do
	if plugin.name == "scrolloverview" and plugin.version == "3eb62e3e0093-local-input-v4" then
		M.enabled = api ~= nil
		break
	end
end
if not M.enabled then
	return M
end

hl.config({
	plugin = {
		scrolloverview = {
			scale = 0.5,
			layout = "vertical", -- Workspaces vertically, columns horizontally.
			workspace_gap = 100,
			gesture_distance = 240,
			wallpaper = 0,
			wallpaper_layer = "auto",
			blur = false,
			shadow = { enabled = false },
			cross_monitor_drag = false,
			insert_workspaces = true, -- Drop in a card gap to insert a numbered workspace.
			hide_special_workspaces = true,
			hide_named_workspaces = false,
			input = {
				scrolling_mode = 2, -- Wheel: vertical = workspace, horizontal = columns.
				scroll_event_delay = 120,
				touchpad_scroll_factor = 1.25,
				right_drag_pan = true, -- Left moves windows, right pans, middle is ignored.
				drag_threshold = 4,
				column_scroll_factor = 1.5,
				column_swipe_threshold = 12,
				-- Match normal three-finger gesture tuning.
				right_drag_column_scale = 0.8,
				right_drag_workspace_scale = 0.8,
				right_drag_workspace_distance = 360,
				right_drag_cancel_ratio = 0.2,
				right_drag_min_speed_to_force = 8,
				right_drag_forever = false,
				right_drag_snap_to_grid = true,
				right_drag_snap_cursor = false,
				right_drag_velocity_decay = 4.0,
				right_drag_max_projection = 2.0,
				right_drag_velocity_smooth = 0.35,
				shift_scroll_columns = true,
				drag_edge_navigation = true, -- File and window drags.
				drag_edge_size = 48,
				drag_edge_speed = 900,
				drag_hover_activate = true, -- External drags only; false disables it.
				drag_hover_delay = 600, -- Milliseconds; 0 means immediate.
			},
		},
	},
})
hl.on("scrolloverview.insert-workspace", function(window, before)
	local ok, reason = pcall(require("hyprland.workspaces").overview_insert, window, before)
	if not ok then
		hl.notification.create({ text = "Workspace insertion failed: " .. tostring(reason), timeout = 5000 })
	end
end)
require("hyprland.keybinds.overview")(api)
api.gesture({ fingers = 4, direction = "vertical", action = "overview" })
return M
