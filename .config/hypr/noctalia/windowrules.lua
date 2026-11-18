-- Noctalia 5.4's native settings window; do not load DMS-specific overrides.
hl.window_rule({
	name = "noctalia-settings",
	match = { class = "^dev\\.noctalia\\.Noctalia$" },
	float = true,
	size = { 1080, 920 },
})
