local nav = require("hyprland.navigation")

hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Close Window" })
hl.bind("SUPER + SHIFT + D", hl.dsp.window.fullscreen({ mode = "maximized", layout_aware = false }), { description = "Maximize Window to Edges" })
hl.bind("SUPER + F11", hl.dsp.window.fullscreen({ mode = "fullscreen" }), { description = "Fullscreen Window" })
hl.bind("SUPER + CTRL + space", hl.dsp.window.float(), { description = "Toggle Floating" })
hl.bind("SUPER + P", nav.pin_floating, { description = "Pin Floating Window" })
hl.bind("SUPER + backslash", nav.toggle_floating_focus, { description = "Toggle Focus Between Floating and Tiled Windows" })
hl.bind("SUPER + SHIFT + F12", nav.toggle_inhibition, { description = "Toggle Shortcut Inhibitors", dont_inhibit = true })
