-- (monitor connector, local number) -> actual numbered workspace ID.
-- IDs are compacted by monitor/local order; no fixed per-monitor ID ranges.
local M = {}
local gestures = require("hyprland.gestures")
local mapping, rule_pool, gesture_modes = {}, {}, {}
local syncing, suspended, pending = false, false, nil
local LIMIT = 2147483647
local cache = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/hypr-niri-workspaces.tsv"

do
	local file = io.open(cache, "r")
	if file then
		local used = {}
		for line in file:lines() do
			local monitor, number, id = line:match("^([^\t]+)\t(%d+)\t(%d+)$")
			number, id = tonumber(number), tonumber(id)
			if monitor and number > 0 and number <= LIMIT and id > 0 and id <= LIMIT and not used[id] then
				mapping[monitor] = mapping[monitor] or {}
				if not mapping[monitor][number] then
					mapping[monitor][number], used[id] = id, true
				end
			end
		end
		file:close()
	end
end

local function numbered(workspace)
	return workspace and not workspace.special and workspace.id and workspace.id > 0
end

local function overview_owns_input()
	-- Overview plugins clear drag ownership before leaving their submap. Never change
	-- IDs while its scrolling scene can still accept a positional drop.
	local submap = hl.get_current_submap()
	return submap == "scrolloverview" or submap == "hyprexpo"
end

local function local_number(monitor, id)
	for number, global_id in pairs(mapping[monitor] or {}) do
		if global_id == id then return number end
	end
end

local function free_number(numbers)
	local number = 1
	while numbers[number] do number = number + 1 end
	return number
end

local function used_ids()
	local used = {}
	for _, numbers in pairs(mapping) do
		for _, id in pairs(numbers) do used[id] = true end
	end
	for _, workspace in ipairs(hl.get_workspaces()) do
		if numbered(workspace) then used[workspace.id] = true end
	end
	return used
end

local function free_id(used)
	local id = 1
	while used[id] do id = id + 1 end
	assert(id <= LIMIT, "no free numbered workspace IDs")
	return id
end

local function reconcile()
	local monitors, live = {}, hl.get_workspaces()
	for _, monitor in ipairs(hl.get_monitors()) do monitors[monitor.name] = monitor end
	-- Unplugged reservations are dropped; Hyprland migrates their live workspaces.
	for name, numbers in pairs(mapping) do
		if not monitors[name] then
			mapping[name] = nil
		else
			for number, id in pairs(numbers) do
				local workspace = hl.get_workspace(id)
				if workspace and (not numbered(workspace) or not workspace.monitor or workspace.monitor.name ~= name) then
					numbers[number] = nil
				end
			end
		end
	end
	-- Existing local assignments survive. New/transferred workspaces fill a free slot.
	table.sort(live, function(a, b) return (a.id or 0) < (b.id or 0) end)
	for _, workspace in ipairs(live) do
		if numbered(workspace) and workspace.monitor then
			local name = workspace.monitor.name
			monitors[name] = workspace.monitor
			mapping[name] = mapping[name] or {}
			if not local_number(name, workspace.id) then
				mapping[name][free_number(mapping[name])] = workspace.id
			end
		end
	end
	return monitors
end

local function disable_rules()
	for _, rule in pairs(rule_pool) do
		if rule.handle:is_enabled() then rule.handle:set_enabled(false) end
	end
end

local function install_rules()
	local desired = {}
	for name, numbers in pairs(mapping) do
		for _, id in pairs(numbers) do desired[id .. "\t" .. name] = { id = id, monitor = name } end
	end
	for key, rule in pairs(rule_pool) do
		if not desired[key] and rule.handle:is_enabled() then rule.handle:set_enabled(false) end
	end
	for key, spec in pairs(desired) do
		local rule = rule_pool[key]
		if not rule then
			rule_pool[key] = { handle = hl.workspace_rule({ workspace = tostring(spec.id), monitor = spec.monitor }) }
		elseif not rule.handle:is_enabled() then
			rule.handle:set_enabled(true)
		end
	end
end

