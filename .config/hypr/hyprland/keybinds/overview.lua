-- Overview-only keymap. Each action is a plugin factory or a Lua
-- function (the same action types hl.bind accepts).
-- Mirrors niri/keybinds.kdl; explicit overview Ctrl+Shift workspace movement
-- intentionally differs from its normal-mode column-to-workspace bindings.
return function(api)
	local binds = {}
	local nav = require("hyprland.navigation")
	local function native(action)
		return function()
			api.window("prepare-workspace")
			action()
			api.window("refresh")
		end
	end
	local function bind(key, action, description, repeating)
		binds[#binds + 1] = { key, action, { description = description, repeating = repeating or false } }
	end
	for direction, keys in pairs({
		left = { "Left", "H" }, right = { "Right", "L" },
		up = { "Up", "K" }, down = { "Down", "J" },
	}) do
		for _, key in ipairs(keys) do
			for _, prefix in ipairs({ "", "SUPER + " }) do
				bind(prefix .. key, api.navigate(direction), "Overview Focus " .. direction, true)
				bind(prefix .. "SHIFT + " .. key, api.window("move-" .. direction), "Overview Move Window/Column " .. direction, true)
				bind(prefix .. "CTRL + SHIFT + " .. key, function()
					local monitor = require("hyprland.workspaces").overview_move(direction)
					if monitor and (direction == "left" or direction == "right") then
						api.overview("open " .. monitor)
					end
				end, "Overview Move Workspace " .. direction, true)
			end
			if direction == "left" or direction == "right" then
				bind("SUPER + CTRL + " .. key, api.navigate(direction), "Overview Focus " .. direction, true)
			end
		end
	end
	for _, prefix in ipairs({ "", "SUPER + " }) do
		bind(prefix .. "Home", api.navigate("first"), "Overview First Column")
		bind(prefix .. "End", api.navigate("last"), "Overview Last Column")
		bind(prefix .. "Q", api.window("close-selected"), "Overview Close Selected Window")
	end
	for _, key in ipairs({ "Return", "Escape", "SUPER + Tab", "SUPER + O" }) do
		bind(key, api.overview("close"), "Close Overview")
	end
	bind("SUPER + backslash", api.window("focus-toggle"), "Toggle Focus Between Floating and Tiled Windows")
	for number = 1, 9 do
		bind("SUPER + " .. number, function()
			require("hyprland.workspaces").overview_number(number)
		end, "Overview Workspace " .. number)
		bind("SUPER + SHIFT + " .. number, function()
			require("hyprland.workspaces").overview_number(number, true)
		end, "Overview Move Window to Workspace " .. number)
	end
	bind("SUPER + minus", native(function() nav.resize_width(-0.1) end), "Shrink Column/Floating Width", true)
	bind("SUPER + equal", native(function() nav.resize_width(0.1) end), "Grow Column/Floating Width", true)
	bind("SUPER + SHIFT + minus", native(function() nav.resize_height(-0.1) end), "Shrink Window Height", true)
	bind("SUPER + SHIFT + equal", native(function() nav.resize_height(0.1) end), "Grow Window Height", true)
	bind("SUPER + Z", native(nav.center), "Center Column/Floating Window")
	bind("SUPER + SHIFT + Z", native(nav.center_visible), "Center Visible Columns")
	bind("SUPER + CTRL + SHIFT + 0", native(nav.reset_height), "Reset Window Height")
	bind("SUPER + D", native(function() hl.dispatch(hl.dsp.layout("colresize +conf")) end), "Cycle Column Width")
	bind("SUPER + 0", native(function() hl.dispatch(hl.dsp.layout("colresize 1.0")) end), "Full-width Column")
	bind("SUPER + CTRL + space", native(function() hl.dispatch(hl.dsp.window.float()) end), "Toggle Floating")
	bind("SUPER + CTRL + Home", native(function() nav.column_edge("l", true) end), "Move Column to First")
	bind("SUPER + CTRL + End", native(function() nav.column_edge("r", true) end), "Move Column to Last")
	hl.bind("SUPER + Tab", api.overview("toggle"), { description = "Scrolling Workspace Overview" })
	hl.bind("SUPER + O", api.overview("toggle"), { description = "Scrolling Workspace Overview" })
	hl.define_submap("scrolloverview", function()
		for _, binding in ipairs(binds) do
			hl.bind(binding[1], binding[2], binding[3])
		end
		hl.bind("mouse:272", function()
			api.overview("select")
			api.window("select")
			api.overview("close")
		end, { description = "Select Clicked Overview Window", mouse = true })
	end)
end
