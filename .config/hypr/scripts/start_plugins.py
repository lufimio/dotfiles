"""Load reviewed, missing plugins at login. Never replace a running library."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

COMMIT = "11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947"


def output(*arguments):
    return subprocess.check_output(arguments, text=True, timeout=30).strip()


def loaded_plugins():
    return {plugin["name"]: plugin for plugin in json.loads(output("hyprctl", "-j", "plugin", "list"))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin", nargs=4, action="append", required=True,
                        metavar=("NAME", "VERSION", "SHA256", "LIBRARY"))
    arguments = parser.parse_args()
    if json.loads(output("hyprctl", "-j", "version"))["commit"] != COMMIT:
        raise RuntimeError("Hyprland changed; rebuild/review the required plugins first.")
    changed = False
    failures = []
    for name, version, digest, filename in arguments.plugin:
        try:
            current = loaded_plugins().get(name)
            if current:
                if current["version"] != version:
                    raise RuntimeError(f"{name}: {current['version']} is already loaded; expected {version}. Not replacing it.")
                continue
            library = Path(filename)
            if not library.is_absolute() or not library.is_file():
                raise RuntimeError(f"{name}: missing library {library}")
            if hashlib.sha256(library.read_bytes()).hexdigest() != digest:
                raise RuntimeError(f"{name}: library checksum changed; refusing to load it.")
            if name == "dynamic-share" and not library.with_name("dynamic-share-anchor").is_file():
                raise RuntimeError("dynamic-share: the companion helper is missing.")
            # Each library also validates its exact runtime ABI before initializing.
            output("hyprctl", "plugin", "load", str(library))
            current = loaded_plugins().get(name)
            if not current or current["version"] != version:
                raise RuntimeError(f"{name}: did not load as {version}")
            changed = True
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            failures.append(str(error))
    if changed:
        output("hyprctl", "reload", "config-only")
    if failures:
        message = "\n".join(failures)
        subprocess.run(["notify-send", "Hyprland plugins", message], check=False)
        raise RuntimeError(message)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
