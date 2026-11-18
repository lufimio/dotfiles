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
  If absent, `noctalia/colors.lua` supplies the existing **Ayu Blue** palette seeded
  from the saved Noctalia `colors.json`. Manual monitor/layout/cursor settings remain
  in effect: the commented niri `noctalia.kdl` include had **no actual file** to port.
- Enable Noctalia's built-in Hyprland color template in its settings if desired.
  Its hook recognizes the conditional include and must not append an unconditional
  theme include that overrides DMS. Disabling that template removes its generated
  file; the independent seed remains usable. No template was enabled during porting.
- Noctalia UI actions use `noctalia msg`, not obsolete `qs -c noctalia-shell ipc`.
  Power menu, notification history, dismissal, DND, lock, and all three screenshot
  shortcuts are translated. Notification history opens Control Center's notifications
  tab; dismissal clears visible notifications (the Noctalia 5 equivalent).
- Without the optional native HyprExpo plugin, **Super+Tab, Super+O, four-finger
  up, and Super+Shift+? are unbound in Noctalia mode**, as requested. No window-switcher
  or incompatible old cheatsheet plugin is substituted. With a compatible HyprExpo
  loaded, its independent overview replaces the overview actions in either shell
  mode; the Noctalia cheatsheet remains unbound. See [HYPREXPO.md](HYPREXPO.md).
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
also work inside keybinding submaps, including HyprExpo. Volume/brightness repeat on hold;
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
| First/last column; move column to endpoints | Bounded repetitions of native focus/swap-column messages; no custom column reconstruction |
| Move a whole column to another workspace | **Active window/group only**, including numbered and wheel shortcuts |
| Ctrl+Up/Down/J/K reorders in overview | Workspace navigation in both modes; no DMS-overview workspace reordering |
| Center active column | Native center, Super+Z |
| Center visible columns | Lua computes the bounds of viewport-intersecting tiled windows and pans without resizing; **may focus the center column**, as approved |
| Reset automatic window height | Native absolute resize to approximately an equal share of the column; does not restore niri's automatic-height state |
| ±10% window height | Relative native resize based on logical monitor workarea |
| Consume/expel | Native messages. Notably, **v0.57.2 source** implements `consume` as pulling the first window of the next column into the active column; it is not niri-identical |
| Column tabbed mode | Hyprland group toggle; it does **not** convert a whole stacked column into tabs |
| Sticky windows | Super+P pins **floating windows only**; tiled windows are not silently floated |
| Overview, Super+Tab / Super+O | Optional guarded HyprExpo native scrolling overview; without it, DMS overview or unbound in Noctalia. See `HYPREXPO.md` for differences |

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
`dynamic-cast` and the scratchpad, are not renumbered.

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
  Compatible HyprExpo uses **4-finger up/down** for interactive open/cancel.
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

- **Super+Ctrl+D:** Do Not Disturb wins the duplicate assignment in niri. Super+0
  still sets full column width; no separate maximize-column toggle was added.
- **Super+Shift+S / Super+Ctrl+S / Super+Ctrl+Shift+S:** selected-shell region/window/focused-output
  screenshots, no cursor, saved under `~/Pictures/Screenshots`. The shell controls the
  filename/UI rather than niri's `_nirisshot.png` naming/template.
- **Super+S / Super+Alt+S:** show the `magic` scratchpad / send a window there silently.
- **Super+left/right mouse drag:** move/resize retained.
- **Super+Alt+B:** toggle the focused window's `capture-private` tag. A native
  `no_screen_share` rule excludes it from compositor-managed capture; the custom
  mirror also blanks it explicitly. A notification confirms the toggle. It remains
  visible locally; this is not a guarantee against applications recording themselves
  or other capture paths outside the compositor.
- No cursor-zoom or terminal-swallowing extras were enabled.

## Dynamic focused-window sharing

This uses **Quickshell**, not wl-mirror: installed wl-mirror 0.18.5 only captures
outputs/regions, which would risk exposing unrelated pixels after switching apps.
No new package was installed.

1. In a Hyprland session, request screen sharing normally.
2. The XDPH custom picker wrapper starts the isolated mirror and controller.
3. In the **normal consent picker**, choose the **`dynamic-cast` workspace**.
4. Focus a source window and press **Super+Shift+R**. Repeat on another window to
   retarget the same maximized mirror. Nothing is captured before explicit selection.
5. Stop sharing normally to close the mirror/controller.

The empty named workspace is persistent because **XDPH builds its allowed source
list before starting a custom picker**. The viewer/controller themselves run only
on demand. Choosing another picker source or canceling also stops them. Merely
focusing another app does not stop the mirror.

