#!/usr/bin/env python3
"""On-demand Dynamic Share picker/CLI. Never polls, captures, or changes focus."""
import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

DEFAULT_MENU_COMMAND = "rofi -dmenu -i -p 'Dynamic Share'"


def lua_string(value):
    # Lua decimal byte escapes are unambiguous, including quotes/newlines/UTF-8.
    return '"' + "".join(f"\\{byte:03d}" for byte in str(value).encode("utf-8")) + '"'


def ipc(code):
    result = subprocess.run(["hyprctl", "repl", code], capture_output=True, text=True, timeout=10)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "Hyprland IPC failed")
    return result.stdout.strip()


def sources():
    response = ipc('local p = hl.plugin.dynamic_share; assert(p, "Dynamic Share is not loaded"); print(p.sources_json())')
    try:
        catalog = json.loads(response)
    except (ValueError, TypeError) as error:
        raise RuntimeError(f"Cannot read Dynamic Share sources: {response}") from error
    if not isinstance(catalog.get("instance"), str):
        raise RuntimeError("Dynamic Share returned no selector instance")
    return catalog


def clean(value):
    return " ".join("".join(" " if ord(char) < 32 or ord(char) == 127 else char for char in str(value)).split())


def choices(catalog):
    entries = []
    for window in catalog.get("windows", []):
        marker = " [private: video blocked]" if window.get("private") else ""
        entries.append((f"Window: {clean(window['title'])} — {clean(window['app_id'])}{marker}", "window", window["id"]))
    for workspace in catalog.get("workspaces", []):
        entries.append((f"Workspace: {clean(workspace['name'])} (windows only)", "workspace", workspace["id"]))
    for monitor in catalog.get("monitors", []):
        entries.append((f"Monitor: {clean(monitor['name'])} (whole output)", "monitor", monitor["id"]))
    entries.append(("Clear: Nothing is being shared", "clear", None))
    return entries


def action(kind, identity=None, instance=None):
    method = {"window": "select_window", "monitor": "select_monitor", "workspace": "select_workspace",
              "focused-window": "select_focused", "focused-monitor": "select_monitor",
              "focused-workspace": "select_workspace", "clear": "clear"}[kind]
    arguments = []
    if identity is not None:
        arguments.append(str(identity) if isinstance(identity, int) else lua_string(identity))
    if instance is not None and (identity is not None or kind == "clear"):
        arguments.append(lua_string(instance))
    response = ipc(f"return hl.plugin.dynamic_share.{method}({', '.join(arguments)})")
    if not response.startswith("true"):
        raise RuntimeError(response or "Source selection failed")
    return response


def identity(source):
    value = source["id"]
    if not isinstance(value, int) or isinstance(value, bool) or not 0 < value <= (2**63 - 1):
        raise RuntimeError("Source catalog contains an invalid identity")
    return value


def pick_dmenu(catalog, command):
    entries = choices(catalog)
    try:
        argv = shlex.split(command)
    except ValueError as error:
        raise RuntimeError(f"Invalid picker command: {error}") from error
    if not argv or not shutil.which(argv[0]):
        raise RuntimeError("The configured dmenu picker command is empty or its executable is missing")
    # Numeric row prefixes make even identical labels unambiguous in ordinary
    # dmenu mode. The command reads lines and returns one exact chosen line.
    labels = [f"{index + 1}. {entry[0]}" for index, entry in enumerate(entries)]
    menu = subprocess.run(
        argv, input="\n".join(labels) + "\n", capture_output=True, text=True,
    )
    if menu.returncode or not menu.stdout.strip():
        return None  # cancel preserves the current source
    try:
        index = labels.index(menu.stdout.strip())
    except ValueError as error:
        raise RuntimeError("Picker must return exactly one offered line (not an index or custom text)") from error
    _, kind, target = entries[index]
    if target is not None:
        identity({"id": target})
    return kind, target


