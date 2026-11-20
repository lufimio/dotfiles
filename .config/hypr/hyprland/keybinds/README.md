# Keybindings

`init.lua` loads the normal-mode files below. Edit bindings directly in the file
for their purpose; keep `hl.bind` calls literal so DMS can list them.

| File | Purpose |
| --- | --- |
| `applications.lua` | Terminal, launcher, browser, file manager, desktop tools |
| `windows.lua` | Close, fullscreen, floating, pinning, focus layer, inhibitors |
| `layout.lua` | Layout cycle, sizes, centering, consuming/expelling columns |
| `navigation.lua` | Arrows/HJKL, stack movement, first/last column |
| `workspaces.lua` | Local numbers, workspace movement, monitor transfers, scratchpad |
| `mouse.lua` | Wheel navigation, window dragging/resizing |
| `capture.lua` | Screenshots, Dynamic Share, capture privacy |
| `shell.lua` | Power, notifications, lock, DND, shortcut viewer |
| `media.lua` | Shell-independent audio/player/brightness controls |
| `recording.lua` | Runtime-toggleable OBS and LiveSplit group |
| `overview.lua` | Overview toggle and submap; loaded only by ScrollOverview setup |

Actions/helpers live in the parent `hyprland/` directory. Plugin settings also
stay there; plugin directories contain source, build tools and docs.
DMS shortcut-editor overrides still load last from `dms/binds-user.lua`.

Reload after editing with `hyprctl reload config-only`.
See the root README for the layout-specific mappings and OBS toggle commands.