The wrapper preserves consent and ordinary source selections. It removes the
restore-token flag **only for the mirror target**, since token restoration would
bypass the picker/startup hook. Ordinary shares retain the existing token behavior.
Whole-workspace sharing remains available **normally through XDPH**; dynamically
mirroring an arbitrary workspace is not implemented.

The source is resolved by its exact Hyprland address to a Wayland toplevel, not by
title/class/visible screen geometry. Missing/closed/private sources and the mirror
workspace itself produce a blank view. All other apps keep their original positions.
The captured workspace is still a real workspace: **do not put unrelated apps there**.
Workspace capture can also include output-global panels/layers; it is not equivalent
to capturing only the mirror surface.

### Reliability and maintenance

This is a **custom integration, not a supported Hyprland/niri feature**. It should
not need frequent editing on these versions, but occasional maintenance after major
Hyprland/Quickshell/XDPH updates is realistic. No zero-maintenance guarantee is possible.

- `dynamic-cast/shell.qml`: Quickshell 0.3.2's `ScreencopyView` and Hyprland toplevel mapping.
- `scripts/dynamic_cast.py`: XDPH 1.5's workspace-list and picker-selection format;
  an unsupported format refuses the mirror rather than falling back to screen capture.
- One active dynamic-mirror portal session at a time is supported. Concurrent
  startup requests from multiple sharing applications are **not supported/tested**.
- Lifecycle follows real portal `Start`/`Session.Close` messages, **not** Hyprland's
  500ms no-frames event, which also fires on paused streams. This requires Python
  PyGObject/GIO and session-bus `BecomeMonitor` permission. If denied, mirror startup
  fails. Only lifecycle traffic is monitored; it is not logged.
- GUI failure, portal restart, or failed source resolution never selects a desktop
  output instead. If a share application abandons startup without closing its portal
  session, manual cleanup may be needed.
- Runtime socket/log: `$XDG_RUNTIME_DIR/hypr-dynamic-cast-<instance hash>/`.
  Emergency cleanup: `python3 ~/.config/hypr/scripts/dynamic_cast.py stop`.
- Disable the custom feature by removing `custom_picker_binary` from `xdph.conf`
  and the capture bindings/module; ordinary portal sharing is independent.

**Not yet live-tested:** off-workspace redraw, picking the persistent workspace,
pause/resume/stop, retargeting, multi-monitor gestures, and privacy behavior on each
capture route. Offline tests do not establish that screen sharing is production-ready.
Test with non-sensitive content before relying on it.

`xdph.conf` is read when the portal backend starts. No running portal was restarted
while porting from the current niri session; start a fresh Hyprland session for testing.

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
lua tests/config.lua
lua tests/config.lua noctalia
lua tests/config.lua dms hyprexpo
lua tests/config.lua noctalia hyprexpo
lua tests/config.lua dms old-hyprexpo
lua tests/config.lua noctalia old-hyprexpo
lua tests/workspaces.lua
python3 tests/test_shell.py
python3 tests/verify_profiles.py
python3 tests/test_dynamic_cast.py
dbus-run-session -- python3 tests/test_dynamic_cast.py --dbus
/usr/lib/qt6/bin/qmllint dynamic-cast/shell.qml
dms keybinds show hyprland
```

The verifier reports `config ok` on Hyprland 0.57.2. Outside a Hyprland session it
can also print a socket-binding warning; that is separate from config parsing.
The Lua tests cover precedence, unique shortcuts, vertical navigation, dictionary
allocation, logical workarea calculations, centering, pinning, and urgency tags.
The workspace suite covers actual-ID collision cycles, rollback, rule retirement,
event coalescing/reentrancy, monitor transfers/unplug, numeric labels, and hybrid
gesture selection/cancellation. Timer initialization is skipped without outputs:
Hyprland 0.57.2's config verifier crashes when cleaning timers without an event loop.
Python tests cover the picker wire format/token handling and actual Start/Close
monitoring on an **isolated test D-Bus**, without screen capture or session locking.
The selector tests cover **142 DMS / 139 Noctalia** unique bindings, absence of
Noctalia overview/cheatsheet actions, selected-only theming/rules, and startup-only
shell selection. Python tests execute controls against fake device/player commands
with failing shell IPC, so no real volume/brightness/playback change occurs. Startup
tests mock all systemd operations; no real shell was stopped, started, or crashed.
Both profiles also pass the installed Hyprland verifier. DMS's static parser does
not evaluate loaded-plugin conditionals: it can list optional HyprExpo/submap
bindings even when that plugin is absent. Plugin-present behavior is covered by
mocks, not by installing or loading the plugin. See `HYPREXPO.md`.

**Still requires live testing:** starting each shell in a fresh Hyprland session,
Noctalia UI actions/locking/theming, device permissions, physical function-row keys,
and crash/restart behavior. These tests do not certify the lock screen or migrate
Noctalia's legacy application preferences.

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
