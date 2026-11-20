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
require("hyprland.keybinds.init")
require("hyprland.scrolloverview")
require("hyprland.dynamic-share-settings")
require("hyprland.edge-navigation")
require("hyprland.permissions")
require("hyprland.autostart")

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
	-- append an unconditional theme include after the DMS branch.
	local ok, theme = pcall(function()
		return require("noctalia")
	end)
	if ok and type(theme) == "table" and type(theme.apply_theme) == "function" then
		theme.apply_theme()
	end
	require("noctalia.windowrules")
end

require("hyprland.struts") -- OPTIONAL: comment out this line to disable niri-like edge padding.
require("hyprland.maximize")

-- Derived urgent styling reads the selected shell's final palette.
require("hyprland.urgency").theme()
