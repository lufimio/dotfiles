"""Offline tests only: never start/stop a real shell, service, player, or device.

python3 tests/test_shell.py
"""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("start_shell", ROOT / "scripts/start_shell.py")
shell = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shell)


class CrashIndependentControls(unittest.TestCase):
    def test_both_profiles_work_with_dead_shell_ipc(self):
        with tempfile.TemporaryDirectory(prefix="hypr-controls-", dir="/tmp/opencode") as directory:
            directory = Path(directory)
            log = directory / "commands.jsonl"
            # Fake every external binary. No real audio/backlight/player changes.
            for binary in ("wpctl", "brightnessctl", "playerctl", "dms", "noctalia", "qs"):
                executable = directory / binary
                executable.write_text(
                    "#!/usr/bin/python3\n"
                    "import json, os, pathlib, sys\n"
                    "name = pathlib.Path(sys.argv[0]).name\n"
                    "with open(os.environ['CONTROL_LOG'], 'a') as log:\n"
                    "    log.write(json.dumps([name, *sys.argv[1:]]) + '\\n')\n"
                    "sys.exit(99 if name in ('dms', 'noctalia', 'qs') else 0)\n"
                )
                executable.chmod(0o755)
            profiles = {}
            for name in ("dms", "noctalia"):
                result = subprocess.run(
                    ["lua", "tests/config.lua", name], cwd=ROOT, check=True, capture_output=True, text=True,
                    env={**os.environ, "PRINT_CONTROLS": "1"},
                )
                controls = {}
                for line in result.stdout.splitlines():
                    if line.startswith("CONTROL\t"):
                        _, key, command = line.split("\t", 2)
                        controls[key] = command
                self.assertEqual(len(controls), 15)
                profiles[name] = controls
                for key, command in controls.items():
                    with self.subTest(profile=name, key=key):
                        log.write_text("")
                        subprocess.run(command, shell=True, check=True, cwd=directory, timeout=3,
                                       env={**os.environ, "PATH": str(directory), "CONTROL_LOG": str(log)})
                        calls = [json.loads(line) for line in log.read_text().splitlines()]
                        self.assertEqual(calls, [shlex.split(command)], "exactly one direct action, no shell IPC")
                        self.assertIn(calls[0][0], ("wpctl", "brightnessctl", "playerctl"))
            self.assertEqual(profiles["dms"], profiles["noctalia"])


