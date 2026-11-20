# niri → Hyprland port

Checked on 2026-11-17; shell profiles added/checked on 2026-11-18:

| Component | Version |
| --- | --- |
| Hyprland | 0.57.2, commit `11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947` |
| niri | 26.04, commit `8ed0da4` |
| Dux Modular Shell (DMS) | 2.1.2 |
| Noctalia | 5.4.1 (native, not the old Quickshell shell) |
| xdg-desktop-portal-hyprland (XDPH) | 1.5.0 |
| Quickshell | 0.3.2 |
| hypridle / hyprlock | 0.1.8 / 0.9.7 |

Hyprland's release wiki is versioned at **0.57.0** for the 0.57 series,
not at every patch release. The installed Lua stubs and exact **v0.57.2**
source were also checked, particularly the window/monitor metadata and
scrolling messages. Do not replace these APIs with examples from the latest-git wiki.

## Files and precedence

`hyprland.lua` loads manual `hyprland/*.lua` modules first, then **only the selected
shell's** overrides. Manual settings remain editable; selected-shell overrides
take priority. The final urgency rule derives its palette from those final colors.

Bindings are grouped by purpose under `hyprland/keybinds/`; `init.lua` loads the
normal-mode modules and `overview.lua` is registered by ScrollOverview setup.
See [the keybinding index](hyprland/keybinds/README.md). Literal bindings and
requires preserve DMS's offline shortcut discovery.

- Manual fallback: 15px corners, capitaine-cursors, handwritten border/shadow colors.
- Initial DMS overrides: 16px corners, miku-cursor-linux at 24px,
  generated border colors, and `#00000070` shadow color.
- DMS output/layout/cursor/window-rule files were seeded from the **active**
  niri includes. DMS may regenerate them when its settings change.
- `dms/input.lua` was initially an empty seed because niri's corresponding file
  was not included. DMS has since regenerated input/layout/window-rule fragments
  with its own settings (including per-device input and 4px gaps); those GUI-owned
  updates are preserved rather than forced back to the initial port values.
- `dms/binds.lua` is intentionally empty. `dms/binds-user.lua` is available
  for DMS shortcut-editor overrides. Do not run `dms setup` casually: it can
  replace the main config and populate conflicting stock shortcuts.
- When replacing a binding in `dms/binds-user.lua`, use `hl.unbind("EXACT KEY")`
  before the replacement. Hyprland otherwise executes duplicate bindings.

The initial port imported niri's active `keybinds.kdl`, `binds/dms-specific.kdl`,
and `binds/obs-livesplit.kdl`. The optional `binds/noctalia-specific.kdl` actions
are now translated to **installed Noctalia 5.4.1** IPC. The unused stock
`dms/binds.kdl` and `dms/binds-next.kdl` remain disabled.

### One-line DMS / Noctalia selector

Near the top of **`hyprland.lua`**, change only:

```lua
local shell = "dms" -- change to "noctalia"
```

Then start a **fresh Hyprland login**. Bindings/colors follow the selection on
reload, but the running shell is deliberately switched **only at session startup**:
stopping a shell on reload could tear down its lock screen. Do not treat a reload
as a safe live shell swap, especially while locked.

- DMS mode loads the existing `dms/*.lua` files and DMS UI commands.
- Noctalia mode skips all DMS overrides, uses `noctalia/windowrules.lua`, and loads
  Noctalia 5's optional generated `hypr/noctalia.lua` via its `apply_theme()` API.
  If absent, no additional theme is applied; manual colors remain in effect.
  Manual monitor/layout/cursor settings remain unchanged.
- Enable Noctalia's built-in Hyprland color template in its settings if desired.
  Its hook recognizes the conditional include and must not append an unconditional
  theme include that overrides DMS. Disabling that template removes its generated
  file. There is no backup palette.
- Noctalia UI actions use `noctalia msg`, not obsolete `qs -c noctalia-shell ipc`.
  Power menu, notification history, dismissal, DND, lock, and all three screenshot
  shortcuts are translated. Notification history opens Control Center's notifications
  tab; dismissal clears visible notifications (the Noctalia 5 equivalent).
- The pinned ScrollOverview v4 plugin supplies **Super+Tab, Super+O** and the
  four-finger overview gesture in either shell profile. Without it these remain
  unbound; no shell overview or older plugin implementation is substituted.
  The Noctalia cheatsheet remains unbound.
