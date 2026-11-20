-- Load bindings by purpose. Keep literal requires and hl.bind calls so DMS's
-- shortcut viewer can discover them without executing the configuration.
require("hyprland.keybinds.applications")
require("hyprland.keybinds.windows")
require("hyprland.keybinds.layout")
require("hyprland.keybinds.navigation")
require("hyprland.keybinds.workspaces")
require("hyprland.keybinds.mouse")
require("hyprland.keybinds.capture")
require("hyprland.keybinds.shell")
require("hyprland.keybinds.media")
require("hyprland.keybinds.recording")
-- Overview bindings are configured separately by hyprland/scrolloverview.lua.
