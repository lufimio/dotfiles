-- Workspace-backed minimization: the installed Hyprland has no native minimize
-- dispatcher. Keep real workspace references so renumbering does not lose home.
local M = {}
local destination = "name:minimized"
local stack, busy, last_regular = {}, false, nil
local signature = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
local state_path = signature and ((os.getenv("XDG_RUNTIME_DIR") or "/tmp/opencode")
	.. "/hypr-minimized-" .. signature:gsub("[^%w_.-]", "_") .. ".tsv")

local function stashed(window)
	return window.workspace and not window.workspace.special
		and window.workspace.addressable_name == "minimized"
end

local function selector(workspace)
	-- Expired workspace userdata raises on access, rather than returning nil.
	local ok, value = pcall(function()
		if workspace.special then return workspace.addressable_name end
		if workspace.id and workspace.id > 0 then return tostring(workspace.id) end
		return "name:" .. workspace.addressable_name
	end)
	return ok and value or nil
end

local function dispatch(action)
	local result = hl.dispatch(action)
	assert(not result or result.success ~= false, result and result.error or "dispatcher failed")
end

local function snapshot(window)
	return {
		id = window.stable_id, home = window.workspace, pinned = window.pinned,
		fullscreen = window.fullscreen or 0, client = window.fullscreen_client or 0,
	}
end

local function live_windows()
	local live = {}
	for _, window in ipairs(hl.get_windows()) do
		if window.mapped then live[window.stable_id] = window end
	end
	return live
end

