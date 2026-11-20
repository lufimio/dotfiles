-- Pure Lua helpers: no subprocesses or blocking I/O in compositor callbacks.
-- Scrolling metadata verified against Hyprland v0.57.2 LuaWindow.cpp.
local M = {}
local workspaces = require("hyprland.workspaces")
local floating_move_step = 50 -- Logical pixels per Super+Shift+arrow/H/J/K/L press.
local floating_move_vectors = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }

function M.toggle_floating_focus()
	local active = hl.get_active_window()
	local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
	if not workspace then return end
	local target
	for _, window in ipairs(hl.get_windows()) do
		local same_workspace = window.workspace and window.workspace.addressable_name == workspace.addressable_name
		local pinned_here = window.pinned and window.monitor and workspace.monitor
			and window.monitor.name == workspace.monitor.name and not workspace.special
		if window ~= active and window.mapped and not window.hidden and window.accepts_input
			and (same_workspace or pinned_here) and window.floating ~= (active and active.floating or false) then
			local rank = window.focus_history_id or -1
			local best = target and (target.focus_history_id or -1) or -1
			if not target or (rank >= 0 and (best < 0 or rank < best)) then target = window end
		end
	end
	if target then hl.dispatch(hl.dsp.focus({ window = target })) end
end

local function move_floating(window, direction)
	if not window or not window.floating then return false end
	local delta = floating_move_vectors[direction]
	if not delta then return false end
	hl.dispatch(hl.dsp.window.move({
		window = window,
		x = delta[1] * floating_move_step,
		y = delta[2] * floating_move_step,
		relative = true,
	}))
	return true
end

local function scrolling_window()
	local window = hl.get_active_window()
	if window and not window.floating and window.layout and window.layout.name == "scrolling" then
		return window, window.layout
	end
end

function M.workspace(direction, move)
	workspaces.step(direction, move)
end

function M.focus_horizontal(direction)
	if direction ~= "left" and direction ~= "right" then return end
	if scrolling_window() then
		hl.dispatch(hl.dsp.layout("focus " .. (direction == "left" and "l" or "r")))
	else
		hl.dispatch(hl.dsp.focus({ direction = direction }))
	end
end

function M.move_horizontal(direction)
	if direction ~= "left" and direction ~= "right" then return end
	if move_floating(hl.get_active_window(), direction) then return end
	if scrolling_window() then
		hl.dispatch(hl.dsp.layout("swapcol " .. (direction == "left" and "l" or "r")))
	elseif hl.get_active_window() then
		hl.dispatch(hl.dsp.window.move({ direction = direction }))
	end
end

function M.column_action(message)
	if scrolling_window() then hl.dispatch(hl.dsp.layout(message)) end
end

function M.cycle_width_or_split()
	local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
	if workspace and workspace.tiled_layout == "scrolling" then
		hl.dispatch(hl.dsp.layout("colresize +conf"))
	elseif workspace and workspace.tiled_layout == "dwindle" then
		hl.dispatch(hl.dsp.layout("togglesplit"))
	end
end

function M.reset_width_or_split()
	local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
	if workspace and workspace.tiled_layout == "scrolling" then
		hl.dispatch(hl.dsp.layout("colresize 1.0"))
	elseif workspace and workspace.tiled_layout == "dwindle" then
		hl.dispatch(hl.dsp.layout("splitratio 1 exact"))
	end
end

function M.vertical(direction, move)
	if direction ~= "up" and direction ~= "down" then return end
	-- Nudge floating windows rather than treating them as tiled layout targets.
	if move and move_floating(hl.get_active_window(), direction) then return end
	local window, layout = scrolling_window()
	if not window then
		-- Floating/special/non-scrolling workspaces retain native directional behavior.
		if hl.get_active_window() then
			hl.dispatch(move and hl.dsp.window.move({ direction = direction }) or hl.dsp.focus({ direction = direction }))
		elseif not move then
			M.workspace(direction)
		end
		return
	end
	local row = layout.index_in_column + 1 -- Native index is zero-based.
	local neighbor = layout.column.windows[row + (direction == "up" and -1 or 1)]
	if neighbor then
		if move then
			-- Swap this exact pair inside the current column. A generic
			-- directional move can use compositor fallback/group heuristics.
			hl.dispatch(hl.dsp.window.swap({ window = window, with = neighbor }))
		else
			hl.dispatch(hl.dsp.focus({ window = neighbor }))
		end
	else
		M.workspace(direction, move)
	end
