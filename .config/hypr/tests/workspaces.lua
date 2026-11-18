-- Realistic workspace lifecycle/ID mocks, including collisions and dispatcher failures.
-- lua tests/workspaces.lua (no compositor, live cache, or user files touched).
package.path = "./?.lua;./?/init.lua;" .. package.path
local function session(seed, cached)
	local s = { spaces = seed, monitors = {}, events = {}, timers = {}, rules = {}, gestures = {}, calls = {}, notices = {} }
	s.submap = ""
	local seen = {}
	for _, space in ipairs(seed) do
		if not seen[space.monitor.name] then
			s.monitors[#s.monitors + 1] = space.monitor
			seen[space.monitor.name] = true
		end
	end
	s.active = seed[1]
	s.monitor = seed[1] and seed[1].monitor
	local function lookup(id)
		for _, space in ipairs(s.spaces) do if space.id == id then return space end end
	end
	function s.emit(event)
		for _, callback in ipairs(s.events[event] or {}) do callback() end
	end
	function s.flush()
		local iterations = 0
		while #s.timers > 0 do
			iterations = iterations + 1
			assert(iterations < 10, "recursive event/timer loop")
			local timers = s.timers
			s.timers = {}
			for _, callback in ipairs(timers) do callback() end
		end
	end
	local function dispatch(name)
		return function(args) return { name = name, args = args } end
	end
	hl = {
		get_current_submap = function() return s.submap end,
		get_workspaces = function()
			local result = {}
			for i, space in ipairs(s.spaces) do result[i] = space end
			return result
		end,
		get_monitors = function() return s.monitors end,
		get_workspace = lookup,
		get_active_workspace = function() return s.active end,
		get_active_special_workspace = function() return s.special end,
		get_active_monitor = function() return s.monitor end,
		get_config = function(key)
			if key == "gestures.workspace_swipe_use_r" then return true end
			if key == "gestures.workspace_swipe_invert" then return s.inverted ~= false end
		end,
		config = function() end,
		on = function(event, callback)
			s.events[event] = s.events[event] or {}
			s.events[event][#s.events[event] + 1] = callback
		end,
		timer = function(callback)
			s.timers[#s.timers + 1] = callback
			return {}
		end,
		workspace_rule = function(spec)
			assert(not spec.default_name, "ordinary workspaces must keep native numeric labels")
			local rule = { spec = spec, enabled = true }
			function rule:is_enabled() return self.enabled end
			function rule:set_enabled(value) self.enabled = value end
			s.rules[#s.rules + 1] = rule
			return rule
		end,
		gesture = function(spec)
			local old = s.gestures[spec.direction]
			if spec.action == "unset" then
				assert(old and old.scale == spec.scale, "must remove exact old gesture")
				s.gestures[spec.direction] = nil
			else
				assert(not old, "overlapping gestures")
				s.gestures[spec.direction] = spec
			end
		end,
		notification = { create = function(spec) s.notices[#s.notices + 1] = spec end },
		dsp = { workspace = { change_id = dispatch("id"), move = dispatch("monitor") },
			window = { move = dispatch("window") }, focus = dispatch("focus") },
		dispatch = function(action)
			s.calls[#s.calls + 1] = action
			local args = action.args
			if action.name == "id" then
				if s.fail and s.fail(action) then return { success = false } end
				assert(not lookup(args.id), "ID collision")
				local space = assert(lookup(args.workspace), "unknown workspace")
				space.id, space.name = args.id, tostring(args.id)
				-- Property-refresh callbacks may be emitted synchronously by mocks;
				-- neither recursive synchronization nor stale-ID adoption is allowed.
				s.emit("config.props_refreshed")
			elseif action.name == "focus" or action.name == "window" then
				local space = lookup(args.workspace)
				if not space then
					local owner
					for _, rule in ipairs(s.rules) do
						if rule.enabled and tonumber(rule.spec.workspace) == args.workspace then owner = rule.spec.monitor end
					end
					assert(owner == s.monitor.name, "new workspace has stale/wrong monitor rule")
					space = { id = args.workspace, name = tostring(args.workspace), monitor = s.monitor }
					s.spaces[#s.spaces + 1] = space
					s.emit("workspace.created")
				end
				s.active = space
				s.emit("workspace.active")
			elseif action.name == "monitor" then
				assert(args.workspace == s.active)
				args.workspace.monitor = assert(s.transfer_target)
				s.emit("workspace.move_to_monitor")
			end
			return { success = true }
		end,
	}
	local real_open = io.open
	io.open = function()
		if not cached then return nil end
		return { lines = function() return cached:gmatch("[^\n]+") end, close = function() end }
	end
	package.loaded["hyprland.workspaces"] = nil
	package.loaded["hyprland.gestures"] = nil
	s.module = require("hyprland.workspaces")
	io.open = real_open
	function s.check_rules()
		local active = {}
		for _, rule in ipairs(s.rules) do
			if rule.enabled then
				local id = tonumber(rule.spec.workspace)
				assert(not active[id], "multiple enabled rules for one numeric ID")
				active[id] = rule.spec.monitor
				local space = lookup(id)
				assert(not space or space.monitor.name == rule.spec.monitor, "stale enabled rule")
			end
		end
	end
	return s
end

local laptop = { name = "eDP-1", x = 0, y = 0 }
local external = { name = "HDMI-A-1", x = 1000, y = 0 }
local function ws(id, monitor) return { id = id, name = tostring(id), monitor = monitor } end

-- Mixed actual IDs, preserved local order, a cycle, native names and window identity.
local a, b, c, d = ws(4, laptop), ws(1, external), ws(2, laptop), ws(3, external)
local capture = { name = "dynamic-cast", monitor = laptop }
local scratch = { name = "magic", special = true, monitor = laptop }
local window = { workspace = a }
local s = session({ a, b, c, d, capture, scratch }, "eDP-1\t1\t4\neDP-1\t2\t2\nHDMI-A-1\t1\t1\nHDMI-A-1\t2\t3\n")
s.emit("config.reloaded")
s.emit("workspace.active")
assert(#s.timers == 1, "coalesce lifecycle events")
s.flush()
assert(a.id == 1 and c.id == 2 and b.id == 3 and d.id == 4, "cluster actual IDs in local order")
assert(window.workspace == a and s.active == a, "do not recreate workspaces or move windows/focus")
assert(a.name == "1" and capture.id == nil and scratch.id == nil)
assert(type(s.gestures.down.action) == "table", "block previous/capture boundary")
assert(s.gestures.up.action == "workspace", "keep native smooth next gesture")
assert(s.gestures.up.scale == -0.8 and s.gestures.down.scale == 0.8, "preserve vertical signs with the tuned scale")
s.check_rules()
local count = #s.calls
s.module.sync()
assert(#s.calls == count, "idempotent defragmentation")

-- Adding on an earlier monitor shifts the later cluster, without losing shortcuts.
s.module.number(3)
s.flush()
local third = s.active
assert(third.id == 3 and b.id == 4 and d.id == 5)
s.monitor, s.active = external, b
s.module.number(2)
assert(s.active == d, "preserve local assignment after another cluster expands")
s.check_rules()

-- All transfer directions dispatch whole workspace moves; reconcile both outputs.
for _, direction in ipairs({ "l", "r", "u", "d" }) do
	s.transfer_target = s.active.monitor == external and laptop or external
	s.module.move_monitor(direction)
	assert(s.calls[#s.calls].name == "monitor" and s.calls[#s.calls].args.monitor == direction)
	s.flush()
	s.check_rules()
end

-- Missing local slots require discrete navigation; after insertion native resumes.
local first, ninth = ws(1, laptop), ws(2, laptop)
s = session({ first, ninth, capture }, "eDP-1\t1\t1\neDP-1\t9\t2\n")
s.module.sync()
local gesture = s.gestures.up.action
assert(type(gesture) == "table", "native would skip local numbers 2..8")
gesture.start()
gesture.update({ delta = { y = -200 } })
gesture.finish({ cancelled = true })
assert(s.active == first, "cancelled fallback must do nothing")
gesture.start()
for _ = 1, 5 do gesture.update({ delta = { y = -2 } }) end
gesture.finish({ cancelled = false })
assert(s.active == first, "short fallback must do nothing")
gesture.start()
gesture.update({ delta = { y = -200 } })
gesture.finish({ cancelled = false })
s.flush()
local second = s.active
assert(second ~= ninth and second.id == 2 and ninth.id == 3)
s.active = first
s.module.sync()
assert(s.gestures.up.action == "workspace", "return to native when orders agree")
s.inverted = false
s.module.sync()
assert(s.gestures.down.action == "workspace", "respect swipe inversion")

-- Native r+1 creates after a foreign cluster; adopt/recluster without moving focus.
a, b = ws(1, laptop), ws(2, external)
s = session({ a, b, capture })
s.module.sync()
assert(s.gestures.up.action == "workspace")
local native_created = ws(3, laptop)
s.spaces[#s.spaces + 1] = native_created
s.active = native_created
s.emit("workspace.created")
s.emit("workspace.active")
s.flush()
assert(native_created.id == 2 and b.id == 3 and s.active == native_created)
s.module.number(2)
assert(s.active == native_created)
s.check_rules()

-- Unplug: forget disconnected reservations, adopt migrated workspaces, recluster.
a, b = ws(1, laptop), ws(2, external)
s = session({ a, b })
s.module.sync()
b.monitor, s.monitors = laptop, { laptop }
s.emit("monitor.removed")
s.flush()
s.module.number(2)
assert(s.active == b)
s.check_rules()

-- An external ID change is picked up by the deferred property-refresh hook.
b.id, b.name = 50, "50"
s.emit("config.props_refreshed")
s.flush()
s.check_rules()
assert(b.id < 50)

-- Fail in phase two, after one final assignment: reverse the journal safely.
a, b = ws(2, laptop), ws(1, external)
s = session({ a, b }, "eDP-1\t1\t2\nHDMI-A-1\t1\t1\n")
local attempts = 0
s.fail = function()
	attempts = attempts + 1
	return attempts == 4
end
s.module.sync()
assert(a.id == 2 and b.id == 1, "rollback must restore original IDs without collisions")
assert(#s.notices == 1, "surface transaction failure")
s.check_rules()
count = #s.calls
s.module.sync()
assert(#s.calls == count, "suspend automation after failed transaction")

-- Fail in phase one and also exercise recovery when rollback itself is rejected.
for _, failures in ipairs({ { [2] = true }, { [4] = true, [5] = true } }) do
	a, b = ws(2, laptop), ws(1, external)
	s = session({ a, b }, "eDP-1\t1\t2\nHDMI-A-1\t1\t1\n")
	attempts = 0
	s.fail = function()
		attempts = attempts + 1
		return failures[attempts]
	end
	s.module.sync()
	assert(a.id ~= b.id and #s.notices == 1)
	s.check_rules()
	s.module.number(1)
	assert(s.active == a, "recover mapping from actual IDs even if rollback fails")
end

-- Temporary IDs need not be above the largest ID (the signed-ID limit is valid).
a = ws(2147483647, laptop)
s = session({ a })
s.module.sync()
assert(a.id == 1)
s.check_rules()

-- Don't renumber or dispatch workspace actions underneath an overview drag.
a, b = ws(2, laptop), ws(1, external)
s = session({ a, b }, "eDP-1\t1\t2\nHDMI-A-1\t1\t1\n")
s.submap = "scrolloverview"
s.module.sync()
s.emit("workspace.created")
s.flush()
assert(a.id == 2 and b.id == 1 and #s.calls == 0)
s.module.number(2)
s.module.step("down")
s.module.move_monitor("r")
assert(#s.calls == 0, "overview owns input and workspace identities")
s.submap = ""
s.emit("keybinds.submap")
s.flush()
assert(a.id == 1 and b.id == 2, "automatically reconcile deferred changes after overview input ends")
s.check_rules()

-- Named/special workspaces must not enter the dictionary or monitor-transfer path.
s.active = capture
count = #s.calls
s.module.step("down")
s.module.move_monitor("r")
assert(#s.calls == count)

-- --verify-config / no-output startup must not create event-loop timers.
s.monitors = {}
s.emit("config.reloaded")
assert(#s.timers == 0)
print("Workspace transaction/lifecycle/gesture tests passed")
