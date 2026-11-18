-- Hyprland 0.57.x (Lua only). See PORTING.md for mappings and limitations.
local shell = "dms" -- "dms" or "noctalia"; switch before the next Hyprland login.
require("hyprland.shell").select(shell)
-- Manual configuration is always loaded first.
require("hyprland.env")
require("hyprland.monitors")
require("hyprland.general")
require("hyprland.layout")
require("hyprland.input")
require("hyprland.cursor")
require("hyprland.animation")
require("hyprland.rules")
require("hyprland.keybinds")
require("hyprland.scrolloverview") -- Optional yayuuu overview; old hyprexpo.lua is inactive.
require("hyprland.hotcorners")
require("hyprland.autostart")
require("hyprland.permissions")

-- Only the selected shell's overrides load, always after manual configuration.
if shell == "dms" then
	-- Intentionally empty: stock DMS binds conflict with niri's.
	require("dms.colors")
	require("dms.outputs")
	require("dms.layout")
	require("dms.cursor")
	require("dms.input")
	require("dms.binds")
	require("dms.binds-user")
	require("dms.windowrules")
else
	-- Keep the literal require for Noctalia 5's template hook: it must NOT
	-- append an unconditional theme include after the DMS branch. Split loading
	-- from application so its undo hook cannot delete this line. If the generated
	-- file is absent/disabled, the separate seed remains available.
	local ok, theme = pcall(function()
		return require("noctalia")
	end)
	if not ok or type(theme) ~= "table" or type(theme.apply_theme) ~= "function" then
		theme = require("noctalia.colors")
	end
	theme.apply_theme()
	require("noctalia.windowrules")
end

require("hyprland.struts") -- OPTIONAL: comment out this line to disable niri-like edge padding.

-- Derived urgent styling reads the selected shell's final palette.
require("hyprland.urgency").theme()