class ShellStartup(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.units = {shell.DMS_UNIT: "loaded", shell.NOCTALIA_UNIT: "not-found"}
        self.states = {shell.DMS_UNIT: "active"}
        self.failure = None
        self.env = patch.dict(os.environ, {
            "HYPRLAND_INSTANCE_SIGNATURE": "offline-test", "WAYLAND_DISPLAY": "wayland-test",
            "XDG_RUNTIME_DIR": "/tmp/opencode", "XDG_CURRENT_DESKTOP": "Hyprland",
        }, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.which = patch.object(shell.shutil, "which", side_effect=lambda binary: "/usr/bin/" + binary)
        self.which.start()
        self.addCleanup(self.which.stop)

        def run(arguments, **kwargs):
            self.calls.append(arguments)
            if self.failure and self.failure(arguments):
                raise subprocess.CalledProcessError(1, arguments, stderr="simulated failure")
            output = ""
            if "--property=LoadState" in arguments:
                output = self.units.get(arguments[-1], "not-found")
            if "--property=ActiveState" in arguments:
                output = self.states.get(arguments[-1], "inactive")
            return subprocess.CompletedProcess(arguments, 0, output + "\n", "")

        self.run = patch.object(shell.subprocess, "run", side_effect=run)
        self.run.start()
        self.addCleanup(self.run.stop)

    def test_noctalia_stops_dms_then_starts_supervised_session_service(self):
        shell.start("noctalia")
        stop = ["systemctl", "--user", "stop", shell.DMS_UNIT]
        self.assertIn(stop, self.calls)
        start = next(call for call in self.calls if call[0] == "systemd-run")
        self.assertIn("--property=Restart=on-failure", start)
        self.assertIn("--property=PartOf=graphical-session.target", start)
        self.assertEqual(start[-1], "/usr/bin/noctalia")
        imported = next(i for i, call in enumerate(self.calls) if call[0] == "dbus-update-activation-environment")
        self.assertLess(imported, self.calls.index(stop))
        self.assertLess(self.calls.index(stop), self.calls.index(start))
        self.assertFalse(any("enable" in call or "disable" in call for call in self.calls))

    def test_dms_stops_only_our_managed_noctalia_unit(self):
        self.units[shell.NOCTALIA_UNIT] = "loaded"
        shell.start("dms")
        self.assertIn(["systemctl", "--user", "stop", shell.NOCTALIA_UNIT], self.calls)
        self.assertEqual(self.calls[-1], ["systemctl", "--user", "start", shell.DMS_UNIT])
        self.assertFalse(any(call[0] in ("pkill", "kill", "systemd-run") for call in self.calls))

    def test_missing_binary_does_not_stop_current_shell(self):
        with patch.object(shell.shutil, "which", side_effect=lambda binary: None if binary == "noctalia" else binary):
            with self.assertRaises(RuntimeError):
                shell.start("noctalia")
        self.assertEqual(self.calls, [])

    def test_missing_dms_unit_does_not_stop_noctalia(self):
        self.units[shell.DMS_UNIT] = "not-found"
        with self.assertRaises(RuntimeError):
            shell.start("dms")
        self.assertFalse(any("stop" in call for call in self.calls))

    def test_new_shell_start_failure_restores_previous_service(self):
        self.failure = lambda call: call[0] == "systemd-run"
        with self.assertRaises(subprocess.CalledProcessError):
            shell.start("noctalia")
        self.assertEqual(self.calls[-1], ["systemctl", "--user", "start", shell.DMS_UNIT])

    def test_invalid_profile_or_non_hyprland_session_is_rejected(self):
        with self.assertRaises(ValueError):
            shell.start("unknown")
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(RuntimeError):
                shell.start("noctalia")
        self.assertEqual(self.calls, [])


class NoctaliaTemplateHooks(unittest.TestCase):
    def test_native_hooks_do_not_bypass_or_delete_the_selector(self):
        templates = Path("/usr/share/noctalia/assets/templates/hyprland")
        if not (templates / "apply.sh").is_file():
            self.skipTest("Noctalia native template hooks are not installed")
        with tempfile.TemporaryDirectory(prefix="hypr-noctalia-hooks-", dir="/tmp/opencode") as directory:
            directory = Path(directory)
            config = directory / "hypr"
            config.mkdir()
            main = config / "hyprland.lua"
            source = (ROOT / "hyprland.lua").read_text()
            main.write_text(source)
            generated = config / "noctalia.lua"
            generated.write_text("return { apply_theme = function() end }\n")
            # No live compositor probe; force the built-in Lua-file detection.
            binaries = directory / "bin"
            binaries.mkdir()
            hyprctl = binaries / "hyprctl"
            hyprctl.write_text("#!/bin/sh\nexit 1\n")
            hyprctl.chmod(0o755)
            env = {**os.environ, "XDG_CONFIG_HOME": str(directory), "PATH": str(binaries) + ":/usr/bin"}
            subprocess.run(["bash", str(templates / "apply.sh"), "apply"], check=True, env=env, timeout=5)
            self.assertEqual(main.read_text(), source, "must not append a DMS-overriding theme call")
            subprocess.run(["bash", str(templates / "undo.sh")], check=True, env=env, timeout=5)
            self.assertEqual(main.read_text(), source, "undo must not remove the conditional load")
            self.assertFalse(generated.exists())


if __name__ == "__main__":
    unittest.main()
