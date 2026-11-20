-- (monitor connector, local number) -> actual numbered workspace ID.
-- IDs are compacted by monitor/local order; no fixed per-monitor ID ranges.
local M = {}
local gestures = require("hyprland.gestures")
local mapping, rule_pool, gesture_modes = {}, {}, {}
local syncing, suspended, pending = false, false, nil
local overview_edit = false -- Scoped only to explicit, plugin-preflighted actions.
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
	if overview_edit then return false end
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

local function occupied_slots()
	local occupied = {}
	for _, window in ipairs(hl.get_windows()) do
		local workspace = window.workspace
		if window.mapped and numbered(workspace) and workspace.monitor then
			local name = workspace.monitor.name
			local number = local_number(name, workspace.id)
			if number then
				occupied[name] = occupied[name] or {}
				occupied[name][number] = true
			end
		end
	end
	return occupied
end

-- First stop retaining empty interior workspaces; Hyprland removes them once
-- inactive and no longer animating. Compact their dictionary slots only after
-- native removal, so no live workspace is destroyed or renumbered out of its way.
local function prune_empty_interior()
	for name, occupied in pairs(occupied_slots()) do
		local first, last = LIMIT, 0
		for number in pairs(occupied) do
			first, last = math.min(first, number), math.max(last, number)
		end
		local slots, compacted, removed = {}, {}, 0
		for number in pairs(mapping[name]) do slots[#slots + 1] = number end
		table.sort(slots)
		for _, number in ipairs(slots) do
			local id = mapping[name][number]
			if number > first and number < last and not occupied[number] and not hl.get_workspace(id) then
				removed = removed + 1
			else
				compacted[number - removed] = id
			end
		end
		mapping[name] = compacted
	end
end

-- Keep empty destinations only outside the occupied run, not between occupied
-- workspaces. Never expand from an empty workspace (no infinite tail).
local function reserve_empty_neighbors()
	local neighbors = {}
	local used = used_ids()
	for name, numbers in pairs(occupied_slots()) do
		neighbors[name] = {}
		local first, last = LIMIT, 0
		for number in pairs(numbers) do
			first, last = math.min(first, number), math.max(last, number)
		end
		for _, adjacent in ipairs({ first - 1, last + 1 }) do
			if adjacent >= 1 and adjacent <= LIMIT then
				neighbors[name][adjacent] = true
				if not mapping[name][adjacent] then
					local id = free_id(used)
					mapping[name][adjacent], used[id] = id, true
				end
			end
		end
	end
	return neighbors
end

local function install_rules(neighbors)
	local desired = {}
	for name, numbers in pairs(mapping) do
		for number, id in pairs(numbers) do
			local persistent = neighbors[name] and neighbors[name][number] == true or false
			local key = id .. "\t" .. name .. "\t" .. tostring(persistent)
			desired[key] = { id = id, monitor = name, persistent = persistent }
		end
	end
	for key, rule in pairs(rule_pool) do
		if not desired[key] and rule.handle:is_enabled() then rule.handle:set_enabled(false) end
	end
	for key, spec in pairs(desired) do
		local rule = rule_pool[key]
		if not rule then
			rule_pool[key] = { handle = hl.workspace_rule({
				workspace = tostring(spec.id), monitor = spec.monitor, persistent = spec.persistent,
			}) }
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
	local layouts = package.loaded["hyprland.layout-switcher"]
	if layouts then layouts.suspend() end
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
		local monitors = reconcile()
		prune_empty_interior()
		local neighbors = reserve_empty_neighbors()
		defragment(monitors)
		install_rules(neighbors)
		local layouts = package.loaded["hyprland.layout-switcher"]
		if layouts then layouts.refresh() end
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

-- The plugin must refuse this transaction while it owns a positional drag.
-- Do not relax the ordinary navigation/event guards while overview is open.
local function with_overview_edit(action, ...)
	if hl.get_current_submap() ~= "scrolloverview" then return end
	local api = hl.plugin.scrolloverview
	local prepare = api.window("prepare-workspace")
	if prepare then hl.dispatch(prepare) end -- Custom events are not bind invocations.
	overview_edit = true
	local ok, result = pcall(action, ...)
	overview_edit = false
	local refresh = api.window("refresh")
	if refresh then hl.dispatch(refresh) end
	if not ok then error(result) end
	return result
end

function M.overview_move(direction)
	if direction ~= "left" and direction ~= "right" and direction ~= "up" and direction ~= "down" then return end
	return with_overview_edit(function()
		M.sync()
		local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
		if not numbered(workspace) or not workspace.monitor then return end
		if direction == "left" or direction == "right" then
			M.move_monitor(direction == "left" and "l" or "r")
			M.sync()
			hl.dispatch(hl.dsp.focus({ workspace = workspace.id }))
			return workspace.monitor and workspace.monitor.name
		end
		local name = workspace.monitor.name
		local number = local_number(name, workspace.id)
		if not number then return end
		local slots = {}
		for slot in pairs(mapping[name]) do slots[#slots + 1] = slot end
		table.sort(slots)
		for i, slot in ipairs(slots) do
			if slot == number then
				local other = slots[i + (direction == "up" and -1 or 1)]
				if not other then return end
				mapping[name][number], mapping[name][other] = mapping[name][other], mapping[name][number]
				M.sync()
				return name
			end
		end
	end)
end

function M.overview_number(number, move)
	return with_overview_edit(M.number, number, move)
end

-- Native overview gap-drop event: its positional drag is already finished.
-- Insert before the supplied right-hand card; retain every existing workspace
-- identity, including empty slots and per-workspace layout choices.
function M.overview_insert(window, before)
	return with_overview_edit(function()
		if not window or not window.mapped or not numbered(before) or not before.monitor
			or not numbered(window.workspace) or window.workspace.monitor ~= before.monitor then return end
		M.sync()
		local name = before.monitor.name
		local position = local_number(name, before.id)
		if not position then return end
		local previous, shifted = {}, {}
		for number, id in pairs(mapping[name]) do
			previous[number] = id
			assert(number < LIMIT or number < position, "no room to insert another workspace")
			shifted[number >= position and number + 1 or number] = id
		end
		local id = free_id(used_ids())
		shifted[position] = id
		mapping[name] = shifted
		-- Do not renumber before the move succeeds, so rollback can restore the
		-- exact dictionary without reversing any compositor identity changes.
		local ok, failure = pcall(function()
			install_rules(reserve_empty_neighbors())
			local result = hl.dispatch(hl.dsp.window.move({ window = window, workspace = id, follow = false }))
			assert(not result or result.success ~= false, "could not move the dropped window")
			assert(window.workspace and window.workspace.id == id, "dropped window did not reach the new workspace")
		end)
		if not ok then
			mapping[name] = previous
			install_rules(reserve_empty_neighbors())
			error(failure)
		end
		M.sync()
		return window.workspace
	end)
end

-- Called only by the native plugin's file/window-drag edge event. It switches
-- workspaces without cursor warping and preserves the native drag owner.
function M.drag_edge_step(direction, monitor_name)
	if overview_owns_input() or (direction ~= "up" and direction ~= "down") then return end
	local api = hl.plugin.edge_navigation
	if not api or type(api.focus_workspace) ~= "function" then return end
	M.sync()
	local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
	if not numbered(workspace) or not workspace.monitor or workspace.monitor.name ~= monitor_name then return end
	local number = local_number(monitor_name, workspace.id)
	if not number then return end
	local next_number = number + (direction == "up" and -1 or 1)
	if next_number < 1 then return end
	if not mapping[monitor_name][next_number] then
		mapping[monitor_name][next_number] = free_id(used_ids())
		M.sync()
	end
	api.focus_workspace(mapping[monitor_name][next_number], monitor_name)
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
	"keybinds.submap", "window.open", "window.close", "window.move_to_workspace" }) do
	hl.on(event, schedule)
end
hl.on("config.unload", save)
hl.on("hyprland.shutdown", save)

return M
