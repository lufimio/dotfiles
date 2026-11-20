# Dynamic Share — experimental native plugin

**0.3.1-experimental** adds independent window/workspace/monitor indicator styles
and workspace outlines that exclude shell-reserved workarea edges. It retains
0.3.0's picker, source-sized exports, and configurable black idle screens.
**0.3.1 is loaded, with hook/helper readiness checked, but capture is not fully
verified end-to-end.** Do not use it for sensitive material until the live
acceptance checks below pass.

Supported stack: Hyprland **0.57.2**, commit
`11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947`, XDPH **1.5.0** at
`/usr/lib/xdg-desktop-portal-hyprland`. No compositor/portal rebuild, backend
replacement, or audio routing is involved. This uses **unstable internal hooks**;
the exact header/runtime ABI check is mandatory.

## Behavior and niri parity

| Feature | Plugin behavior |
| --- | --- |
| Persistent switchable portal source | Owned idle helper appears as **Dynamic Share (switchable window)**; choose this **window** in the normal share picker, even for monitor/workspace targets |
| Change source without restarting the app's share | Window, monitor, or workspace target; existing portal source/PipeWire node is retained |
| Explicit/focused selection | Lua API, stock XDPH graphical picker, configurable dmenu command, and CLI |
| Window content | Native standalone rendering requests subsurfaces, popups, and the cursor when requested by XDPH; live validation pending |
| Whole monitor | Native mirror capture, privacy masks, and requested cursor |
| Workspace | Native windows-only workspace scene, without desktop shell; does not activate or relayout that workspace |
| Output sizing | Source-sized by default; `"fixed"` fits/letterboxes into the helper-sized canvas |
| Empty/private/closed/hidden/locked source | Opaque black with configurable plain text, default **Nothing is being shared** |
| Local shared-target feedback | Optional border/inner glow; intended final-output-only painting, **capture exclusion not yet proven live** |
| New portal share starts blank every time | **Not supported reliably:** XDPH's frame requests have no reliable portal-session identity; a new share can inherit the global target |
| Delay stream startup until selection | **Not supported:** XDPH starts the stream immediately, with black idle frames if no target |
| Per-application target | **Not supported:** Dynamic Share consumers use one global target |

Ordinary shares are not retargeted. Selecting a target alone does not start a
portal stream. `clear()` keeps existing Dynamic Share streams alive but empty.
Empty streams retain their last usable source-sized canvas (initially 1280×720).
Some applications/encoders may reject size changes; use `"fixed"` in that case.
The helper's own visible surface remains static black, never a local preview.

These are accepted **plugin-only** differences, not full niri parity.

## Settings

All runtime configuration lives under `hyprland/`, not in this plugin directory.
Edit the `settings` table in `hyprland/dynamic-share-settings.lua`, or configure a loaded 0.3.1
plugin directly:

```lua
local ok, reason = hl.plugin.dynamic_share.configure({
    empty_text = "Nothing is being shared", -- "" gives plain black
    empty_font_size = 32,                   -- integer 8–128
    sizing = "source",                     -- "source" or "fixed"
    indicator = {
        enabled = false, -- opt in after live testing
        windows = true,
        workspaces = true,
        monitors = true,
        window = {
            border_color = "#f38ba8", -- #RRGGBB or #RRGGBBAA
            border_width = 3,         -- logical pixels, 0–32; 0 hides border
            glow_color = "#f38ba8",
            glow_size = 16,           -- logical pixels, 0–128; 0 hides glow
            glow_opacity = 0.25,      -- finite number, 0–1
            radius = 10,              -- logical pixels, 0–128
        },
        workspace = {
            border_color = "#94e2d5",
            border_width = 2,
            glow_color = "#94e2d5",
            glow_size = 12,
            glow_opacity = 0.3,
            radius = 8,
        },
        monitor = {
            border_color = "#cba6f7",
            border_width = 4,
            glow_color = "#cba6f7",
            glow_size = 24,
            glow_opacity = 0.4,
            radius = 0,
        },
    },
})
assert(ok, reason)
```

