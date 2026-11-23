local capture = require("hyprland.capture")
-- local shell = require("hyprland.shell")

-- Screenshots use snipline; privacy is compositor-owned.
hl.bind("Print", hl.dsp.exec_cmd("snipline capture region"), { description = "Screenshot Region" })
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("snipline capture region"), { description = "Screenshot Region" })
hl.bind("SUPER + CTRL + S", hl.dsp.exec_cmd("snipline capture window"), { description = "Screenshot Window" })
hl.bind("SUPER + CTRL + SHIFT + S", hl.dsp.exec_cmd("snipline capture monitor"), { description = "Screenshot Focused Output" })

hl.bind("SUPER + SHIFT + R", capture.target, { description = "Share Focused Window Dynamically", submap_universal = true })
hl.bind("SUPER + CTRL + R", capture.workspace, { description = "Share Focused Workspace Dynamically", submap_universal = true })
hl.bind("SUPER + CTRL + SHIFT + R", capture.monitor, { description = "Share Focused Monitor Dynamically", submap_universal = true })
hl.bind("SUPER + CTRL + BackSpace", capture.clear, { description = "Clear Dynamic Share", submap_universal = true })
hl.bind("SUPER + CTRL + P", capture.privacy, { description = "Toggle Window Capture Privacy" })
