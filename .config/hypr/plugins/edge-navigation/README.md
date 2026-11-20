# Edge Navigation — separate Hyprland plugin

Independent of ScrollOverview and Dynamic Share. Pinned to Hyprland **0.57.2**,
commit `11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947`, Lua **5.5** and the matching
runtime ABI. No function hooks, input grabs, synthesized buttons, cursor warps,
portal restarts, shell overrides or compositor rebuilds.

## Behavior and configuration

Edit **`hyprland/edge-navigation.lua`**, then reload config.

- `drag_edges = true`: edge navigation outside overview.
- `external_drags = true`, `window_drags = true`: independent file/application
  DnD and native window **move** support. Resizing never navigates.
- `edge_size = 16`: logical pixels inward from each monitor's physical edge.
- `edge_delay = 500`: dwell in milliseconds before first movement; `0` is immediate.
- `repeat_delay = 700`: subsequent discrete focus/workspace steps while held.
- `smooth_scroll = true`, `scroll_speed = 900`: continuous horizontal scrolling
  after dwell, in logical pixels/second. Focus follows the column crossing the
  viewport center. Set smooth scrolling false for delayed column-by-column focus.
- Up/down focus an adjacent window in the scrolling stack, then navigate the
  adjacent **monitor-local** numbered workspace at a boundary.
  Floating/non-scrolling targets use directional window selection first.
  Named/special workspaces are not assigned new local-number slots.
- `monitors = {}` allows all connectors; a connector-name array restricts the
  plugin to those monitors. Crossing monitors resets dwell; it does not create
  a pointer barrier or automatically transfer focus across a monitor boundary.
- Leaving a zone, ending the drag, entering overview, changing monitors,
  locking the session, reloading config or unloading the plugin stops/reset
  the relevant navigation. Continuous camera ownership is restored on exit.

Window dragging uses Hyprland's existing drag controller. At a workspace switch
the still-floating dragged target follows the destination, preserving its
geometry and native grab; Hyprland handles the eventual drop/retiling.
The workspace switch deliberately uses the **internal** no-button-release path,
then applies native animation, pinned-window migration and workspace events.
External DnD offers/drops remain owned by the application's native protocol.

## Hot corners

All four corners are configurable separately in the `corners` table:

```lua
top_left = {
    enabled = true,
    size = 4,             -- Logical square size.
    delay = 300,          -- Milliseconds; 0 is immediate.
    during_drag = false,  -- File and window move drags.
    action = function(monitor)
        hl.dispatch(hl.plugin.scrolloverview.overview("toggle " .. monitor))
    end,
},
```

Any Lua callback / native `hl.dispatch` action can be used. A corner without an
action stays disabled. Top-left defaults to the existing overview toggle; the
other three corners default disabled. Actions fire **once per entry**, not on
every timer tick. Enabled drag corners take precedence over drag edges.

Hot corners are owned only by this plugin; there is no Lua polling fallback.
Overview keeps its existing own edge-navigation implementation (including
window drags); this plugin yields directional edges while that submap owns input.

## Build, load, rollback

From `.config/hypr`:

```sh
python3 plugins/edge-navigation/build.py        # Build only.
python3 plugins/edge-navigation/build.py --load # Explicit initial load.
```

Libraries are copied to unique, versioned directories under
`~/.local/share/hypr/edge-navigation/`; mapped libraries are never overwritten.
The loader validates the running ABI and new config errors, and unloads only
its new plugin on failure. It refuses to implicitly replace an existing copy.
It never unloads/rebuilds/switches the overview or sharing plugins.
The central startup registry in `hyprland/plugins.lua` contains the reviewed
path/hash for future login loading. Update it after a deliberate upgrade.
Unload the exact library in `build.json` and reload config for immediate rollback.
Unloading disables these hot corners rather than enabling an alternative implementation.

Diagnostics (no input action):

```sh
hyprctl repl 'local s=hl.plugin.edge_navigation.status(); return "enabled="..tostring(s.enabled).." window_drags="..tostring(s.window_drags).." delay="..s.edge_delay'
```

Test suites are not shipped. Physical DnD, XWayland drag bridging, native window
drop/retiling and multi-monitor behavior need interactive validation before
treating this experimental plugin as stable.

Version 0.1.2 reconnects the custom-event Lua bridge during configuration:
Hyprland 0.57 recreates its Lua event handler on reload without subscribing it
to events from already-loaded plugins. Zero-delay corners run on pointer entry;
positive delays use the native dwell timer. Corner actions fire once until exit.
