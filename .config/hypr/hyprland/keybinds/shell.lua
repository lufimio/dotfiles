local shell = require("hyprland.shell")

hl.bind("SUPER + CTRL + Delete", hl.dsp.exec_cmd(shell.command("power_menu")), { description = "Power Menu" })
hl.bind("SUPER + N", hl.dsp.exec_cmd(shell.command("notifications")), { description = "Notifications" })
hl.bind("SUPER + Escape", hl.dsp.exec_cmd(shell.command("dismiss")), { description = "Dismiss Popup" })
if shell.command("cheatsheet") then
	hl.bind("SUPER + SHIFT + slash", hl.dsp.exec_cmd(shell.command("cheatsheet")), { description = "Keyboard Shortcuts" })
end
hl.bind("SUPER + Delete", hl.dsp.exec_cmd(shell.command("lock")), { description = "Lock Device" })
hl.bind("SUPER + CTRL + D", hl.dsp.exec_cmd(shell.command("dnd")), { description = "Toggle Do Not Disturb" })
