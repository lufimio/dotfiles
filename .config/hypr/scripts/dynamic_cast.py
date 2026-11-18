#!/usr/bin/env python3
"""On-demand, isolated-window mirror for Hyprland 0.57 / XDPH 1.5.

Only the dedicated workspace is offered as the stable dynamic capture target.
Never substitute output/region capture. See ../PORTING.md for limitations.
"""

import argparse
import asyncio
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys

WORKSPACE = "dynamic-cast"
TITLE = "Hyprland Dynamic Cast"
ROOT = Path(__file__).resolve().parent.parent
BACKEND = "org.freedesktop.impl.portal.desktop.hyprland"


def runtime_dir():
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not signature or not os.environ.get("XDG_RUNTIME_DIR"):
        raise RuntimeError("dynamic casting requires a Hyprland session")
    instance = hashlib.sha256(signature.encode()).hexdigest()[:12]
    directory = Path(os.environ["XDG_RUNTIME_DIR"]) / ("hypr-dynamic-cast-" + instance)
    directory.mkdir(mode=0o700, exist_ok=True)
    return directory


def workspace_tracker_id(encoded):
    """XDPH 1.5 V2 list: byte-length:name:tracker-id; (not Hyprland IDs)."""
    data = encoded.encode("utf-8")
    while data:
        size, separator, rest = data.partition(b":")
        if not separator or not size.isdigit():
            raise ValueError("unrecognized XDPH workspace list")
        length = int(size)
        if len(rest) <= length or rest[length:length + 1] != b":":
            raise ValueError("invalid workspace name length")
        name = rest[:length].decode("utf-8")
        identifier, separator, data = rest[length + 1:].partition(b";")
        if not separator or not identifier.isdigit():
            raise ValueError("invalid workspace tracker ID")
        if name == WORKSPACE:
            return identifier.decode("ascii")
    return None


def mirror_selection(output, tracker_id):
    match = re.search(r"\[SELECTION\]([^/\r\n]*)/([^\r\n]+)", output)
    if not match:
        return False, output
    source = match[2]
    is_mirror = source == "workspace:" + WORKSPACE or source == "workspace-id:" + tracker_id
    if not is_mirror:
        return False, output
    # A restored share skips the picker and therefore cannot start this helper.
    # Disable restore tokens for this target only, not for ordinary shares.
    flags = match[1].replace("r", "")
    return True, output[:match.start(1)] + flags + output[match.end(1):]


def request(directory, message, timeout=3):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(timeout)
        connection.connect(str(directory / "control.sock"))
        connection.sendall(json.dumps(message).encode() + b"\n")
        with connection.makefile("rb") as stream:
            reply = json.loads(stream.readline(4096))
        if not reply.get("ok"):
            raise RuntimeError(reply.get("error", "mirror request failed"))
        return reply


def ensure_worker(directory):
    try:
        request(directory, {"op": "ping"})
        return
    except (OSError, ValueError, RuntimeError):
        pass
    log_fd = os.open(directory / "mirror.log", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(log_fd, "ab") as log:
        child = subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "worker"],
            stdout=subprocess.PIPE, stderr=log, start_new_session=True,
        )
        # A startup pipe, not polling: READY is sent only after the view connects.
        import selectors
        with selectors.DefaultSelector() as selector:
            selector.register(child.stdout, selectors.EVENT_READ)
            if not selector.select(12) or child.stdout.readline().strip() != b"READY":
                child.terminate()
                raise RuntimeError("mirror startup failed; see " + str(directory / "mirror.log"))
        child.stdout.close()


