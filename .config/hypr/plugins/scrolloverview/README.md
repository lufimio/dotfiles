# ScrollOverview — local v4 patch

Pinned upstream: `3eb62e3e0093d54cbdcf4f58c831b5b53b3b1ff2`.
Target: Hyprland **0.57.2**, commit `11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947`,
Lua **5.5**. `input-v3.patch` plus `workspace-insert.patch`/`.inc` builds as
`3eb62e3e0093-local-input-v4`.

Configuration lives in `hyprland/scrolloverview.lua`; bindings live in
`hyprland/keybinds/overview.lua`. Only the pinned v4 library is configured.
Missing, stock and older plugins leave overview unbound, without enabling a
shell fallback or breaking the rest of the compositor configuration.

## Input

- Left drag moves windows; right drag pans; middle clicks are ignored.
  `right_drag_pan = false` restores upstream button behavior.
- `drag_threshold = 4` logical pixels starts a drag.
- `column_scroll_factor = 1.5` increases two-finger horizontal sensitivity.
- `column_swipe_threshold = 12` lets a short, deliberate two-finger swipe commit
  to an adjacent column. Zero uses native snapping. No wrapping or extra long-swipe step.
- Right drag locks to columns or workspaces on initial movement. Both scales
  default to **0.8**; workspace distance **360**, cancel ratio **0.2**, force
  speed **8**, `forever = false`, grid snapping on, cursor snapping off.
  Column fling smoothing **0.35**, decay **4**, projection limit **2** viewport
  widths match the current native three-finger tuning. Force speed is normalized
  to logical travel per 60-Hz update, not raw mouse event rate.
- Shift+wheel/touchpad scrolls columns horizontally.
- `drag_edge_navigation = true`, zone **48** logical pixels, maximum speed
  **900** logical pixels/second: window and external drags navigate at edges.
- `drag_hover_activate = true`, delay **600 ms**: external DnD hovering a window
  closes overview and focuses that target. It never auto-closes an internal
  rearrangement; edge navigation suspends hover activation. False disables it,
  and a zero delay activates immediately.
- Special workspaces are hidden by default; named normal workspaces are visible.

## Bindings

The overview keymap is based on `../niri/keybinds.kdl`:

- Arrows/HJKL, optionally Super: focus. Shift: move a column horizontally or
  swap a window vertically within its stack, then cross a visible workspace boundary.
  Floating windows nudge by 50 logical pixels.
- Ctrl+Shift+arrows/HJKL: move whole workspaces. Horizontal transfers monitors;
  vertical swaps adjacent numbered monitor-local slots.
- Super+1–9 focuses a local workspace; Super+Shift+1–9 moves the selected window.
  This moves a window/group, not an entire column.
- Home/End, resizing, centering, floating, close and floating/tiled focus actions
  follow the normal translated bindings. Return/Escape/Super+Tab/O close overview.

Named/special workspaces can be displayed/focused but are not assigned numbered
dictionary slots. Global application/screenshot/share bindings are not copied
into the submap. Unsupported niri actions remain explicit approximations.
Workspace edits reject active drags before temporarily bypassing the normal
overview guard; collision-safe ID changes and rollback remain in place.

`hyprland/workspaces.lua` keeps numbered empty slots at the outer edges of the
occupied workspace run, so the overview can scroll into an empty destination.
This uses native persistent workspace rules, not another plugin patch; empty
slots never expand into an endless chain.
Empty interior workspaces are not retained: Hyprland removes them when inactive,
then the workspace manager compacts later slots without changing their contents.
Compaction waits while overview owns input, so it cannot invalidate a live drag.

With `insert_workspaces = true`, dragging a window into the gap between two
numbered workspace cards shows a colored insertion line. Release there to
create a workspace before the following card and move the window into it.
Later monitor-local slots shift up; existing workspace identities and layouts
remain intact. Ordinary card drops keep their existing behavior. Insertion is
same-monitor only and does not apply to named/special cards or external file DnD.
The positional drag finishes before Lua changes any IDs.

## Build and activation

From `.config/hypr`:

```sh
python3 plugins/scrolloverview/build.py           # Build only.
python3 plugins/scrolloverview/build.py --load    # Explicit live switch.
python3 plugins/scrolloverview/build.py --install # Install for a future load.
python3 plugins/scrolloverview/build.py --path    # Latest built library.
python3 plugins/scrolloverview/build.py --restore # Restore prior on-disk install.
```

The builder fetches the pinned source, checks headers/ABI, applies the patch and
saves a unique library under `~/.local/share/hypr/scrolloverview/`. It never
overwrites a mapped library or loads anything during a plain build.

`--load` verifies the active submap, resolves the exact mapped library path,
preserves a rollback binary, switches only this plugin, reloads config and checks
for errors. It refuses a second loaded copy and attempts rollback on failure.
Use `--old-path /absolute/library.so` only if automatic path resolution is ambiguous.
**Save work and close overview first:** a native plugin crash cannot be rolled
back after the compositor exits. Live loading does not install persistently.

`--install` atomically replaces the hyprpm library, retaining a content-addressed
backup. If its cache is root-owned, the helper prints explicit sudo instructions
instead of escalating. `--restore` changes only the on-disk installation.
`build.json`, `installation.json` and `active.json` record paths and hashes.
Future login loading uses the reviewed path/hash in `hyprland/plugins.lua`;
update that registry deliberately after upgrading.
After a Hyprland upgrade, review/rebase rather than bypassing ABI checks.

Test suites are not shipped. Compilation and config verification do not certify
physical gestures, DnD handoff, special workspace rendering or multi-monitor behavior.
