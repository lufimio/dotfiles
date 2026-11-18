-- Pure Lua helpers: no subprocesses or blocking I/O in compositor callbacks.
-- Scrolling metadata verified against Hyprland v0.57.2 LuaWindow.cpp.
local M = {}
local workspaces = require("hyprland.workspaces")

local function scrolling_window()
	local window = hl.get_active_window()
	if window and not window.floating and window.layout and window.layout.name == "scrolling" then
		return window, window.layout
	end
end

function M.workspace(direction, move)
	workspaces.step(direction, move)
end

function M.vertical(direction, move)
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
			hl.dispatch(hl.dsp.window.move({ direction = direction }))
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
