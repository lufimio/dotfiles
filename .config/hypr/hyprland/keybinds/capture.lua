local capture = require("hyprland.capture")
local shell = require("hyprland.shell")

-- Screenshots use the selected shell; privacy is compositor-owned.
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd(shell.command("screenshot_region")), { description = "Screenshot Region" })
hl.bind("SUPER + CTRL + S", hl.dsp.exec_cmd(shell.command("screenshot_window")), { description = "Screenshot Window" })
hl.bind("SUPER + CTRL + SHIFT + S", hl.dsp.exec_cmd(shell.command("screenshot_output")), { description = "Screenshot Focused Output" })

hl.bind("SUPER + SHIFT + R", capture.target, { description = "Share Focused Window Dynamically", submap_universal = true })
hl.bind("SUPER + CTRL + R", capture.workspace, { description = "Share Focused Workspace Dynamically", submap_universal = true })
hl.bind("SUPER + CTRL + SHIFT + R", capture.monitor, { description = "Share Focused Monitor Dynamically", submap_universal = true })
hl.bind("SUPER + CTRL + BackSpace", capture.clear, { description = "Clear Dynamic Share", submap_universal = true })
hl.bind("SUPER + CTRL + P", capture.privacy, { description = "Toggle Window Capture Privacy" })
