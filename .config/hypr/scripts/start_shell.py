#!/usr/bin/env python3
"""Select the shell at Hyprland LOGIN only, never while reloading a lock provider.

Uses the existing DMS service or a session-bound transient Noctalia service.
Does not enable/disable services, edit other shell settings, or affect niri startup.
"""
import argparse
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import sys

NOCTALIA_UNIT = "hyprland-noctalia.service"
DMS_UNIT = "dms.service"
SESSION_VARIABLES = ("DISPLAY", "XAUTHORITY", "WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP", "HYPRLAND_INSTANCE_SIGNATURE")


def run(arguments, *, check=True, timeout=25):
    return subprocess.run(arguments, check=check, text=True, capture_output=True, timeout=timeout)


def property_value(unit, name):
    result = run(["systemctl", "--user", "show", "--property=" + name, "--value", unit], check=False)
    return result.stdout.strip()


def loaded(unit):
    return property_value(unit, "LoadState") == "loaded"


def start(name):
    if name not in ("dms", "noctalia"):
        raise ValueError("unknown shell: " + name)
    if not all(os.environ.get(key) for key in ("HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR")):
        raise RuntimeError("shell selection requires a real Hyprland session")
    # Preflight before stopping the other shell. Never install missing packages.
    for binary in ("systemctl", "dbus-update-activation-environment", "dms" if name == "dms" else "noctalia"):
        if not shutil.which(binary):
            raise RuntimeError("missing required program: " + binary)
    if name == "noctalia" and not shutil.which("systemd-run"):
        raise RuntimeError("systemd-run is required to supervise Noctalia")
    run(["systemctl", "--user", "is-active", "--quiet", "graphical-session.target"])
    if name == "dms" and not loaded(DMS_UNIT):
        raise RuntimeError("the existing dms.service is missing")

    # Complete the environment import BEFORE starting either service.
    variables = [key for key in SESSION_VARIABLES if os.environ.get(key)]
    run(["dbus-update-activation-environment", "--systemd", *variables])
    other = NOCTALIA_UNIT if name == "dms" else DMS_UNIT
    previous = None
    if loaded(other):
        if property_value(other, "ActiveState") in ("active", "activating", "reloading"):
            previous = other
        run(["systemctl", "--user", "stop", other])
    try:
        if name == "dms":
            run(["systemctl", "--user", "start", DMS_UNIT], timeout=100)
        elif loaded(NOCTALIA_UNIT):
            run(["systemctl", "--user", "start", NOCTALIA_UNIT])
        else:
            run([
                "systemd-run", "--user", "--unit=" + NOCTALIA_UNIT, "--collect", "--service-type=exec",
                "--property=PartOf=graphical-session.target", "--property=After=graphical-session.target",
                "--property=Restart=on-failure", "--property=RestartSec=1",
                shutil.which("noctalia"),
            ])
    except (OSError, subprocess.SubprocessError):
        if previous:
            # Best-effort recovery if the new shell cannot even start.
            try:
                run(["systemctl", "--user", "start", previous], check=False, timeout=100)
            except (OSError, subprocess.SubprocessError):
                pass
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("shell", choices=("dms", "noctalia"))
    args = parser.parse_args()
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise RuntimeError("XDG_RUNTIME_DIR is not set")
    with (Path(runtime) / "hyprland-shell-start.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        start(args.shell)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print("[hyprland-shell] " + str(error), file=sys.stderr)
        if getattr(error, "stderr", None):
            print(error.stderr, file=sys.stderr, end="")
        raise SystemExit(1)
