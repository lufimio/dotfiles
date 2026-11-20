# Hyprland configuration

`hyprland.lua` is the entry point. Select `"dms"` or `"noctalia"` there before
a fresh login; shell processes are never switched by a config reload.

- **Bindings:** [`hyprland/keybinds/`](hyprland/keybinds/README.md), separated by purpose.
- **Normal navigation:** `hyprland/navigation.lua`; monitor-local numbering in `hyprland/workspaces.lua`.
- **Empty overview destinations:** the workspace manager keeps numbered empty
  destinations at the outer edges of each monitor's occupied workspaces.
  Empty interior workspaces disappear after you leave them; later slots compact.
  Empty slots do not generate more empty neighbors.
- **Insert a workspace:** in overview, drag a window into the gap between two
  numbered workspace cards and release on the insertion line. Later workspaces
  shift along, keeping their windows and layouts.
- **Layouts:** `Super+F4` cycles the current numbered workspace between scrolling
  and dwindle. Edit the `layouts` list in `hyprland/layout-switcher.lua` to add more.
- **Plugins at login:** `hyprland/plugins.lua` lists reviewed libraries and hashes.
  `scripts/start_plugins.py` loads only missing plugins; it never replaces an
  already loaded library. After an upgrade, review/update the path and hash.
- **Plugin settings:** `hyprland/scrolloverview.lua`, `hyprland/edge-navigation.lua`,
  and `hyprland/dynamic-share-settings.lua`. Plugin directories contain buildable
  source and build tools, not runtime configuration or test suites.

## Layout-aware shortcuts

| Key | Scrolling | Dwindle |
| --- | --- | --- |
| Super+arrows/HJKL | Columns/stack, then workspace vertically | Native directional focus |
| Super+Shift+movement | Column/stack movement; floating nudge | Native directional movement |
| Super+D | Cycle column width | Toggle split orientation |
| Super+0 | Full-width column | Equal 50/50 split |
| Super+minus/equal | Column/floating width | Native window width |
| Super+Shift+minus/equal | Window height | Window height |

Column-only actions stay scrolling-only. `Super+Shift+D` uses native,
non-layout-aware maximization with zero gaps, borders or rounding to fill
everything except the bar's reserved area. Normal tiled spacing returns when
maximization ends (`hyprland/maximize.lua`).
Per-workspace layout choices and runtime binding toggles reset on config reload.

## OBS / LiveSplit bindings

No toggle shortcut is assigned. Change the group without consuming its keys:

```sh
hyprctl repl 'return require("hyprland.keybinds.recording").toggle()'
hyprctl repl 'return require("hyprland.keybinds.recording").set_enabled(false)'
hyprctl repl 'return require("hyprland.keybinds.recording").set_enabled(true)'
```

## Permissions

`hyprland/permissions.lua` allows only reviewed capture tools, the required plugin
paths and known keyboard devices. Other sensitive operations request a native
`hyprland-dialog` prompt. New keyboard devices prompt too.

**Relog after changing permissions.** Hyprland 0.57.2 reads these rules only at
startup. The configuration deliberately does not enable enforcement midway
through an existing session before the startup allowlist is installed.
This is not a general application sandbox, does not gate ordinary app launches,
and does not protect IPC sockets. Apps needing isolation must also be sandboxed.

## Apply ordinary edits

```sh
Hyprland --verify-config -c "$PWD/hyprland.lua"
hyprctl reload config-only
hyprctl configerrors
```

Standalone `hypridle.conf`/`hyprlock.conf` remain for manual use only. Neither is
started automatically; the selected shell continues to own locking and idling.
