-- https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function ()
  hl.exec_cmd("xremap --watch=config,device /home/lufimio/.config/xremap/config.yml")
  hl.exec_cmd("dcal daemon")
  hl.exec_cmd("psst-keyring-prompter & psst-polkit-agent")
  hl.exec_cmd("dbus-update-activation-environment --systemd DISPLAY XAUTHORITY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
end)