- Noctalia 5 does **not** automatically migrate the old `~/.config/noctalia/settings.json`
  or Quickshell plugins. Those files were left untouched; this is a compositor
  integration port, **not a migration of the old bar/widgets/plugins to v5 TOML**.

`scripts/start_shell.py` imports the actual Hyprland environment before starting
services. At login it uses the existing **`dms.service`**, or stops that service
and starts **`hyprland-noctalia.service`**, a transient systemd user unit bound to
`graphical-session.target` with restart-on-failure. Switching back to DMS stops
only that managed Noctalia unit. Missing programs are checked before stopping the
other shell, and startup failure attempts to restore the previously running service.
No global service is enabled/disabled, no unrelated process is killed, and niri's
existing DMS startup remains unchanged. Do not separately autostart both shells.
This helper is not a safe manual hot-swap tool and must not be invoked while locked.

### Shell-crash-independent hardware and media controls

`hyprland/controls.lua` owns the shared commands. They execute system tools directly
on **every press**, rather than depending on an IPC error/timeout fallback:

| Keys | Direct action |
| --- | --- |
| Audio volume up/down, mute | WirePlumber `wpctl`, default output; 5% steps, increase capped at 100% |
| Microphone mute (`XF86AudioMicMute`) | `wpctl`, default input |
| Display brightness up/down | `brightnessctl --class=backlight`, 5% steps, minimum raw value 1 |
| Next/previous/play-pause, plus Super+Shift+N/B/P | Same `playerctl` actions in either profile |
| Super+Shift+period/comma | `playerctl` player volume ±0.05 |

Hardware keys remain allowed while locked. Controls and their existing aliases
also work inside keybinding submaps, including overview. Volume/brightness repeat on hold;
mute/playback/track toggles do not repeatedly fire on a held key. AudioPause keeps
the original play/pause-toggle mapping. Existing xremap F6/F7/F8 mappings are
unchanged; ordinary F1…F12 are **not** globally hijacked by Hyprland.

These commands require the underlying audio service/device/player, **not a running
desktop shell**. Player selection prefers `playerctld` if it is running, otherwise
the first available MPRIS player; it need not match a shell widget's manually chosen
player. Brightness keys control the **kernel display backlight**, not external
DDC/CI-only monitors. Shell OSD/feedback is not guaranteed, especially after a crash.
UI functions (notifications, power menu, screenshots, overview, lock UI) still require
the selected shell; no independent locker or additional OSD daemon was enabled.

## Layout and navigation decisions

| niri behavior | Hyprland implementation / difference |
| --- | --- |
| Infinite horizontal columns | Native `scrolling` layout; default width 100%, presets 1/3, 1/2, 2/3, 100% |
| Never center on ordinary focus | Native fit mode; horizontal focus/swap do not wrap at endpoints |
| Lone column retains its width | `fullscreen_on_one_column = false` |
| 6px gaps plus struts | **6px gaps only**, as requested; struts/adjacent-column peek omitted. `gaps_in = 3` accounts for Hyprland adding it on both adjoining sides |
| Up/down within a column, then workspace | `navigation.lua` uses real `window.layout.column.windows` and `index_in_column` metadata; no geometric guessing or external polling |
| Move window up/down, then another workspace | Same boundary helper, followed by native move; follows the moved window |
| Super+Shift+arrows / H/J/K/L on floating windows | Native relative movement in 50 logical-pixel steps; repeatable, without scrolling-column or workspace-step actions. Tune `floating_move_step` in `hyprland/navigation.lua` |
| First/last column; move column to endpoints | Bounded repetitions of native focus/swap-column messages; no custom column reconstruction |
| Move a whole column to another workspace | **Active window/group only**, including numbered and wheel shortcuts |
| Ctrl+Up/Down/J/K reorders in overview | Workspace navigation in both modes; no DMS-overview workspace reordering |
| Center active column | Super+Z centers the scrolling column; on a floating window it instead uses native window centering within that monitor's reserved-area-adjusted workarea |
| Center visible columns | Lua computes the bounds of viewport-intersecting tiled windows and pans without resizing; **may focus the center column**, as approved |
| Reset automatic window height | Native absolute resize to approximately an equal share of the column; does not restore niri's automatic-height state |
| ±10% window height | Relative native resize based on logical monitor workarea |
| Super+minus/equal width resizing | Scrolling column resize for tiled windows; native horizontal resize for floating windows, in 10% logical-workarea-width steps |
| Initial floating size | Native `size = "monitor_w*0.9 monitor_h*0.9"` rule: 90% of logical monitor dimensions on first map, without persistent resizing hooks. Explicit app sizes and the Dynamic Share helper size remain exceptions; later resizing/placement uses normal Hyprland behavior |
| Super+backslash | Toggle focus between floating and tiled windows on the current workspace, preferring focus history; replaces the earlier group-toggle approximation |
| Super+Shift+Up/Down/K/J | Swap the selected tiled window with its exact neighboring row in the same scrolling column first; move to the adjacent monitor-local workspace only at the top/bottom boundary. Floating windows retain their 50px nudge |
| Drag navigation outside overview | Separate `edge-navigation` plugin: window move and external DnD drags dwell 500ms at a monitor edge; horizontal scrolling is continuous, vertical focus/workspace steps repeat after 700ms. Settings and hot-corner callbacks live in `hyprland/edge-navigation.lua`; overview retains its own edge input |
| Consume/expel | Native messages. Notably, **v0.57.2 source** implements `consume` as pulling the first window of the next column into the active column; it is not niri-identical |
| Column tabbed mode | Hyprland group toggle; it does **not** convert a whole stacked column into tabs |
| Sticky windows | Super+P pins **floating windows only**; tiled windows are not silently floated |
| Overview, Super+Tab / Super+O | Pinned ScrollOverview v4 in either shell profile; unbound without it. See `plugins/scrolloverview/README.md` |

