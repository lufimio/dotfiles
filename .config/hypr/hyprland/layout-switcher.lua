-- Add layout names here to extend Super+F4's current-workspace cycle.
local M = { layouts = { "scrolling", "dwindle" } }
local choices, rules = {}, {}

local function selector(workspace)
	-- An exact numeric range stays separate from monitor-binding rules that use
	-- plain numeric selectors; Hyprland merges identical selector strings.
	return string.format("r[%d-%d]", workspace.id, workspace.id)
end

-- Retain workspace objects rather than numeric IDs: monitor-local numbering can
-- change IDs. Refresh the affected rule after the workspace dictionary compacts.
function M.refresh()
	local changed = {}
	for index = #choices, 1, -1 do
		local choice = choices[index]
		if not choice.workspace.addressable_name then
			if choice.rule then
				choice.rule:set_enabled(false)
			end
			table.remove(choices, index)
		else
			local key = selector(choice.workspace) .. "\t" .. choice.layout
			if key ~= choice.key or not choice.rule:is_enabled() then
				if choice.rule then
					choice.rule:set_enabled(false)
				end
				changed[#changed + 1] = { choice = choice, key = key }
			end
		end
	end
	for _, change in ipairs(changed) do
		local choice = change.choice
		local rule = rules[change.key]
		if not rule then
			rule = hl.workspace_rule({ workspace = selector(choice.workspace), layout = choice.layout })
			rules[change.key] = rule
		else
			rule:set_enabled(true)
		end
		choice.key, choice.rule = change.key, rule
	end
end

function M.suspend()
	for _, choice in ipairs(choices) do
		if choice.rule then
			choice.rule:set_enabled(false)
		end
	end
end

function M.cycle()
	if hl.get_current_submap() == "scrolloverview" then
		return
	end
	require("hyprland.workspaces").sync()
	local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
	if not workspace or #M.layouts == 0 then
		return
	end
	if workspace.special or not workspace.id or workspace.id < 1 then
		hl.notification.create({ text = "Layout cycling is for numbered workspaces", timeout = 1800 })
		return
	end
	local current = 0
	for index, name in ipairs(M.layouts) do
		if name == workspace.tiled_layout then
			current = index
			break
		end
	end
	local next_layout = M.layouts[current % #M.layouts + 1]
	local choice
	for _, entry in ipairs(choices) do
		if entry.workspace == workspace then
			choice = entry
			break
		end
	end
	if not choice then
		choice = { workspace = workspace }
		choices[#choices + 1] = choice
	end
	choice.layout = next_layout
	M.refresh()
	hl.notification.create({ text = "Layout: " .. next_layout, timeout = 1800 })
end

hl.on("workspace.removed", M.refresh)
return M
