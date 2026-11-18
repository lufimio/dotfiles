-- Top-left 4×4 logical pixels on each monitor.
-- Hover for roughly 300ms; leave the corner before triggering again.
if not require("hyprland.scrolloverview").enabled then
	return
end

local corner, ticks, fired = nil, 0, false

local timer = hl.timer(function()
	local pos = hl.get_cursor_pos()
	local monitor = hl.get_monitor_at_cursor()
	local hit = nil

	if pos and monitor then
		local x, y = pos.x - monitor.x, pos.y - monitor.y
		if x >= 0 and x < 4 and y >= 0 and y < 4 then
			hit = monitor.name
		end
	end

	if hit ~= corner then
		corner, ticks, fired = hit, 0, false
	end
	if not hit or fired then
		return
	end

	ticks = ticks + 1
	if ticks >= 1 then
		fired = true
		hl.dispatch(hl.plugin.scrolloverview.overview("toggle " .. hit))
	end
end, { timeout = 25, type = "repeat" })

hl.on("config.unload", function()
	timer:set_enabled(false)
end)