### Per-monitor workspace dictionary

`workspaces.lua` maps **(monitor connector name, local number) → global ID**.
Global IDs are allocated individually on demand; no monitor has a reserved block.
Super+1…9 uses the focused monitor's dictionary; the corresponding Shift bind
moves the active window/group and follows it. Existing native workspaces are
adopted. Ordinary workspaces retain **native global numeric labels**; they are
not custom-named to local numbers. Thus the displayed number on a second monitor
may differ from the monitor-local Super+number shortcut.

### Actual-ID defragmentation and monitor transfers

On workspace/monitor lifecycle changes and property refreshes, the dictionary is
reconciled and **actual compositor IDs** are compacted into monitor clusters.
Monitors are ordered physically left-to-right, then top-to-bottom (connector name
breaks ties); each cluster follows its existing local-number assignments. There
are no fixed-size reserved ranges. Named/special workspaces, including
`dynamic-share-anchor` and the scratchpad, are not renumbered.

The renumbering first moves changing live workspaces to free temporary positive
IDs, then assigns their final IDs. It keeps the workspace objects, windows, layout,
and focus intact. Its own obsolete monitor-rule handles are disabled before the
transaction and replaced/reused afterward, so reused IDs do not retain the wrong
monitor assignment. Reentrant callbacks are guarded; lifecycle events are coalesced
onto a one-shot event-loop task, outside creation/destruction/swipe callbacks.
If a dispatcher fails, successful operations are rolled back and automatic
renumbering is suspended until config reload, with a notification.

This is **not atomic to external IPC observers**: they can see temporary IDs.
External fixed-ID workspace/window rules, application settings, and portal restore
tokens do not follow workspace objects and are **not rewritten**. Avoid adding
fixed per-ID rules that conflict with dynamic numbering. The ordinary native names
change along with their IDs, so workspace-share restoration may select the wrong
workspace after renumbering; this tradeoff was explicitly accepted.

**Super+Alt+Shift+Left/Right/Up/Down**, also **H/L/K/J**, moves the entire active
numbered workspace to the monitor in that direction using Hyprland's native
workspace move. All its windows move together. The destination's first unused
local slot is adopted and both ID clusters are reconciled. Nothing is moved when
there is no target monitor. Named/special workspaces are intentionally excluded.

The dictionary is saved as plain TSV to
`$XDG_CACHE_HOME/hypr-niri-workspaces.tsv` (normally `~/.cache/…`) on config unload
and compositor shutdown. It is restored on reload. Native monitor moves are
reconciled so a workspace is not stolen back to its old output. Reservations for
disconnected monitors are dropped; their migrated live workspaces are adopted on
their actual outputs instead of being stolen back on reconnect.

Local shortcut slots remain stable when empty workspaces disappear; navigation
can recreate such a slot. Actual-ID defragmentation does not fill local-number
holes or swap local shortcut assignments. Monitor unplug/replug behavior and
existing DMS workspace labels need a live session check.
The named capture workspace is deliberately outside this numbered dictionary.

## Input, appearance, and startup

