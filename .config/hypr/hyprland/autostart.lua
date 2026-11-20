-- https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
	require("hyprland.plugins").start()
	hl.exec_cmd("xremap --watch=config,device /home/lufimio/.config/xremap/config.yml")
	hl.exec_cmd("dcal daemon")
	hl.exec_cmd("discord --start-minimized")

	hl.exec_cmd("psst-keyring-prompter")
	hl.exec_cmd("psst-polkit-agent")
	-- Import the real session environment, then start only the selected shell.
	-- Never stop/restart a potential lock provider on config reload.
	require("hyprland.shell").start()
	-- Do not start niri-sticky-windows, niri-screen-time, hypridle or hyprlock.
end)