The singular `window`, `workspace`, and `monitor` tables are independent styles;
the plural booleans enable/disable their respective indicators. Partial tables
preserve other current settings, including other target kinds. Legacy flat
appearance fields directly under `indicator` still update all three styles;
nested fields override them. Invalid settings are rejected without applying a
partial style update.

The checked-in setup starts all three styles with your previous shared values.
When an older 0.3.0 plugin remains loaded, setup temporarily flattens the window
style into its single-style API; separate styles and workarea geometry require
0.3.1. `status().indicator_per_target` identifies support.

Text is plain UTF-8, not markup,
limited to 4096 bytes with no NUL. It is cached, centered, fitted, and wrapped/
ellipsized as needed. The underlying frame is always opaque black.

The indicator outlines the selected window, the entire selected monitor, or the
usable area of the visible selected workspace. Workspace borders are inset from
Hyprland's logical shell reservations on all four edges, scaled into output
pixels; panel/bar-reserved strips are outside the outline. Unreserved floating
overlays/popups do not change the workarea. This only changes indicator geometry,
not workspace layout or capture sizing. Hidden workspaces have no local outline. It paints
after the native OpenGL final-output step, skips capture/fake contexts, repaints
clean pixels beneath old/new outlines, and blocks direct scanout only on outputs
needing the outline or its cleanup. It uses an **inner glow**, not an outer shadow.
Activity is inferred from delivered frames and expires after one second without
a delivery; previews also count. It is not authoritative portal-session status.
Rotations, scaling, fullscreen/direct-scanout transitions, HDR and capture
exclusion still need live testing.

## Picker, CLI and Lua

The picker action now opens the installed **`hyprland-share-picker`** dialog
with window, workspace, and monitor tabs. This is a local target chooser: it
does **not** start a new portal stream, capture previews, or change the app's
existing portal source. The picker receives a catalog snapshot with display-only
IDs, which are translated back to the plugin's instance-scoped IDs. A **Clear
target** item is included in the Windows tab.

The stock dialog's **Remember this choice** checkbox is ignored here: no restore
token is created. Its **Region** tab cannot be hidden; region choices are rejected
without changing the target, because the plugin does not implement region targets.
Closing/canceling the dialog also leaves the target unchanged. Source lists are a
snapshot; reopen the picker to refresh them.

For a different picker, edit `picker` in `hyprland/dynamic-share-settings.lua`:

```lua
picker = {
    backend = "xdph", -- "xdph" or "dmenu"
    command = "fuzzel --dmenu --prompt 'Dynamic Share: '",
}
```

The keybinding reads these settings; standalone CLI calls use the flags below.
Set `backend = "dmenu"` to use `command`. Examples include
`rofi -dmenu -i -p 'Dynamic Share'`, `fuzzel --dmenu`, `wofi --dmenu`, and
`bemenu -i`. The command receives newline-separated choices on stdin and must
return **one exact offered line** on stdout, not a row index. Rows have unique
numeric prefixes so identical window titles cannot select the wrong identity.
An unsuccessful exit or empty result cancels. Unknown/multiple/custom lines are
rejected without changing the target.

Commands use shell-style argument splitting, **not implicit shell execution**.
For a deliberate pipeline/expansion, explicitly supply `sh -c '...'`. Configure
only commands you trust. The stock backend does not execute the dmenu command,
and errors never silently fall back to another UI.

From `.config/hypr`:

```sh
python3 plugins/dynamic-share/select-source.py pick
python3 plugins/dynamic-share/select-source.py pick --backend dmenu --command "fuzzel --dmenu"
python3 plugins/dynamic-share/select-source.py list
python3 plugins/dynamic-share/select-source.py window 7
python3 plugins/dynamic-share/select-source.py monitor eDP-1
python3 plugins/dynamic-share/select-source.py workspace 3
python3 plugins/dynamic-share/select-source.py focused-window
python3 plugins/dynamic-share/select-source.py focused-monitor
python3 plugins/dynamic-share/select-source.py focused-workspace
python3 plugins/dynamic-share/select-source.py clear
python3 plugins/dynamic-share/select-source.py status
```