- Preserved Caps level-5 option, numlock, 400ms delay/50Hz repeat, touchpad tap,
  natural scrolling, two-finger scroll, drag/drag-lock, middle emulation and DWT.
- Trackpoint-specific touchpad suppression (`dwtp`) omitted: no equivalent option.
- Native focus-follows-mouse, **without niri's exact 40% scroll cap**.
- Cursor hides after 3 seconds and on typing; keyboard navigation does not warp it.
- Gestures: **3-finger horizontal** scrolls the tape; **3-finger vertical** uses
  native, continuously animated **numeric-relative (`r±1`)** workspace switching
  whenever its next target agrees with local numbering. Each direction is chosen
  separately before a swipe. Only mismatches (such as local-number holes or the
  previous-workspace boundary that would enter `dynamic-cast`) use a discrete
  Lua fallback. The fallback honors inversion, cancellation, and the configured
  distance/cancel-ratio threshold, but does not implement native velocity forcing
  or track fingers 1:1. Defragmentation keeps native mode usable as much as possible.
  ScrollOverview uses **4-finger vertical** gestures for interactive open/cancel.
  Without it, **4-finger up** discretely toggles DMS overview (unbound in Noctalia).
  Check gestures on real hardware.
- Shadows use native range/render power, an approximation of niri's softness/spread.
- Only terminal windows explicitly get window blur by default; DMS can override it.
- Application IDs become Hyprland classes. RE2 matches the whole string, so substring
  matches were expanded where required. Floating sizes/positions use native rules.
  LiveSplitOne's 500px width uses a targeted native resize when it opens.
- `urgency.lua` tags urgent windows and applies the selected shell's error color to their
  borders; focus clears the tag. There is no urgency-cleared event, so a withdrawn
  request may stay colored until focus. Group lock colors are only a palette source,
  not an urgency matcher.
- Animations approximate niri 26.04: critically damped mass-1 springs at stiffness
  800 for movement/resize and 1000 for vertical workspace transitions; approximate
  exponential/quad 150ms open/close easing. Different renderers/shaders mean this
  is **not pixel-identical**. DMS controls its own overview/UI motion.
- `hyprland/animation-defaults.lua` preserves the pre-port Hyprland sample/default
  animation settings and is **not loaded**.
- Laptop/ASUS positions and modes are preserved. Laptop VRR uses fullscreen
  game/video mode (3), not niri's exact on-demand policy. The currently connected
  laptop reports **no VRR support**, so this cannot enable unsupported hardware.
- Xwayland is integrated; xwayland-satellite and hardcoded niri XAUTHORITY are omitted.
  Actual Hyprland session variables are imported into D-Bus/systemd at startup.
- Primary selection remains native: select-to-middle-click paste is not disabled.
- `focus_on_activate` enables native activation, not a recreation of niri's
  debug-only invalid-serial activation bypass. CSD negotiation remains compositor-native.
- xremap, dcal and the existing psst agents remain in autostart. No niri-only sticky
  or screen-time daemon is started. Selected-shell startup uses systemd supervision.
- The dummy mouse and hyprland-run sample rule were removed. Existing maximize-event
  suppression and the Xwayland drag-focus fix remain.

## Shortcut changes and extras

- **Super+Ctrl+D:** Do Not Disturb wins the duplicate assignment in niri.
- **Super+F4:** cycle scrolling/dwindle; extend the list in `hyprland/layout-switcher.lua`.
  **Super+D** cycles scrolling width or toggles dwindle split orientation.
  **Super+0** sets full column width or resets a dwindle split to 50/50.
- **Super+Shift+D:** native maximization fills the workarea rather than merely
  changing scrolling-layout presentation. Fullscreen/maximized workspace rules
  remove gaps, struts, borders and rounding while preserving the bar reservation.
  Browser Bitwarden extension popup windows float, including when their title
  arrives after mapping (`window.title`); normal website tabs are not matched.
- **Super+Shift+S / Super+Ctrl+S / Super+Ctrl+Shift+S:** selected-shell region/window/focused-output
  screenshots, no cursor, saved under `~/Pictures/Screenshots`. The shell controls the
  filename/UI rather than niri's `_nirisshot.png` naming/template.
- **Super+S / Super+Alt+S:** show the `magic` scratchpad / send a window there silently.
- **Super+left/right mouse drag:** move/resize retained.
- **Super+Ctrl+P:** toggle the focused window's `capture-private` tag. A native
  `no_screen_share` rule excludes it from compositor-managed capture; the native
  Dynamic Share plugin also checks it before rendering/publishing. It remains
  visible locally; this is not a guarantee against applications recording themselves
  or other capture paths outside the compositor.
