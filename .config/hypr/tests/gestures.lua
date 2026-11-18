-- Release-decision tests for dictionary fallbacks. Native rendering is not mocked.
package.path = "./?.lua;./?/init.lua;" .. package.path
local options, horizontal, result = {}, nil, nil
local origin, active = {}, nil
active = origin
hl = {
	config = function(values)
		for key, value in pairs(values.gestures) do options["gestures." .. key] = value end
	end,
	gesture = function(spec) horizontal = spec end,
	get_config = function(key) return options[key] end,
	get_active_workspace = function() return active end,
}
local gestures = require("hyprland.gestures")
assert(horizontal.action == "scroll_move" and horizontal.scale == 0.8)
assert(options["gestures.workspace_swipe_distance"] == 360)
assert(options["gestures.workspace_swipe_cancel_ratio"] == 0.2)
assert(options["gestures.workspace_swipe_min_speed_to_force"] == 8)
assert(options["gestures.workspace_swipe_forever"] == false)
local function swipe(deltas, cancelled, change_workspace)
	result, active = nil, origin
	local handler = gestures.workspace_fallback(function(direction) result = direction end)
	handler.start()
	for _, delta in ipairs(deltas) do handler.update({ delta = { y = delta } }) end
	if change_workspace then active = {} end
	handler.finish({ cancelled = cancelled or false })
	return result
end
local slow = {}
for i = 1, 50 do slow[i] = -2 end
assert(swipe(slow) == "down", "100 raw units commit, versus the previous 150-unit threshold")
assert(swipe({ -20 }) == "down", "short decisive flick uses native-style velocity forcing")
assert(swipe({ -1, -1, -1, -1, -1 }) == nil, "ignore gentle jitter")
assert(swipe({ -100 }, true) == nil, "respect explicit cancellation")
assert(swipe({ -100 }, false, true) == nil, "don't act after workspace focus changes")
assert(swipe({ 20 }) == "up")
options["gestures.workspace_swipe_invert"] = false
assert(swipe({ 20 }) == "down", "respect inversion")
options["gestures.workspace_swipe_min_speed_to_force"] = 0
assert(swipe({ 20 }) == nil, "zero disables velocity forcing")
print("Gesture sensitivity/cancellation tests passed")
