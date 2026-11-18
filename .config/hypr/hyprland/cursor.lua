-- Manual fallback; dms/cursor.lua takes priority only in DMS mode.
hl.env("XCURSOR_THEME", "capitaine-cursors")
hl.env("HYPRCURSOR_THEME", "capitaine-cursors")
hl.config({ cursor = { inactive_timeout = 3 } })
