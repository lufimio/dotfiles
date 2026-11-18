-- Approximate niri v26.04 defaults; DMS controls its own overview/UI animation.
-- https://github.com/niri-wm/niri/blob/v26.04/docs/wiki/Configuration:-Animations.md
-- https://wiki.hypr.land/0.57.0/configuring/core/animations/
hl.config({ animations = { enabled = true } })

-- niri: mass=1, damping-ratio=1. damping = 2 * sqrt(stiffness * mass).
hl.curve("niriMovement", { type = "spring", mass = 1, stiffness = 800, dampening = 56.568542 })
hl.curve("niriWorkspace", { type = "spring", mass = 1, stiffness = 1000, dampening = 63.245553 })
hl.curve("niriOpen", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("niriClose", { type = "bezier", points = { { 0.5, 1 }, { 0.89, 1 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 1, spring = "niriMovement" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 1, spring = "niriMovement" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 1.5, bezier = "niriOpen", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.5, bezier = "niriClose", style = "popin 90%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.5, bezier = "niriOpen" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.5, bezier = "niriClose" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1, spring = "niriWorkspace", style = "slidevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 1, spring = "niriMovement", style = "fade" })