def picker(arguments):
    directory = runtime_dir()
    with (directory / "picker.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        available = False
        tracker_id = None
        try:
            tracker_id = workspace_tracker_id(os.environ.get("XDPH_WORKSPACE_SHARING_LIST_V2", ""))
            if not tracker_id:
                raise RuntimeError("persistent dynamic-cast workspace is missing from XDPH's snapshot")
            ensure_worker(directory)
            request(directory, {"op": "prepare"})
            available = True
        except (OSError, ValueError, RuntimeError) as error:
            print("[dynamic-cast] " + str(error), file=sys.stderr)

        # Do not replace or auto-confirm the consent dialog.
        result = subprocess.run(["hyprland-share-picker", *arguments], capture_output=True, text=True)
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
        selected, output = mirror_selection(result.stdout, tracker_id or "")
        try:
            if available and selected and result.returncode == 0:
                request(directory, {"op": "arm"})
            else:
                request(directory, {"op": "stop"})
                if selected:
                    # No working view: refuse this target instead of sharing stale pixels.
                    return 1
        except (OSError, ValueError, RuntimeError) as error:
            if selected:
                print("[dynamic-cast] " + str(error), file=sys.stderr)
                return 1
        print(output, end="", flush=True)
        return result.returncode


class PortalMonitor:
    """Watch actual portal session closure, NOT Hyprland's 500ms frame heartbeat.

    No portal traffic is logged. The monitor sees only Start/Close and portal
    owner changes. If session-bus monitoring is denied, startup fails closed.
    """

    def __init__(self, loop, on_start, on_close, on_disconnect):
        from gi.repository import Gio, GLib
        self.connection = Gio.DBusConnection.new_for_address_sync(
            Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None),
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None, None,
        )
        self.connection.set_exit_on_close(False)

        def schedule(callback, *args):
            if not loop.is_closed():
                loop.call_soon_threadsafe(callback, *args)

        def received(connection, message, incoming, user_data):
            if not incoming:
                return message
            interface, member, path = message.get_interface(), message.get_member(), message.get_path()
            body = message.get_body()
            values = body.unpack() if body else ()
            if interface == "org.freedesktop.impl.portal.ScreenCast" and member == "Start" and len(values) >= 2:
                schedule(on_start, values[1])
            elif interface in ("org.freedesktop.impl.portal.Session", "org.freedesktop.portal.Session") and member in ("Close", "Closed"):
                schedule(on_close, path)
            elif interface == "org.freedesktop.DBus" and member == "NameOwnerChanged" and len(values) == 3 and values[1]:
                schedule(on_disconnect)
            # A monitor must never auto-reply UnknownMethod to copied calls.
            # Returning None consumes them before GIO's object dispatcher.
            return None if message.get_message_type() == Gio.DBusMessageType.METHOD_CALL else message

        self.connection.add_filter(received, None)
        self.connection.connect("closed", lambda *_: schedule(on_disconnect))
        rules = [
            "type='method_call',destination='" + BACKEND + "',interface='org.freedesktop.impl.portal.ScreenCast',member='Start'",
            "type='method_call',destination='" + BACKEND + "',interface='org.freedesktop.impl.portal.Session',member='Close'",
            "type='method_call',interface='org.freedesktop.portal.Session',member='Close'",
            "type='signal',interface='org.freedesktop.portal.Session',member='Closed'",
        ]
        for name in (BACKEND, "org.freedesktop.portal.Desktop"):
            rules.append("type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='" + name + "'")
        self.connection.call_sync(
            "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus.Monitoring", "BecomeMonitor",
            GLib.Variant("(asu)", (rules, 0)), None, Gio.DBusCallFlags.NONE, 3000, None,
        )


