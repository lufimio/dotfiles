-- OPTIONAL niri-strut approximation.
-- Disable by commenting out require("hyprland.struts") in hyprland.lua.
-- Extra logical pixels ON TOP OF the selected shell's current outer gaps.
local struts = { left = 18, right = 18, top = 3, bottom = 3 }
local base = hl.get_config("general.gaps_out") or 6
local function gap(side)
	return type(base) == "number" and base or (base[side] or 0)
end

hl.config({
	general = {
		gaps_out = {
			top = gap("top") + struts.top,
			right = gap("right") + struts.right,
			bottom = gap("bottom") + struts.bottom,
			left = gap("left") + struts.left,
		},
	},
})
-- This changes tiled edge spacing, not the monitor workarea: floating windows,
-- fullscreen behavior, and adjacent-column peeking are not niri-identical.
