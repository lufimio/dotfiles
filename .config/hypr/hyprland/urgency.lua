-- Hyprland 0.57.2 has an urgent event, but no urgent window-rule matcher.
-- The native tag survives config reloads; focusing clears the urgent styling.
local M = {}
local tag = "niri-urgent"

function M.theme()
	-- The selected shell exports its error palette color here. This is a palette source,
	-- not a claim that a locked group is an urgent window.
	local color = hl.get_config("group.col.border_locked_active") or "rgb(da70d6)"
	hl.window_rule({
		name = "niri-urgent-border",
		match = { tag = tag, focus = false },
		border_color = color,
	})
end

hl.on("window.urgent", function(window)
	if window and not window.active then
		hl.dispatch(hl.dsp.window.tag({ window = window, tag = "+" .. tag }))
	end
end)
hl.on("window.active", function(window)
	if window then
		hl.dispatch(hl.dsp.window.tag({ window = window, tag = "-" .. tag }))
	end
end)
hl.on("config.reloaded", M.theme)

return M