async def worker():
    directory = runtime_dir()
    path = directory / "control.sock"
    path.unlink(missing_ok=True)
    stopped, view_ready = asyncio.Event(), asyncio.Event()
    viewer = None
    target = ""
    private = set()
    session = None
    armed = False
    deadline = None
    loop = asyncio.get_running_loop()

    def portal_start(identifier):
        nonlocal session, armed, deadline
        if armed:
            session, armed = identifier, False
            if deadline:
                deadline.cancel()

    def portal_close(identifier):
        if identifier == session:
            stopped.set()

    # Establish lifecycle tracking before exposing the picker target.
    bus = PortalMonitor(loop, portal_start, portal_close, stopped.set)

    async def publish():
        if viewer:
            viewer.write(json.dumps({"address": "" if target in private else target}).encode() + b"\n")
            await viewer.drain()

    async def handle(reader, writer):
        nonlocal viewer, target, armed, deadline
        keep = False
        try:
            message = json.loads(await asyncio.wait_for(reader.readline(), 3))
            operation = message.get("op")
            if operation == "view":
                viewer, keep = writer, True
                await publish()
                view_ready.set()
                await reader.read()  # The view keeps its connection for source updates.
                stopped.set()
                return
            if operation == "stop":
                stopped.set()
            elif operation == "prepare":
                if armed:
                    raise RuntimeError("another mirror selection is still starting")
                if not session:
                    target = ""  # A new share starts blank until Super+Shift+R.
                    await publish()
            elif operation == "arm":
                if session:
                    raise RuntimeError("one dynamic mirror share at a time is supported")
                armed = True
                if deadline:
                    deadline.cancel()
                deadline = loop.call_later(30, stopped.set)
            elif operation in ("target", "privacy"):
                address = message.get("address", "")
                if not re.fullmatch(r"0x[0-9a-fA-F]+", address):
                    raise ValueError("invalid window address")
                if operation == "target":
                    if not session:
                        raise RuntimeError("select the dynamic-cast workspace in the share picker first")
                    target = address.lower()
                if message.get("private", False):
                    private.add(address.lower())
                else:
                    private.discard(address.lower())
                await publish()
            elif operation != "ping":
                raise ValueError("unknown operation")
            writer.write(b'{"ok":true}\n')
            await writer.drain()
        except (ValueError, RuntimeError, OSError, asyncio.TimeoutError) as error:
            writer.write(json.dumps({"ok": False, "error": str(error)}).encode() + b"\n")
            try:
                await writer.drain()
            except OSError:
                pass
        finally:
            if not keep:
                writer.close()

    server = await asyncio.start_unix_server(handle, str(path), limit=4096)
    os.chmod(path, 0o600)
    environment = {**os.environ, "HYPR_DYNAMIC_CAST_SOCKET": str(path), "QT_QPA_PLATFORM": "wayland"}
    view = await asyncio.create_subprocess_exec(
        "quickshell", "--no-duplicate", "--path", str(ROOT / "dynamic-cast/shell.qml"),
        env=environment, stdout=sys.stderr, stderr=sys.stderr,
    )
    async def watch_view():
        await view.wait()
        stopped.set()
    watcher = asyncio.create_task(watch_view())
    try:
        ready = asyncio.create_task(view_ready.wait())
        closed = asyncio.create_task(stopped.wait())
        await asyncio.wait({ready, closed}, timeout=8, return_when=asyncio.FIRST_COMPLETED)
        if not view_ready.is_set() or stopped.is_set():
            raise RuntimeError("mirror view did not become ready")
        print("READY", flush=True)
        await stopped.wait()
    finally:
        server.close()
        await server.wait_closed()
        bus.connection.close_sync(None)
        if deadline:
            deadline.cancel()
        if view.returncode is None:
            view.terminate()
            try:
                await asyncio.wait_for(view.wait(), 3)
            except asyncio.TimeoutError:
                view.kill()
                await view.wait()
        watcher.cancel()
        path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("picker", "worker", "target", "privacy", "stop"))
    parser.add_argument("arguments", nargs="*")
    parser.add_argument("--private", action="store_true")
    args, extra = parser.parse_known_args()
    if args.operation == "picker":
        return picker(args.arguments + extra)
    if args.operation == "worker":
        asyncio.run(worker())
        return 0
    message = {"op": args.operation}
    if args.operation in ("target", "privacy"):
        if len(args.arguments) != 1:
            parser.error("a window address is required")
        message.update(address=args.arguments[0], private=args.private)
    try:
        request(runtime_dir(), message)
    except (OSError, ValueError, RuntimeError) as error:
        if args.operation == "privacy":
            return 0  # Native capture privacy works even without a running mirror.
        print("[dynamic-cast] " + str(error), file=sys.stderr)
        if args.operation == "target":
            subprocess.run(["notify-send", "Dynamic Cast", "Select the dynamic-cast workspace in the sharing picker first."])
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print("[dynamic-cast] " + str(error), file=sys.stderr)
        raise SystemExit(1)
