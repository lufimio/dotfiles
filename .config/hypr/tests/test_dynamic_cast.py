"""Offline tests; optional D-Bus test runs ONLY on an isolated session bus.

python3 tests/test_dynamic_cast.py
dbus-run-session -- python3 tests/test_dynamic_cast.py --dbus
"""
import asyncio
import importlib.util
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("dynamic_cast", Path(__file__).resolve().parents[1] / "scripts/dynamic_cast.py")
cast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cast)


class PickerTests(unittest.TestCase):
    def test_snapshot_ids_are_not_compositor_workspace_ids(self):
        self.assertEqual(cast.workspace_tracker_id("1:1:91;12:dynamic-cast:407;"), "407")

    def test_utf8_lengths(self):
        self.assertEqual(cast.workspace_tracker_id("4:café:1;12:dynamic-cast:9;".replace("4:café", "5:café")), "9")

    def test_missing_and_invalid_snapshots(self):
        self.assertIsNone(cast.workspace_tracker_id("1:1:1;"))
        for value in ("bad", "99:x:1;", "12:dynamic-cast:x;", "12:dynamic-cast:1"):
            with self.assertRaises(ValueError):
                cast.workspace_tracker_id(value)

    def test_mirror_requires_consent_and_disables_only_its_restore_token(self):
        selected, output = cast.mirror_selection("[SELECTION]r/workspace-id:407\n", "407")
        self.assertTrue(selected)
        self.assertEqual(output, "[SELECTION]/workspace-id:407\n")

    def test_named_target(self):
        self.assertTrue(cast.mirror_selection("[SELECTION]/workspace:dynamic-cast", "407")[0])

    def test_other_sources_and_cancellation_pass_through(self):
        for output in ("", "cancelled", "[SELECTION]r/window:407", "[SELECTION]r/workspace-id:408", "[SELECTION]r/screen:eDP-1"):
            self.assertEqual(cast.mirror_selection(output, "407"), (False, output))


async def monitor_test():
    from gi.repository import Gio, GLib
    # This test is invoked under dbus-run-session: never monitor the user's bus.
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    connection.call_sync(
        "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
        GLib.Variant("(su)", (cast.BACKEND, 0)), None, Gio.DBusCallFlags.NONE, 3000, None,
    )
    loop = asyncio.get_running_loop()
    started, closed = loop.create_future(), loop.create_future()
    monitor = cast.PortalMonitor(loop, started.set_result, closed.set_result, lambda: None)
    # An unknown object still emits a real method call; no screen share is created.
    for interface, method, signature, values in (
        ("org.freedesktop.impl.portal.ScreenCast", "Start", "oossa{sv}", ["/request/test", "/session/test", "test", "", "0"]),
        ("org.freedesktop.impl.portal.Session", "Close", "", []),
    ):
        path = "/session/test" if method == "Close" else "/org/freedesktop/portal/desktop"
        child = await asyncio.create_subprocess_exec(
            "busctl", "--user", "--auto-start=no", "--expect-reply=no", "call", cast.BACKEND,
            path, interface, method, *([signature, *values] if signature else []),
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
        )
        assert await child.wait() == 0
    assert await asyncio.wait_for(started, 3) == "/session/test"
    assert await asyncio.wait_for(closed, 3) == "/session/test"
    monitor.connection.close_sync(None)
    print("Isolated D-Bus portal Start/Close monitor test passed")


if __name__ == "__main__":
    if "--dbus" in sys.argv:
        sys.argv.remove("--dbus")
        if not __import__("os").environ.get("DBUS_SESSION_BUS_ADDRESS", "").startswith("unix:"):
            raise SystemExit("Use dbus-run-session for this test")
        asyncio.run(monitor_test())
    unittest.main()
