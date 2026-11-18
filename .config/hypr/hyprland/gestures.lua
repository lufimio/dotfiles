-- Native three-finger tuning. No artificial per-column limit is exposed by
-- Hyprland 0.57.2's scroll_move gesture: momentum projection is compositor code.
local M = {
	horizontal_scale = 0.8, -- Mildly reduce travel and fling projection, keep tracking.
	workspace_scale = 0.8,
}

hl.config({
	gestures = {
		workspace_swipe_use_r = true,
		-- Keep room for a visible settling animation after a fast/short flick.
		-- Commitment needs only 20% of 360 / 0.8 = ~90 raw delta units
		-- (previously 150), or the lower native velocity-forcing threshold.
		workspace_swipe_distance = 360,
		workspace_swipe_cancel_ratio = 0.2,
		workspace_swipe_min_speed_to_force = 8,
		workspace_swipe_forever = false, -- One workspace per continuous gesture.
		scrolling = { move_snap_to_grid = true, move_snap_cursor = false },
	},
})
hl.gesture({ fingers = 3, direction = "horizontal", action = "scroll_move", scale = M.horizontal_scale })

-- Match native commitment rules in the rare dictionary-order fallback too.
-- Lua callbacks receive raw deltas; multiply explicitly, once.
function M.workspace_fallback(callback)
	local total, absolute, samples, origin = 0, 0, 0, nil
	return {
		start = function()
			total, absolute, samples, origin = 0, 0, 0, hl.get_active_workspace()
		end,
		update = function(event)
			local delta = event.delta.y * M.workspace_scale
			total, absolute, samples = total + delta, absolute + math.abs(delta), samples + 1
		end,
		finish = function(event)
			if event.cancelled or origin ~= hl.get_active_workspace() or math.abs(total) < 2 then return end
			local threshold = (hl.get_config("gestures.workspace_swipe_distance") or 360)
				* (hl.get_config("gestures.workspace_swipe_cancel_ratio") or 0.2)
			local force = hl.get_config("gestures.workspace_swipe_min_speed_to_force") or 8
			if math.abs(total) < threshold and not (force > 0 and samples > 0 and absolute / samples >= force) then return end
			local inverted = hl.get_config("gestures.workspace_swipe_invert")
			if inverted == nil then inverted = true end
			local delta = inverted and -total or total
			callback(delta < 0 and "up" or "down")
		end,
	}
end
return M