local function change_id(workspace, id)
	local result = hl.dispatch(hl.dsp.workspace.change_id({ workspace = workspace.id, id = id }))
	if (result and result.success == false) or workspace.id ~= id then
		error("could not change workspace ID to " .. id)
	end
end

local function defragment(monitors)
	if suspended then return end
	local names, entries, target = {}, {}, 0
	for name in pairs(mapping) do names[#names + 1] = name end
	-- Physical left-to-right, then top-to-bottom. Connector name breaks ties.
	table.sort(names, function(a, b)
		local ma, mb = monitors[a], monitors[b]
		if (ma.x or 0) ~= (mb.x or 0) then return (ma.x or 0) < (mb.x or 0) end
		if (ma.y or 0) ~= (mb.y or 0) then return (ma.y or 0) < (mb.y or 0) end
		return a < b
	end)
	local changed = false
	for _, name in ipairs(names) do
		local slots = {}
		for number in pairs(mapping[name]) do slots[#slots + 1] = number end
		table.sort(slots)
		for _, number in ipairs(slots) do
			local id = mapping[name][number]
			target = target + 1
			entries[#entries + 1] = { monitor = name, number = number, old = id, target = target, workspace = hl.get_workspace(id) }
			changed = changed or id ~= target
		end
	end
	if not changed then return end
	local temporary = used_ids()
	for _, entry in ipairs(entries) do temporary[entry.target] = true end
	-- Two phases: vacate all changing live IDs, then assign targets. No ID swaps,
	-- focus changes, window moves, workspace recreation, or custom display names.
	disable_rules()
	local journal = {}
	local ok, failure = pcall(function()
		for _, entry in ipairs(entries) do
			if entry.workspace and entry.old ~= entry.target then
				local id = free_id(temporary)
				temporary[id] = true
				change_id(entry.workspace, id)
				journal[#journal + 1] = { workspace = entry.workspace, before = entry.old }
			end
		end
		for _, entry in ipairs(entries) do
			if entry.workspace and entry.old ~= entry.target then
				local before = entry.workspace.id
				change_id(entry.workspace, entry.target)
				journal[#journal + 1] = { workspace = entry.workspace, before = before }
			end
		end
	end)
	if ok then
		for _, entry in ipairs(entries) do mapping[entry.monitor][entry.number] = entry.target end
	else
		-- Reverse successful operations, including completed final assignments.
		local restored = true
		for i = #journal, 1, -1 do
			local operation = journal[i]
			if not pcall(change_id, operation.workspace, operation.before) then restored = false end
		end
		if not restored then
			-- Retain actual workspace identities even after an unexpected rollback failure.
			local used = {}
			for _, entry in ipairs(entries) do
				if entry.workspace then
					mapping[entry.monitor][entry.number] = entry.workspace.id
					used[entry.workspace.id] = true
				end
			end
			for _, entry in ipairs(entries) do
				if not entry.workspace then
					local id = used[entry.old] and free_id(used) or entry.old
					mapping[entry.monitor][entry.number], used[id] = id, true
				end
			end
		end
		suspended = true -- Avoid repeated intrusive retries; reload to retry.
		hl.notification.create({ text = "Workspace defragmentation stopped; reload config to retry. " .. tostring(failure), timeout = 8000, icon = "warning" })
	end
end

-- r±1 skips live/reserved IDs on other monitors, but can still enter named
-- workspaces at the start. Use native motion only when its target agrees.
local function native_matches(step)
	if hl.get_config("gestures.workspace_swipe_use_r") == false then return false end
	local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
	if not numbered(workspace) or not workspace.monitor then return false end
	local name = workspace.monitor.name
	local number = local_number(name, workspace.id)
	if not number or number + step < 1 then return false end
	local blocked = {}
	for monitor, numbers in pairs(mapping) do
		if monitor ~= name then
			for _, id in pairs(numbers) do blocked[id] = true end
		end
	end
	local candidate = workspace.id + step
	while candidate > 0 and blocked[candidate] do candidate = candidate + step end
	if candidate < 1 then return false end
	local wanted = mapping[name][number + step]
	if wanted then
		return wanted == candidate and (hl.get_workspace(candidate) ~= nil or hl.get_config("gestures.workspace_swipe_create_new") ~= false)
	end
	-- A native-created ID will be adopted into the first unused local slot.
	return hl.get_config("gestures.workspace_swipe_create_new") ~= false
		and not hl.get_workspace(candidate) and free_number(mapping[name]) == number + step
end

local function update_gestures()
	local inverted = hl.get_config("gestures.workspace_swipe_invert")
	if inverted == nil then inverted = true end -- Hyprland 0.57 default.
	for _, direction in ipairs({ "up", "down" }) do
		local step = direction == "up" and -1 or 1
		if inverted then step = -step end
		local mode = native_matches(step) and "native" or "local"
		local state = mode .. step
		if gesture_modes[direction] ~= state then
			-- Directional workspace gestures normalize "up" delta; undo that to
			-- preserve the original vertical gesture's signs/inversion setting.
			local scale = (direction == "up" and -1 or 1) * gestures.workspace_scale
			if gesture_modes[direction] then
				hl.gesture({ fingers = 3, direction = direction, scale = scale, action = "unset" })
			end
			local action = "workspace"
			if mode == "local" then
				action = gestures.workspace_fallback(function(direction) M.step(direction) end)
			end
			hl.gesture({ fingers = 3, direction = direction, scale = scale, action = action })
			gesture_modes[direction] = state
		end
	end
end

function M.sync()
	if syncing or overview_owns_input() then return end
	syncing = true
	local ok, failure = pcall(function()
		defragment(reconcile())
		install_rules()
		update_gestures()
	end)
	syncing = false
	if not ok then error(failure) end
end

local function schedule()
	if syncing or pending then return end
	-- --verify-config has no monitors/event loop. Hyprland 0.57.2 crashes while
	-- cleaning up timers created there; defer initialization until a real session.
	if #hl.get_monitors() == 0 then return end
	-- Leave creation/destruction/gesture callbacks before touching IDs. Coalesce
	-- events; this is a one-shot event-loop task, not a polling daemon.
	pending = hl.timer(function()
		pending = nil
		M.sync()
	end, { timeout = 1, type = "oneshot" })
end

function M.number(number, move)
	if overview_owns_input() then return end
	if number < 1 or number > LIMIT or number % 1 ~= 0 then return end
	M.sync()
	local monitor = hl.get_active_monitor()
	if not monitor then return end
	local name = monitor.name
	mapping[name] = mapping[name] or {}
	if not mapping[name][number] then
		mapping[name][number] = free_id(used_ids())
		M.sync()
	end
	local id = mapping[name][number]
	if move then
		hl.dispatch(hl.dsp.window.move({ workspace = id, follow = true }))
	else
		hl.dispatch(hl.dsp.focus({ workspace = id, on_current_monitor = true }))
	end
	schedule()
end

function M.step(direction, move)
	if overview_owns_input() then return end
	M.sync()
	local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
	if not numbered(workspace) or not workspace.monitor then return end
	local number = local_number(workspace.monitor.name, workspace.id)
	if number then M.number(number + (direction == "up" and -1 or 1), move) end
end

function M.move_monitor(direction)
	if overview_owns_input() then return end
	local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
	if not numbered(workspace) then return end
	hl.dispatch(hl.dsp.workspace.move({ workspace = workspace, monitor = direction }))
	schedule()
end

local function save()
	-- Only on unload/shutdown, never in a keybind. The XDG cache directory exists.
	local file = io.open(cache .. ".tmp", "w")
	if not file then return end
	for monitor, numbers in pairs(mapping) do
		for number, id in pairs(numbers) do file:write(string.format("%s\t%d\t%d\n", monitor, number, id)) end
	end
	file:close()
	os.rename(cache .. ".tmp", cache)
end

for _, event in ipairs({ "config.reloaded", "config.props_refreshed", "hyprland.start", "workspace.created", "workspace.removed",
	"workspace.active", "workspace.move_to_monitor", "monitor.added", "monitor.removed", "monitor.layout_changed", "monitor.focused",
	"keybinds.submap" }) do
	hl.on(event, schedule)
end
hl.on("config.unload", save)
hl.on("hyprland.shutdown", save)

return M