- **Super+Shift+R:** niri's focused-window dynamic sharing action, now using the
  native plugin. **Super+Ctrl+R:** focused workspace. **Super+Ctrl+Shift+R:**
  focused monitor. The picker has no global shortcut.
- **Super+Ctrl+BackSpace:** clear the target, retaining a black idle stream.
  These actions also work in overview submaps. **Ctrl+Shift+R is not bound**
  (browser refresh is unchanged). Reset/start/stop/glow have no new global binds.
- No cursor-zoom or terminal-swallowing extras were enabled.

## Dynamic focused-window sharing

Production controls now use the **native Dynamic Share plugin**, not the old
Quickshell mirror. See [plugins/dynamic-share/README.md](plugins/dynamic-share/README.md)
for exact ABI requirements, editable per-target styles, and remaining parity gaps.

1. Request screen sharing normally in your application.
2. In the stock consent picker, choose the **Dynamic Share (switchable window)**
   **window** entry, even when the eventual target is a monitor or workspace.
3. Use **Super+Shift+R** on a focused window, or the shortcuts above, to retarget
   that same stream. The optional picker API/CLI reuses the stock XDPH graphical
   dialog without starting another portal stream. `picker` in
   `hyprland/dynamic-share-settings.lua` can select a custom dmenu-compatible command.
4. Clear with **Super+Ctrl+BackSpace** to publish opaque black with your
   configured idle text. Stop sharing normally in the application when finished.

`hyprland/capture.lua` calls the plugin directly. The central registry in
`hyprland/plugins.lua` and `scripts/start_plugins.py` loads missing reviewed plugins
on login. `hyprland.lua` applies `hyprland/dynamic-share-settings.lua` on reload.
The loader does not replace
a running plugin or reset its selected target. The owned helper is an idle
placeholder, not a Quickshell mirror; capture is request-driven.
Its workspace is the true special workspace `special:dynamic-share-anchor`,
hidden by the overview's special-workspace filter. Runtime configuration lives
under `hyprland/`, not inside the plugin directory. The unused demo is removed.

The original niri window-target shortcut is preserved. Monitor, workspace,
and clear shortcuts remain active; the picker shortcut was removed. Experimental
Super+Ctrl+Alt+R/M/W/S aliases are no longer loaded. Reset, start/stop, and
indicator toggling remain Lua/CLI/settings-only, as requested.

Window targets request native window content, popups and cursor. Workspace targets
use a windows-only native scene, without shell layers. Monitor targets deliberately
capture the entire output, subject to compositor privacy masks. Cleared, private,
closed, hidden or locked targets become black rather than falling back to a desktop.
Workspace indicator geometry excludes shell-reserved workarea edges; monitor
indicators retain the full output boundary.

**Accepted plugin-only limits:** all Dynamic Share consumers use one global
target. A new/restored share can inherit that target, because the plugin has no
reliable portal-session identity. XDPH starts the stream immediately, not after
selection. Clear the target first if a new share must begin empty. End-to-end
application, queued-frame privacy, sizing, cursor and local-indicator capture
exclusion still require live validation; compilation alone is not a privacy guarantee.

### Removed legacy code

The Quickshell sharing implementation, custom-picker wrapper, inactive hyprexpo
config, optional demo bindings and all test suites are removed.
`xdph.conf` uses the stock picker. Installed native plugin rollback libraries
remain outside the repository and are not deleted.
Optional plugin/theme/hot-corner fallbacks are removed; core terminal, launcher,
navigation, media controls and safe loader rollback paths remain.

## Inactive hypridle / hyprlock

Both installed versions match the current releases checked. Neither was enabled,
started, or used to lock the session. The selected shell is responsible for locking/idling.
Super+Delete calls `loginctl lock-session` in DMS mode and `noctalia msg session lock`
in Noctalia mode. A crashed/missing shell does **not** gain a standalone lock fallback.

`hypridle.conf` now uses Hyprland 0.57 Lua DPMS dispatches for sleep/resume and idle
timeouts instead of niri/legacy dispatch syntax. Timeout values and locking policy
are unchanged. `hyprlock.conf` needed no syntax changes. Used keys were reviewed
against their exact tagged source and checked offline with installed libhyprlang
(schema/structure, not a live authentication/rendering test). Do not run both shell
idle management and hypridle without first reviewing their overlapping policies.

