"""Build a separate plugin. --load loads only edge-navigation, never others."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent
STORE = (
    Path(os.getenv("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    / "hypr/edge-navigation"
)
COMMIT = "11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947"
VERSION = "0.1.2"


def output(*args):
    return subprocess.check_output(args, text=True, timeout=30).strip()


def run(*args):
    subprocess.run(args, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--load",
        action="store_true",
        help="load a new plugin; never implicitly replace an existing copy",
    )
    args = parser.parse_args()
    installed = json.loads(output("Hyprland", "--version-json"))
    if installed["commit"] != COMMIT:
        raise RuntimeError("Review/rebuild for this Hyprland version first.")
    if args.load:
        running = json.loads(output("hyprctl", "-j", "version"))
        if running["abiHash"] != installed["abiHash"]:
            raise RuntimeError("Installed/running ABI mismatch.")
        if any(
            p["name"] == "edge-navigation"
            for p in json.loads(output("hyprctl", "-j", "plugin", "list"))
        ):
            raise RuntimeError(
                "edge-navigation is already loaded; refusing an implicit replacement."
            )
        if output("hyprctl", "repl", "return hl.get_current_submap()").strip("'\"") in (
            "scrolloverview",
            "hyprexpo",
        ):
            raise RuntimeError("Close the overview before loading.")
    with tempfile.TemporaryDirectory(
        prefix="edge-navigation-build-", dir="/tmp"
    ) as directory:
        run(
            "cmake",
            "-S",
            str(ROOT),
            "-B",
            directory,
            "-G",
            "Ninja",
            "-DCMAKE_BUILD_TYPE=Debug",
        )
        run("cmake", "--build", directory, "-j2")
        source = Path(directory) / "edge-navigation.so"
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        destination = (
            STORE / f"{VERSION}-{digest[:12]}-{time.time_ns()}" / "edge-navigation.so"
        )
        destination.parent.mkdir(parents=True)
        shutil.copy2(source, destination)
    record = {
        "library": str(destination),
        "sha256": digest,
        "version": VERSION,
        "hyprland": COMMIT,
        "abi_hash": installed["abiHash"],
    }
    (STORE / "build.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"Built {destination}", flush=True)
    if not args.load:
        return
    prior_errors = set(json.loads(output("hyprctl", "-j", "configerrors"))) - {""}
    try:
        output("hyprctl", "plugin", "load", str(destination))
        plugins = json.loads(output("hyprctl", "-j", "plugin", "list"))
        if not any(
            p["name"] == "edge-navigation" and p["version"] == VERSION for p in plugins
        ):
            raise RuntimeError("New plugin did not load.")
        output("hyprctl", "reload", "config-only")
        errors = set(json.loads(output("hyprctl", "-j", "configerrors"))) - {""}
        if errors - prior_errors:
            raise RuntimeError("New config errors: " + "; ".join(errors - prior_errors))
    except Exception:
        # Only this new plugin may be unloaded. Overview and sharing stay untouched.
        output("hyprctl", "plugin", "unload", str(destination))
        output("hyprctl", "reload", "config-only")
        raise
    print(
        "Loaded edge-navigation. Review/update hyprland/plugins.lua for future login loading."
    )


if __name__ == "__main__":
    main()
