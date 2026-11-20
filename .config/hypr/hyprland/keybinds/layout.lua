local nav = require("hyprland.navigation")
local layouts = require("hyprland.layout-switcher")

hl.bind("SUPER + F4", layouts.cycle, { description = "Cycle Workspace Layout" })
-- Size and center columns, or the focused floating window.
hl.bind("SUPER + minus", function() nav.resize_width(-0.1) end, { description = "Shrink Column or Floating Window 10%", repeating = true })
hl.bind("SUPER + equal", function() nav.resize_width(0.1) end, { description = "Grow Column or Floating Window 10%", repeating = true })
hl.bind("SUPER + D", nav.cycle_width_or_split, { description = "Cycle Column Width or Toggle Split" })
hl.bind("SUPER + 0", nav.reset_width_or_split, { description = "Full-width Column or Equal Split" })
hl.bind("SUPER + CTRL + SHIFT + 0", nav.reset_height, { description = "Equal-share Window Height (approximation)" })
hl.bind("SUPER + SHIFT + minus", function() nav.resize_height(-0.1) end, { description = "Shrink Window Height 10%", repeating = true })
hl.bind("SUPER + SHIFT + equal", function() nav.resize_height(0.1) end, { description = "Grow Window Height 10%", repeating = true })
hl.bind("SUPER + Z", nav.center, { description = "Center Column or Floating Window" })
hl.bind("SUPER + SHIFT + Z", nav.center_visible, { description = "Center Visible Columns (may change focus)" })

-- Move windows into/out of scrolling columns.
hl.bind("SUPER + bracketleft", function() nav.column_action("consume_or_expel prev") end, { description = "Consume or Expel Left" })
hl.bind("SUPER + bracketright", function() nav.column_action("consume_or_expel next") end, { description = "Consume or Expel Right" })
hl.bind("SUPER + SHIFT + bracketleft", function() nav.column_action("consume") end, { description = "Consume from Next Column (native approximation)" })
hl.bind("SUPER + SHIFT + bracketright", function() nav.column_action("promote") end, { description = "Expel Active Window into New Column" })