## Validation

Run from `~/.config/hypr`:

```sh
Hyprland --verify-config -c "$PWD/hyprland.lua"
dms keybinds show hyprland
hyprctl reload config-only
hyprctl configerrors
```

The verifier reports `config ok` on Hyprland 0.57.2. Outside a Hyprland session it
can also print a socket-binding warning; that is separate from config parsing.
Test suites are intentionally not shipped. Both shell profiles can be checked
with the installed verifier using a temporary entry-point copy that selects the
other profile; do not switch the live shell just to validate configuration.
Timer initialization is skipped without outputs: Hyprland 0.57.2's verifier
crashes when cleaning timers without an event loop.

Bindings remain literal declarations in `hyprland/keybinds/` for DMS discovery.
See [README.md](README.md) for layout-aware mappings, the Lua-only OBS toggle,
and missing-only plugin startup. `Super+F4` cycles scrolling/dwindle on numbered
workspaces; layout choices and binding toggle state reset on config reload.

Permission rules are startup-only in this Hyprland version. The explicit
allowlist and unknown-operation prompts activate on the next login, not midway
through an existing session. This is not an app-launch firewall or IPC sandbox.

**Still requires interactive validation:** fresh-login startup of each shell,
permission dialogs, Noctalia UI/locking/theming, physical function-row keys,
drag/drop, multi-monitor behavior, capture privacy, and crash/restart behavior.
Config verification does not certify the lock screen or migrate Noctalia's
legacy application preferences.

## Sources

- [Hyprland 0.57 release wiki](https://wiki.hypr.land/0.57.0/)
- [Scrolling](https://wiki.hypr.land/0.57.0/configuring/layouts/scrolling-layout/)
- [Dispatchers](https://wiki.hypr.land/0.57.0/configuring/core/dispatchers/)
- [Gestures](https://wiki.hypr.land/0.57.0/configuring/core/binds/gestures/)
- [Lua events](https://wiki.hypr.land/0.57.0/configuring/core/advanced-configuration/events/)
- [Window rules](https://wiki.hypr.land/0.57.0/configuring/core/rules/window-rules/)
- [Exact scrolling source](https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/layout/algorithm/tiled/scrolling/ScrollingAlgorithm.cpp)
- [Exact window metadata](https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/config/lua/objects/LuaWindow.cpp)
- [Exact monitor metadata](https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/config/lua/objects/LuaMonitor.cpp)
- [Exact ID dispatcher/monitor transfer API](https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/config/lua/bindings/LuaBindingsDispatchers.cpp)
- [Exact workspace identity changes](https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/workspace/HLWorkspace.cpp)
- [Exact native swipe behavior](https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/managers/input/UnifiedWorkspaceSwipeGesture.cpp)
- [Exact workspace selector ordering](https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/state/workspace/Resolver.cpp)
- [niri 26.04 animation defaults](https://github.com/niri-wm/niri/blob/v26.04/docs/wiki/Configuration:-Animations.md)
- [niri 26.04 layout](https://github.com/niri-wm/niri/blob/v26.04/docs/wiki/Configuration:-Layout.md)
- [DMS 2.1 compositor integration](https://duxlabs.dev/docs/dms/compositors)
- [Noctalia IPC (rolling docs; cross-checked against installed 5.4.1 CLI)](https://docs.noctalia.dev/noctalia/ipc/)
- [Noctalia 5.4.1 source](https://github.com/noctalia-dev/noctalia/tree/v5.4.1)
- [Noctalia 5.4.1 Hyprland Lua template](https://github.com/noctalia-dev/noctalia/blob/v5.4.1/assets/templates/hyprland/hyprland.lua)
- [Quickshell 0.3.2 capture API](https://quickshell.org/docs/v0.3.2/types/Quickshell.Wayland/ScreencopyView/)
- [XDPH 1.5 picker protocol](https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/v1.5.0/src/shared/ScreencopyShared.cpp)
- [XDPH 1.5 portal sessions](https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/v1.5.0/src/portals/Screencopy.cpp)
- [wl-mirror's pending window support](https://github.com/Ferdi265/wl-mirror/issues/61)
- [hypridle 0.1.8 source](https://github.com/hyprwm/hypridle/blob/v0.1.8/src/config/ConfigManager.cpp)
- [hyprlock 0.9.7 source](https://github.com/hyprwm/hyprlock/blob/v0.9.7/src/config/ConfigManager.cpp)
