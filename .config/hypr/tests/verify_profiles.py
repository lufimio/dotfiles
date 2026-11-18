"""Verify both shell profiles with the installed Hyprland, without live edits.

Only --verify-config is used: no compositor/session/shell is started.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "hyprland.lua").read_text()
assert source.count('local shell = "dms"') == 1
with tempfile.TemporaryDirectory(prefix="hypr-profiles-", dir="/tmp/opencode") as directory:
    for shell in ("dms", "noctalia"):
        # Do not call this noctalia.lua: require("noctalia") would load the
        # profile config itself recursively when the optional theme is absent.
        config = Path(directory) / ("profile-" + shell + ".lua")
        # Hyprland normally seeds package.path from the config directory.
        path = (str(ROOT / "?.lua") + ";" + str(ROOT / "?" / "init.lua") + ";").replace("\\", "\\\\").replace('"', '\\"')
        config.write_text('package.path = "' + path + '" .. package.path\n'
                          + source.replace('local shell = "dms"', 'local shell = "' + shell + '"', 1))
        result = subprocess.run(["Hyprland", "--verify-config", "-c", str(config)], text=True,
                                capture_output=True, timeout=30, cwd=ROOT)
        if result.returncode or "config ok" not in result.stdout:
            raise SystemExit(shell + " verification failed:\n" + result.stdout + result.stderr)
        print(shell + ": config ok")