def xdph_environment(catalog):
    """Supply display-only IDs to the stock picker, never real portal handles."""
    environment = dict(os.environ)
    # Do not inherit lists supplied to a different portal picker invocation.
    for key in tuple(environment):
        if key.startswith("XDPH_") and "SHARING_LIST" in key:
            environment.pop(key)
    mapping, windows, workspaces = {}, [], []
    for index, window in enumerate(catalog.get("windows", []), 1):
        target = identity(window)
        # The stock window format uses delimiters rather than byte lengths.
        app = clean(window["app_id"]).replace(">", "›")
        title = clean(window["title"]).replace(">", "›")
        if window.get("private"):
            title += " [private: video blocked]"
        windows.append(f"{index}[HC>]{app}[HT>]{title}[HE>]0[HA>]")
        mapping[("window", str(index))] = ("window", target)
    clear = len(windows) + 1
    windows.append(f"{clear}[HC>]Dynamic Share[HT>]Clear target: Nothing is being shared[HE>]0[HA>]")
    mapping[("window", str(clear))] = ("clear", None)
    for index, workspace in enumerate(catalog.get("workspaces", []), 1):
        name = clean(workspace["name"]) + " (windows only)"
        workspaces.append(f"{len(name.encode('utf-8'))}:{name}:{index};")
        mapping[("workspace-id", str(index))] = ("workspace", identity(workspace))
    for monitor in catalog.get("monitors", []):
        name = monitor["name"]
        if not isinstance(name, str) or not name or any(char in name for char in "\0\r\n"):
            raise RuntimeError("Source catalog contains an invalid monitor name")
        mapping[("screen", name)] = ("monitor", identity(monitor))
    environment["XDPH_WINDOW_SHARING_LIST"] = "".join(windows)
    environment["XDPH_WORKSPACE_SHARING_LIST_V2"] = "".join(workspaces)
    # The picker discovers its own real output names/descriptions over Wayland;
    # returned outputs must still be present in our instance-scoped snapshot.
    environment["XDPH_OUTPUT_SHARING_LIST"] = ""
    return environment, mapping


def pick_xdph(catalog):
    executable = shutil.which("hyprland-share-picker")
    if not executable:
        raise RuntimeError("hyprland-share-picker is missing; configure picker.backend = 'dmenu' instead")
    environment, mapping = xdph_environment(catalog)
    menu = subprocess.run([executable], env=environment, capture_output=True, text=True)
    if menu.returncode:
        raise RuntimeError(menu.stderr.strip() or "The stock XDPH picker failed")
    if not menu.stdout.strip():
        return None  # native Cancel/close is successful with no selection output
    lines = [line for line in menu.stdout.splitlines() if line.startswith("[SELECTION]")]
    if len(lines) != 1:
        raise RuntimeError("The stock picker returned an invalid or ambiguous selection")
    match = re.fullmatch(r"\[SELECTION\]r?/(window|workspace-id|screen|region):(.+)", lines[0])
    if not match:
        raise RuntimeError("The stock picker returned an invalid selection")
    if match[1] == "region":
        raise RuntimeError("Region targets are not supported; choose a window, workspace, or monitor")
    try:
        return mapping[(match[1], match[2])]
    except KeyError as error:
        raise RuntimeError("The chosen source was not in this picker snapshot; reopen the picker") from error


def pick(backend="xdph", command=DEFAULT_MENU_COMMAND):
    catalog = sources()  # snapshot BEFORE opening a focus-taking picker
    if backend == "xdph":
        selected = pick_xdph(catalog)
    elif backend == "dmenu":
        selected = pick_dmenu(catalog, command)
    else:
        raise RuntimeError("picker backend must be 'xdph' or 'dmenu'")
    if selected is None:
        return None
    kind, target = selected
    return action(kind, target, catalog["instance"])


def positive(value):
    parsed = int(value)
    if parsed <= 0 or parsed > (2**63 - 1):
        raise argparse.ArgumentTypeError("ID must be a positive signed 64-bit integer")
    return parsed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    pick_command = commands.add_parser("pick")
    pick_command.add_argument("--backend", choices=("xdph", "dmenu"), default="xdph")
    pick_command.add_argument("--command", dest="menu_command", default=DEFAULT_MENU_COMMAND, help="dmenu-compatible command; no implicit shell evaluation")
    for command in ("list", "status", "clear", "focused-window", "focused-monitor", "focused-workspace"):
        commands.add_parser(command)
    for command in ("window", "workspace"):
        commands.add_parser(command).add_argument("identity", type=positive)
    commands.add_parser("monitor").add_argument("identity", help="connector name, e.g. eDP-1")
    args = parser.parse_args(argv)
    try:
        if args.command == "pick":
            response = pick(args.backend, args.menu_command)
        elif args.command == "list":
            response = json.dumps(sources(), ensure_ascii=False, indent=2)
        elif args.command == "status":
            response = ipc("for k, v in pairs(hl.plugin.dynamic_share.status()) do print(k, v) end")
        else:
            response = action(args.command, getattr(args, "identity", None))
        if response:
            print(response)
        return 0
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"Dynamic Share: {error}", file=sys.stderr)
        if args.command == "pick":
            try:
                ipc(f"hl.notification.create({{text = {lua_string('Dynamic Share: ' + str(error))}, timeout = 5000}})")
            except (RuntimeError, OSError, subprocess.SubprocessError):
                pass  # IPC failure must not mask the original selector error.
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
