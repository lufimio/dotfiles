local nav = require("hyprland.navigation")

-- Wheel navigation.
hl.bind("SUPER + mouse_down", function() nav.workspace("down") end, { description = "Focus Workspace Down" })
hl.bind("SUPER + mouse_up", function() nav.workspace("up") end, { description = "Focus Workspace Up" })
hl.bind("SUPER + CTRL + mouse_down", function() nav.workspace("down", true) end, { description = "Move Active Window to Workspace Down" })
hl.bind("SUPER + CTRL + mouse_up", function() nav.workspace("up", true) end, { description = "Move Active Window to Workspace Up" })
hl.bind("SUPER + SHIFT + mouse_down", function() nav.focus_horizontal("right") end, { description = "Focus Right" })
hl.bind("SUPER + SHIFT + mouse_up", function() nav.focus_horizontal("left") end, { description = "Focus Left" })
hl.bind("SUPER + CTRL + SHIFT + mouse_down", function() nav.move_horizontal("right") end, { description = "Move Right" })
hl.bind("SUPER + CTRL + SHIFT + mouse_up", function() nav.move_horizontal("left") end, { description = "Move Left" })
hl.bind("SUPER + mouse_left", function() nav.focus_horizontal("left") end, { description = "Focus Left" })
hl.bind("SUPER + mouse_right", function() nav.focus_horizontal("right") end, { description = "Focus Right" })
hl.bind("SUPER + CTRL + mouse_left", function() nav.move_horizontal("left") end, { description = "Move Left" })
hl.bind("SUPER + CTRL + mouse_right", function() nav.move_horizontal("right") end, { description = "Move Right" })

hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { description = "Drag Window", mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { description = "Resize Window", mouse = true })
