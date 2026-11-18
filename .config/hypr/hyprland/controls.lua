-- One direct action per keypress: never wait for shell IPC or apply an action
-- twice after a timed-out IPC reply. Shells may observe these changes for OSD.
return {
	volume_up = "wpctl set-volume --limit 1.0 @DEFAULT_AUDIO_SINK@ 5%+",
	volume_down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",
	mute = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
	mic_mute = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle",
	-- Restrict to display backlights; never pick a keyboard LED as the default.
	brightness_up = "brightnessctl --class=backlight set +5%",
	brightness_down = "brightnessctl --class=backlight --min-value=1 set 5%-",
	-- playerctld is preferred if running; %any works without that daemon.
	next = "playerctl --player=playerctld,%any next",
	previous = "playerctl --player=playerctld,%any previous",
	play_pause = "playerctl --player=playerctld,%any play-pause",
	player_volume_up = "playerctl --player=playerctld,%any volume 0.05+",
	player_volume_down = "playerctl --player=playerctld,%any volume 0.05-",
}
