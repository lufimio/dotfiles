-- Native maximization uses the workspace workarea, which normally includes
-- gaps_out (including our struts). Remove those only while fullscreen/maximized;
-- monitor layer-shell reservations, such as the bar, remain untouched.
for _, selector in ipairs({ "f[1]", "f[2]" }) do
	hl.workspace_rule({
		workspace = selector,
		gaps_in = 0,
		gaps_out = 0,
		float_gaps = 0,
		no_border = true,
		no_rounding = true,
	})
end