Window/workspace numeric IDs come from `list`, **not** Hyprland window addresses
or workspace numbers. IDs are stable only within one plugin instance. Neither
picker backend resolves sources by title. Cancel preserves the target;
instance tokens reject stale picker selections after a
plugin reload. Explicit CLI IDs should be refreshed after a reload.

Lua methods under `hl.plugin.dynamic_share`:

- `select_focused()` / `select_window()` — focused window.
- `select_window(id[, instance])` — catalog window.
- `select_monitor()` — focused monitor; `select_monitor(id_or_connector[, instance])`.
- `select_workspace()` — focused special workspace if present, otherwise focused
  regular workspace; `select_workspace(id[, instance])` selects a catalog entry.
- `sources_json()` — JSON catalog including an instance token.
- `clear([instance])`, `reset()`, `start()`, `stop()`, `status()`.
- `configure(settings)`, `set_sizing("source" | "fixed")`.
- `is_window_cast_target(id)` — recent activity for a selected, non-private window.
- Aliases: `set_dynamic_cast_window`, `set_dynamic_cast_monitor`,
  `clear_dynamic_cast_target`.

Actions return `(ok, message)`; `sources_json`, `status`, and
`is_window_cast_target` return their named value. A private window can become the
selected target while returning `false` with a privacy explanation; video stays
empty. Ordinary invalid/stale IDs preserve the current target.

The main config uses `hyprland/keybinds/capture.lua` and `hyprland/capture.lua`:

| Shortcut | Action |
| --- | --- |
| Super+Shift+R | Select focused window — the original niri binding |
| Super+Ctrl+R | Select focused workspace |
| Super+Ctrl+Shift+R | Select focused monitor |
| Super+Ctrl+BackSpace | Clear target; retain the black idle stream |
| Super+Ctrl+P | Toggle the focused window's native capture privacy |

The picker has no global shortcut. Target/clear bindings work in submaps;
Ctrl+Shift+R remains unbound. Reset/start/stop/indicator
toggle have no new global bindings.

The stock portal picker exposes the plugin's dedicated window. Retired
Quickshell sources, custom-picker wrappers and demo bindings have been removed.

## Build — does not load anything

Requires matching Hyprland headers, C/C++23 compilers, Lua 5.5, Pango/Cairo,
Wayland client/server libraries, `wayland-scanner`, `wayland-protocols`, and
Python 3 for the picker. Interactive picking uses the installed
`hyprland-share-picker`, or your configured dmenu-compatible executable.

```sh
cmake -S plugins/dynamic-share -B /tmp/opencode/dynamic-share-native-v031-build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/opencode/dynamic-share-native-v031-build --parallel 4
```

Keep `dynamic-share.so` and `dynamic-share-anchor` **beside each other**. Use a
new build directory whenever a previous library/helper is loaded. The build
does not load or install either binary. Test suites are not shipped.

## Manual activation — only when ready

### Current dotfiles integration

`hyprland.lua` includes `hyprland/dynamic-share-settings.lua` on config reload;
production shortcuts are in `hyprland/keybinds/capture.lua`. The central startup
loader in `hyprland/plugins.lua` loads the reviewed binary/helper
pair from `$XDG_DATA_HOME/hypr/dynamic-share/0.3.1-experimental-3e56775b772e`
(`~/.local/share` by default), **only if no Dynamic Share plugin is loaded**.
It never replaces or unloads a running version. The current session has 0.3.1
loaded; subsequent logins use the durable 0.3.1 copy.
The plugin's own exact ABI check still applies after compositor upgrades.

Settings live in `hyprland/dynamic-share-settings.lua`; your enabled indicator and
appearance values are preserved. The plugin's own indicator default is off.
Remove the corresponding entry from `hyprland/plugins.lua` to
disable login loading; that does not unload the current
library or stop current streams. Binary copies are local to this machine, not
part of the dotfiles repository.

### Manual testing or switching

