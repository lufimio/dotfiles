-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
-- https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
-- https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
--
hl.config({
	dwindle = {
		preserve_split = true, -- You probably want this
	},
})

hl.config({
	master = {
		new_status = "master",
	},
})

hl.config({
	scrolling = {
		fullscreen_on_one_column = true,
		column_width = 1.0,
	},
})
