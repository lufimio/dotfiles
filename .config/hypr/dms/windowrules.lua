-- DMS Window Rules — managed by Dux Modular Shell
-- Do not edit manually; changes may be overwritten

-- DMS-RULE: id=dms_rule_0, name=
hl.window_rule({ match = { class = "^wev$" }, float = true, size = { 400, 400 } })

-- DMS-RULE: id=dms_rule_1, name=
hl.window_rule({ match = { class = "^(dev\\.duxlabs\\.shell|com\\.danklinux\\.dms)$" }, float = true })

-- DMS-RULE: id=dms_rule_2, name=
hl.window_rule({ match = { class = "^eu\\.betterbird\\.Betterbird$", title = ".*Reminder.*" }, float = true, size = { 600, 700 } })

-- DMS-RULE: id=dms_rule_3, name=
hl.window_rule({ match = { class = "^love$", title = "^Olympus$" }, float = true })

-- DMS-RULE: id=dms_rule_4, name=
hl.window_rule({ match = { class = "^waterfox$", title = "^Extension: (Bitwarden Password Manager) - Bitwarden — Waterfox$" }, float = true })

-- DMS-RULE: id=dms-floating-windows, name=DMS Floating Windows
hl.window_rule({ match = { class = "^(dev\\.duxlabs\\.shell|com\\.danklinux\\.dms)$" }, float = true })

-- DMS-RULE: id=dms-window-opaque, name=DMS Window Opaque
hl.window_rule({ match = { class = "^(dev\\.duxlabs\\.shell|com\\.danklinux\\.dms)$" }, opaque = true })