local function sync(candidates)
	local live, kept, seen = live_windows(), {}, {}
	for _, entry in ipairs(stack) do
		if live[entry.id] and stashed(live[entry.id]) and not seen[entry.id] then
			kept[#kept + 1], seen[entry.id] = entry, true
		end
	end
	-- Recover windows manually moved into the collection. Native moves can move
	-- tab groups together; candidates preserve every member's original home.
	local missing = {}
	for id, window in pairs(live) do
		if stashed(window) and not seen[id] then missing[#missing + 1] = id end
	end
	table.sort(missing)
	for _, id in ipairs(missing) do
		kept[#kept + 1] = candidates and candidates[id] or { id = id, fullscreen = 0, client = 0 }
	end
	stack = kept
	return live
end

local function remember_regular(workspace)
	if workspace and not workspace.special and workspace.addressable_name ~= "minimized" then
		last_regular = workspace
	end
end

local function return_workspace(entry)
	local home = selector(entry.home)
	if home then return home end
	local current = hl.get_active_workspace()
	if current and current.addressable_name ~= "minimized" then return selector(current) end
	home = selector(last_regular)
	if home then return home end
	-- The original empty workspace may have vanished. Prefer another regular
	-- workspace on this monitor; only create a local slot when none exists.
	local monitor = hl.get_active_monitor()
	for _, workspace in ipairs(hl.get_workspaces()) do
		if not workspace.special and workspace.addressable_name ~= "minimized"
			and workspace.monitor == monitor then return selector(workspace) end
	end
	require("hyprland.workspaces").number(1)
	return assert(selector(hl.get_active_workspace()), "no restore workspace available")
end

local function reset_fullscreen(window, internal, client)
	dispatch(hl.dsp.window.fullscreen_state({
		window = window, internal = internal, client = client, layout_aware = false,
	}))
end

local function protected(action)
	if busy or hl.get_current_submap() ~= "" then return false end
	busy = true
	local ok, result = pcall(action)
	busy = false
	sync()
	if not ok then
		hl.notification.create({ text = "Minimize: " .. tostring(result), timeout = 5000 })
		return false
	end
	return result
end

function M.minimize()
	return protected(function()
		sync()
		local window = hl.get_active_window()
		if not window or not window.mapped or not window.accepts_input or stashed(window) then return false end
		remember_regular(hl.get_active_workspace())
		local candidates = {}
		for id, other in pairs(live_windows()) do
			if not stashed(other) then candidates[id] = snapshot(other) end
		end
		local entry = candidates[window.stable_id]
		local ok, failure = pcall(function()
			if entry.fullscreen ~= 0 or entry.client ~= 0 then reset_fullscreen(window, 0, 0) end
			if entry.pinned then dispatch(hl.dsp.window.pin({ window = window, action = "unset" })) end
			dispatch(hl.dsp.window.move({ window = window, workspace = destination, follow = false }))
			assert(stashed(window), "window did not reach the minimized workspace")
		end)
		if not ok then
			-- Keep metadata if the move succeeded despite a later error.
			if stashed(window) then
				sync(candidates)
			else
				if entry.pinned then dispatch(hl.dsp.window.pin({ window = window, action = "set" })) end
				if entry.fullscreen ~= 0 or entry.client ~= 0 then reset_fullscreen(window, entry.fullscreen, entry.client) end
			end
			error(failure)
		end
		sync(candidates)
		-- The focused member is the newest entry even when a whole group moved.
		for i = #stack, 1, -1 do
			if stack[i].id == entry.id then table.remove(stack, i) end
		end
		stack[#stack + 1] = entry
		return true
	end)
end

function M.restore()
	return protected(function()
		local live = sync()
		local entry = stack[#stack]
		if not entry then return false end
		local window = live[entry.id]
		dispatch(hl.dsp.window.move({ window = window, workspace = return_workspace(entry), follow = true }))
		assert(not stashed(window), "window did not leave the minimized workspace")
		dispatch(hl.dsp.focus({ window = window }))
		if entry.pinned then dispatch(hl.dsp.window.pin({ window = window, action = "set" })) end
		if entry.fullscreen ~= 0 or entry.client ~= 0 then reset_fullscreen(window, entry.fullscreen, entry.client) end
		return true
	end)
end

function M.toggle()
	sync()
	if #stack > 0 then return M.restore() end
	return M.minimize()
end

function M.show()
	return protected(function()
		remember_regular(hl.get_active_workspace())
		dispatch(hl.dsp.focus({ workspace = destination }))
		return true
	end)
end

-- Save only on config unload/shutdown, never from a key callback. Instance-local
-- IDs and ordering survive reloads without leaking into a different login.
local function encode(value)
	return tostring(value):gsub("([^%w_.:-])", function(char) return string.format("%%%02X", char:byte()) end)
end
local function decode(value)
	return value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
end

if state_path and #hl.get_monitors() > 0 then
	local file = io.open(state_path, "r")
	if file then
		for line in file:lines() do
			local id, home, pinned, fullscreen, client = line:match("^([^\t]+)\t([^\t]+)\t([01])\t([0-3])\t([0-3])$")
			if id then
				stack[#stack + 1] = {
					id = decode(id), home = home ~= "-" and hl.get_workspace(decode(home)) or nil,
					pinned = pinned == "1", fullscreen = tonumber(fullscreen), client = tonumber(client),
				}
			end
		end
		file:close()
	end
end

local function save()
	if not state_path or #hl.get_monitors() == 0 then return end
	sync()
	local file = io.open(state_path .. ".tmp", "w")
	if not file then return end
	for _, entry in ipairs(stack) do
		file:write(table.concat({
			encode(entry.id), encode(selector(entry.home) or "-"), entry.pinned and "1" or "0",
			tostring(entry.fullscreen), tostring(entry.client),
		}, "\t"), "\n")
	end
	file:close()
	os.rename(state_path .. ".tmp", state_path)
end

hl.workspace_rule({ workspace = destination, layout = "dwindle" })
hl.on("workspace.active", remember_regular)
for _, event in ipairs({ "window.close", "window.move_to_workspace" }) do
	hl.on(event, function() if not busy then sync() end end)
end
hl.on("config.unload", save)
hl.on("hyprland.shutdown", save)
remember_regular(hl.get_active_workspace())
sync()
return M