end

-- Native focus/swapcol dispatches repeated to an endpoint; no column reconstruction.
function M.column_edge(direction, move)
	local window = scrolling_window()
	if not window then
		return
	end
	local limit = #hl.get_workspace_windows(window.workspace)
	for _ = 1, limit do
		local current, layout = scrolling_window()
		if not current then
			break
		end
		local index = layout.column.index
		hl.dispatch(hl.dsp.layout((move and "swapcol " or "focus ") .. direction))
		local after, after_layout = scrolling_window()
		if not after or after_layout.column.index == index then
			break
		end
	end
end

local function workarea(monitor)
	-- v0.57.2: mode.width/height are logical; width/height and size are pixels.
	local reserved = monitor.reserved or {}
	local left, right = reserved.left or 0, reserved.right or 0
	local top, bottom = reserved.top or 0, reserved.bottom or 0
	return monitor.x + left, monitor.y + top,
		monitor.mode.width - left - right, monitor.mode.height - top - bottom
end

function M.center()
	local window = hl.get_active_window()
	if not window then return end
	if window.floating then
		-- Native centering uses this window's monitor and excludes reserved bars.
		-- It keeps the window floating, its size, and its workspace unchanged.
		hl.dispatch(hl.dsp.window.center({ window = window }))
	elseif window.layout and window.layout.name == "scrolling" then
		hl.dispatch(hl.dsp.layout("center"))
	end
end

function M.center_visible()
	local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
	if not workspace or workspace.special or workspace.tiled_layout ~= "scrolling" or not workspace.monitor then
		return
	end
	local left, _, width = workarea(workspace.monitor)
	local first, last
	for _, window in ipairs(hl.get_workspace_windows(workspace)) do
		if window.mapped and not window.floating and not window.hidden and window.layout then
			local x, w = window.at.x, window.size.x
			if x < left + width and x + w > left then
				first = math.min(first or x, x)
				last = math.max(last or x + w, x + w)
			end
		end
	end
	if not first then
		return
	end
	local shift = left + width / 2 - (first + last) / 2
	if math.abs(shift) >= 1 then
		-- Native move shifts the tape in pixels and focuses its center column.
		hl.dispatch(hl.dsp.layout(string.format("move %+.0f", shift)))
	end
end

function M.resize_width(change)
	local window = hl.get_active_window()
	if not window then return end
	if window.floating then
		if not window.monitor then return end
		local _, _, width = workarea(window.monitor)
		-- Match column/height increments: fractions of the logical workarea,
		-- not physical pixels or a compounding fraction of the window's width.
		hl.dispatch(hl.dsp.window.resize({ window = window, x = width * change, y = 0, relative = true }))
	elseif window.layout and window.layout.name == "scrolling" then
		hl.dispatch(hl.dsp.layout(string.format("colresize %+.10g", change)))
	elseif window.monitor then
		local _, _, width = workarea(window.monitor)
		hl.dispatch(hl.dsp.window.resize({ window = window, x = width * change, y = 0, relative = true }))
	end
end

function M.resize_height(change)
	local window = hl.get_active_window()
	if not window or not window.monitor then
		return
	end
	local _, _, _, height = workarea(window.monitor)
	hl.dispatch(hl.dsp.window.resize({ x = 0, y = height * change, relative = true }))
end

function M.reset_height()
	local window, layout = scrolling_window()
	if not window then
		return
	end
	local _, _, _, height = workarea(window.monitor)
	local gap = hl.get_config("general.gaps_in")
	gap = type(gap) == "number" and gap or 3
	-- Native absolute resize approximates niri's auto-height with an equal share.
	hl.dispatch(hl.dsp.window.resize({ x = window.size.x, y = height / #layout.column.windows - 2 * gap }))
end

function M.pin_floating()
	local window = hl.get_active_window()
	if window and window.floating then
		hl.dispatch(hl.dsp.window.pin())
	end
end

function M.toggle_inhibition()
	local disabled = hl.get_config("binds.disable_keybind_grabbing")
	hl.config({ binds = { disable_keybind_grabbing = not disabled } })
end

return M
