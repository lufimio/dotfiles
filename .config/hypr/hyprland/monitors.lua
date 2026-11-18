-- Manual fallbacks; DMS output rules are loaded afterwards.
-- https://wiki.hypr.land/0.57.0/configuring/core/monitors/

hl.monitor({
	output = "eDP-1",
	mode = "1366x768@60.059",
	position = "0x312",
	scale = 1,
	vrr = 3, -- on-demand VRR (fullscreen video/game).
})

hl.monitor({
	output = "desc:Ancor Communications Inc ASUS VS228 E7LMTF084993",
	mode = "1920x1080@60.000",
	position = "1366x0",
	scale = 1,
})

hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = 1,
})
