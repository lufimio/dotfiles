-- https://wiki.hypr.land/0.57.0/configuring/layouts/scrolling-layout/

hl.config({
	scrolling = {
		-- A lone column must keep its chosen width, not automatically expand.
		fullscreen_on_one_column = false,
		column_width = 1.0,
		explicit_column_widths = "0.33333, 0.5, 0.66667, 1.0",
		focus_fit_method = 1, -- niri: center-focused-column "never".
		follow_focus = 1,
		wrap_focus = false,
		wrap_swapcol = false,
		direction = "right",
	},
})