Save work and **stop experimental Dynamic Share streams first**. Never overwrite
a mapped plugin or load two versions together. Nothing in the build autoloads a
plugin, edits the main config, restarts portals, or switches production sharing.

For example, when upgrading from the former 0.3.0 test build:

```sh
hyprctl plugin unload /tmp/opencode/dynamic-share-native-v030-build/dynamic-share.so
hyprctl plugin load /tmp/opencode/dynamic-share-native-v031-build/dynamic-share.so
```

Use the actual originally loaded path if different. Loading/unloading schedules
a config reload. This dotfiles config reapplies setup and the production bindings
automatically. Check status after the reload:

```sh
hyprctl repl 'for k, v in pairs(hl.plugin.dynamic_share.status()) do print(k, v) end'
```

For standalone testing outside this main config, include
`hyprland.dynamic-share-settings` yourself.
The settings module silently places the owned helper on `special:dynamic-share-anchor`,
applies settings when supported, and calls `start()`.
This is a true special workspace, hidden by ScrollOverview's special-workspace
filter. Only the owned helper is migrated there; unrelated windows in an old
named helper workspace are not moved or closed.

Expect `helper_running`, `capture_hook_installed`, and `transport_ready` true
once mapped. `capture_active` means a frame was delivered in the last second.
Select a harmless target, then choose the dedicated Dynamic Share **window** in
your application. Use `clear()` to publish black; `stop()` removes the entry and
hooks. `start()` is idempotent and can recover an exited helper. Teardown closes
only the owned helper's lifetime socket, never signals reusable PIDs.

## Consent, privacy and idle cost

The bridge hooks native frame `share`/`render` and session `bufferSize`. Only
exports of its authenticated owned helper requested by same-user installed XDPH
are dynamic. Credentials, executable device/inode, helper PID/app ID, weak frame
lifetimes and instance-scoped IDs prevent title spoofing and pointer reuse.
XDPH remains the consent boundary; this does not isolate a compromised XDPH.

Monitor/workspace requests use privately owned native sessions/frames, never
mutate ordinary managed sessions, and retire after delivery. Native buffers,
fences, permissions and PipeWire transport remain compositor/portal-owned.
Native privacy masks apply to scenes; selected-window and helper privacy and
lock state are rechecked before rendering and before publishing.

Invalidated in-flight content is replaced by a real black render before `Ready`,
using a cancellable one-shot Wayland task after native GPU ordering. This cannot
revoke frames already delivered to XDPH, PipeWire, or a receiver. Callback and
GPU-lifetime handling still require live acceptance tests.

Without capture requests there is no plugin mirroring loop, frame-request timer,
PipeWire producer, or readback. The helper commits one static SHM buffer and
blocks on FDs. Bookkeeping, hooks, ~3.5 MiB of helper pixels plus textures remain.
The optional indicator adds render checks and a one-shot cleanup deadline, not an
idle poll. Monitor/workspace capture currently adds per-request native session
and intermediate framebuffer work; performance has not been benchmarked.

## Required live acceptance

1. Share harmless A, retarget B/window/monitor/workspace, and verify unchanged
   application stream/PipeWire node, including browser, Discord and OBS.
2. Test source-sized renegotiation and fixed letterboxing across sizes, scales,
   rotations, outputs and workspace moves; cursor/popups and inactive workspaces.
3. Clear/close/hide/disconnect/private/unprivate; verify black **with configured
   text**, not frozen content, transparency, or fallback capture.
4. Lock/unlock and revoke permissions with queued frames; test SHM and DMA-BUF.
5. Enable the indicator; verify local geometry, motion, cleanup/expiry and
   fullscreen/direct-scanout transitions. Check its **absence** in all Dynamic
   Share and concurrent ordinary monitor/window/workspace recordings.
6. Concurrent Dynamic Share/ordinary consumers, pause/resume, helper exit,
   portal reconnect, config reload, plugin unload/reload with work in flight.
7. Measure idle CPU/wakeups, memory, frame delivery and direct-scanout recovery.

See `../../XDPH-DYNAMIC-SHARING.md` for the portal-only feasibility investigation.
