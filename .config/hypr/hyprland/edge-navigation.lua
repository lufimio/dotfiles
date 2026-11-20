-- Standalone native plugin; no ScrollOverview modification or input grabbing.
local M = { enabled = false }
local api = hl.plugin.edge_navigation
if not api or type(api.configure) ~= "function" then
	return M
end

-- Hot-corner actions are ordinary Lua callbacks and may invoke any hl dispatcher.
local corners = {
	top_left = {
		enabled = true,
		size = 12,
		delay = 50,
		during_drag = true,
		action = function(monitor)
			hl.dispatch(hl.plugin.scrolloverview.overview("toggle " .. monitor))
		end,
	},
	top_right = { enabled = false, size = 4, delay = 0, during_drag = false },
	bottom_left = { enabled = false, size = 4, delay = 0, during_drag = false },
	bottom_right = { enabled = false, size = 4, delay = 0, during_drag = false },
}
local native_corners = {}
for name, corner in pairs(corners) do
	native_corners[name] = {
		enabled = corner.enabled and type(corner.action) == "function",
		size = corner.size,
		delay = corner.delay,
		during_drag = corner.during_drag,
	}
end
local ok, reason = api.configure({
	enabled = true,
	drag_edges = true,
	external_drags = true,
	window_drags = true, -- Native move drags only; resizing never navigates.
	edge_size = 16, -- Logical pixels inward from the physical monitor edges.
	edge_delay = 500, -- Initial dwell, milliseconds; zero is immediate.
	repeat_delay = 700, -- Subsequent discrete focus/workspace steps.
	smooth_scroll = true, -- Continuous horizontal camera tracking after dwell.
	scroll_speed = 900, -- Logical pixels/second, independent of event frequency.
	monitors = {}, -- Empty = all; otherwise an allowlist of connector names.
	corners = native_corners,
})
assert(ok, "edge-navigation: " .. tostring(reason))
M.enabled = true
hl.on("edge-navigation.action", function(action, monitor)
	local corner = corners[action]
	if corner then
		if corner.enabled and corner.action then
			corner.action(monitor)
		end
	elseif action == "workspace_up" or action == "workspace_down" then
		require("hyprland.workspaces").drag_edge_step(action == "workspace_up" and "up" or "down", monitor)
	end
end)
return M
