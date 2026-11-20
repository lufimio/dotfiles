"""Rebuild the pinned local input patch; switch live only with explicit --load.

Run with python3 plugins/scrolloverview/build.py [--install | --load].
--install replaces only hyprpm's scrolloverview.so, atomically, keeping a backup.
--load explicitly opts into a live switch after building; it can crash Hyprland.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shlex
import shutil
import subprocess
import tempfile
import time
import tomllib

REVISION = "3eb62e3e0093d54cbdcf4f58c831b5b53b3b1ff2"
HYPRLAND = "11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947"
VERSION = "3eb62e3e0093-local-input-v4"
PATCH = Path(__file__).with_name("input-v3.patch")
INSERT_PATCH = Path(__file__).with_name("workspace-insert.patch")
INSERT_SOURCE = Path(__file__).with_name("workspace-insert.inc")
STORE = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "hypr/scrolloverview"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def output(*args):
    return subprocess.check_output(args, text=True, timeout=30).strip()


def atomic_copy(source, destination):
    """Never truncate a .so that might still be mapped by Hyprland."""
    fd, temporary = tempfile.mkstemp(prefix=".scrolloverview-", dir=destination.parent)
    try:
        os.close(fd)
        shutil.copy2(source, temporary)
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)

def installation_hint(source, target):
    """Print, but never execute, privileged install commands."""
    pending = target.with_name(f".scrolloverview-local-{os.getpid()}.so")
    print("hyprpm's cache is not writable. To install persistently yourself:")
    print(f"sudo install -m 644 {shlex.quote(str(source))} {shlex.quote(str(pending))}")
    print(f"sudo mv {shlex.quote(str(pending))} {shlex.quote(str(target))}")
    print("This replaces the on-disk library atomically; it does not switch the running plugin.")


def hyprpm_target():
    # hyprpm 0.57 uses this system-cache directory, not XDG_CACHE_HOME.
    root = Path("/var/cache/hyprpm") / pwd.getpwuid(os.getuid()).pw_name
    repo = root / "hyprland-scroll-overview"
    state = tomllib.loads((repo / "state.toml").read_text())
    if state["repository"]["hash"] != REVISION:
        raise SystemExit("hyprpm's upstream revision changed; review/rebase input.patch before installing.")
    if state["scrolloverview"]["filename"] != "scrolloverview.so":
        raise SystemExit("Unexpected hyprpm library filename; refusing to replace it.")
    return repo / "scrolloverview.so"

def loaded_overviews():
    return [plugin for plugin in json.loads(output("hyprctl", "-j", "plugin", "list"))
            if plugin["name"] == "scrolloverview"]


def contains_version(library, version):
    try:
        return version.encode() + b"\0" in library.read_bytes()
    except OSError:
        return False


def find_loaded_path(plugin, previous, override=None):
    """Resolve paths from this session's mapped files, never guess an unload path."""
    if override:
        path = Path(override).expanduser()
        if not path.is_absolute() or not path.is_file():
            raise RuntimeError("--old-path must name an existing absolute library path.")
        return path
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    instances = json.loads(output("hyprctl", "-j", "instances"))
    matches = [instance for instance in instances if instance["instance"] == signature]
    if len(matches) != 1:
        raise RuntimeError("Cannot identify the current compositor; specify --old-path.")
    mapped = set()
    for line in Path(f"/proc/{int(matches[0]['pid'])}/maps").read_text().splitlines():
        fields = line.split(maxsplit=5)
        if len(fields) == 6:
            path = Path(fields[5].removesuffix(" (deleted)"))
            if "scrolloverview" in path.name and path.suffix == ".so":
                mapped.add(path)
    candidates = {path for path in mapped if contains_version(path, plugin["version"])}
    active_file = STORE / "active.json"
    active = json.loads(active_file.read_text()) if active_file.exists() else {}
    for record in (active, previous or {}):
        path = Path(record.get("library", ""))
        if path in candidates:
            return path
    if len(candidates) == 1:
        return candidates.pop()
    # An atomically replaced cache file can still be loaded at its old path.
    # --old-path handles this explicitly instead of unloading the wrong copy.
    raise RuntimeError("Cannot unambiguously identify the loaded library; pass --old-path /absolute/loaded/library.so.")


def record_active(library, version):
    (STORE / "active.json").write_text(json.dumps(
        {"library": str(library), "version": version}, indent=2) + "\n")


def load_built_plugin(library, previous=None, old_path=None, abi_hash=None):
    """Explicit live switch, with state verification and best-effort rollback."""
    running = json.loads(output("hyprctl", "-j", "version"))
    if running["commit"] != HYPRLAND or (abi_hash and running["abiHash"] != abi_hash):
        raise RuntimeError("Running Hyprland does not match the build ABI; restart/rebuild before loading.")
    submap = output("hyprctl", "repl", "return hl.get_current_submap()").strip("'\"")
    if submap in ("scrolloverview", "hyprexpo"):
        raise RuntimeError("Close the overview first; the new build is saved but was not loaded.")
    current = loaded_overviews()
    if len(current) > 1:
        raise RuntimeError("Multiple overview copies are loaded; resolve that before switching.")
    prior_errors = set(json.loads(output("hyprctl", "-j", "configerrors"))) - {""}
    old = current[0] if current else None
    old_library = find_loaded_path(old, previous, old_path) if old else None
    rollback = None
    if old:
        # Preserve a uniquely named, known-version rollback image before unload.
        source = old_library
        if not contains_version(source, old["version"]):
            source = next((path for path in sorted(STORE.glob("*.so"))
                           if contains_version(path, old["version"])), None)
        if source is None:
            raise RuntimeError("Cannot preserve the currently loaded version; refusing to unload it.")
        rollback = STORE / f"scrolloverview-rollback-{time.time_ns()}.so"
        shutil.copy2(source, rollback)
        response = output("hyprctl", "plugin", "unload", str(old_library))
        if loaded_overviews():
            raise RuntimeError(f"Old plugin did not unload ({response}); no new copy was loaded. Check --old-path.")
    try:
        response = output("hyprctl", "plugin", "load", str(library))
        current = loaded_overviews()
        if len(current) != 1 or current[0]["version"] != VERSION:
            raise RuntimeError(f"New plugin did not load as {VERSION}: {response}")
        output("hyprctl", "reload", "config-only")
        errors = set(json.loads(output("hyprctl", "-j", "configerrors"))) - {""}
        if errors - prior_errors:
            raise RuntimeError("New configuration errors: " + "; ".join(sorted(errors - prior_errors)))
        record_active(library, VERSION)
    except Exception as error:
        try:
            current = loaded_overviews()
            if current:
                if len(current) != 1 or current[0]["version"] != VERSION:
                    raise RuntimeError("An unexpected plugin is loaded; refusing to unload it for rollback.")
                output("hyprctl", "plugin", "unload", str(library))
                if loaded_overviews():
                    raise RuntimeError("Could not unload the failed new plugin.")
            if rollback:
                output("hyprctl", "plugin", "load", str(rollback))
                restored = loaded_overviews()
                if len(restored) != 1 or restored[0]["version"] != old["version"]:
                    raise RuntimeError("Previous plugin did not reload.")
                output("hyprctl", "reload", "config-only")
                record_active(rollback, old["version"])
                print(f"Switch failed; restored {old['version']} from {rollback}.")
        except Exception as rollback_error:
            raise RuntimeError(f"{error}\nAutomatic rollback failed: {rollback_error}\n"
                               f"Saved rollback library: {rollback}. A compositor crash cannot be recovered by this helper.") from error
        raise RuntimeError(str(error)) from error
    print(f"Loaded {VERSION} from {library}. This live switch does not install it persistently.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--install", action="store_true", help="install for the next plugin load, without live activation")
    action.add_argument("--restore", action="store_true", help="restore the last backed-up hyprpm binary, without live activation")
    action.add_argument("--path", action="store_true", help="print the latest built library path, without building or installing")
    action.add_argument("--load", action="store_true", help="build, then switch the running plugin (save work first; may crash Hyprland)")
    parser.add_argument("--old-path", help="explicit currently loaded library path if --load cannot detect it")
    args = parser.parse_args()
    if args.old_path and not args.load:
        parser.error("--old-path requires --load")
    if args.path:
        record = json.loads((STORE / "build.json").read_text())
        library = Path(record["library"])
        if not library.is_file():
            raise SystemExit("The last built library is missing; rebuild it first.")
        if hashlib.sha256(library.read_bytes()).hexdigest() != record["sha256"]:
            raise SystemExit("The last built library's checksum changed; rebuild it first.")
        print(library)
        return
    STORE.mkdir(parents=True, exist_ok=True)
    previous_file = STORE / "build.json"
    previous = json.loads(previous_file.read_text()) if previous_file.exists() else None
    if args.load:
        print("WARNING: --load will replace the running overview after building. Save work and close the overview.", flush=True)

    if args.restore:
        target = hyprpm_target()
        record = json.loads((STORE / "installation.json").read_text())
        backup = Path(record["backup"])
        if str(target) != record["target"] or not backup.is_relative_to(STORE):
            raise SystemExit("Backup metadata does not match this installation.")
        if hashlib.sha256(backup.read_bytes()).hexdigest() != record["backup_sha256"]:
            raise SystemExit("Backup checksum mismatch; refusing to restore.")
        if not os.access(target.parent, os.W_OK):
            installation_hint(backup, target)
            raise SystemExit(1)
        atomic_copy(backup, target)
        print(f"Restored {target}; restart Hyprland to activate the restored binary.")
        return

    installed = json.loads(output("Hyprland", "--version-json"))
    if installed["commit"] != HYPRLAND:
        raise SystemExit("This patch was tested with Hyprland 0.57.2 only; review it for the installed version first.")
    # Verify pkg-config actually points to headers for the exact installed commit.
    flags = output("pkg-config", "--cflags", "hyprland")
    header_hashes = set()
    for include in re.findall(r"(?:^|\s)-I(\S+)", flags):
        for header in (Path(include) / "hyprland/src/version.h", Path(include) / "src/version.h"):
            if header.exists():
                match = re.search(r'#define GIT_COMMIT_HASH\s+"([^"]+)"', header.read_text())
                if match:
                    header_hashes.add(match[1])
    if header_hashes != {HYPRLAND}:
        raise SystemExit(f"Missing or mismatched Hyprland headers: {header_hashes}")
    run("pkg-config", "--exists", "lua5.5")

    temporary_root = Path("/tmp/opencode")
    temporary_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="scrolloverview-build-", dir=temporary_root) as directory:
        source = Path(directory)
        run("git", "init", "--quiet", str(source))
        run("git", "-C", str(source), "fetch", "--depth=1",
            "https://github.com/yayuuu/hyprland-scroll-overview.git", REVISION)
        run("git", "-C", str(source), "checkout", "--quiet", "--detach", "FETCH_HEAD")
        run("git", "-C", str(source), "apply", "--check", str(PATCH.resolve()))
        run("git", "-C", str(source), "apply", str(PATCH.resolve()))
        run("git", "-C", str(source), "apply", "--check", str(INSERT_PATCH.resolve()))
        run("git", "-C", str(source), "apply", str(INSERT_PATCH.resolve()))
        shutil.copy2(INSERT_SOURCE, source / INSERT_SOURCE.name)
        env = dict(os.environ, SCROLLOVERVIEW_BUILD_VERSION=VERSION)
        run("make", "all", "LUA_PKG=lua5.5", cwd=source, env=env)

        digest = hashlib.sha256((source / "scrolloverview.so").read_bytes()).hexdigest()
        library = STORE / f"scrolloverview-{VERSION}-{time.time_ns()}.so"
        shutil.copy2(source / "scrolloverview.so", library)

    record = {
        "library": str(library), "sha256": digest,
        "upstream": REVISION, "hyprland": HYPRLAND,
        "abi_hash": installed["abiHash"],
        "patch_sha256": hashlib.sha256(PATCH.read_bytes()).hexdigest(),
        "insert_patch_sha256": hashlib.sha256(INSERT_PATCH.read_bytes()).hexdigest(),
        "insert_source_sha256": hashlib.sha256(INSERT_SOURCE.read_bytes()).hexdigest(),
    }
    (STORE / "build.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"Built {library}")
    if args.load:
        load_built_plugin(library, previous, args.old_path, installed["abiHash"])
    if args.install:
        target = hyprpm_target()
        backup_digest = hashlib.sha256(target.read_bytes()).hexdigest()
        backup = STORE / f"backup-{backup_digest}.so"
        if not backup.exists():
            shutil.copy2(target, backup)
        record.update(target=str(target), backup=str(backup), backup_sha256=backup_digest, installed=False)
        (STORE / "installation.json").write_text(json.dumps(record, indent=2) + "\n")
        if not os.access(target.parent, os.W_OK):
            installation_hint(library, target)
            raise SystemExit(1)
        atomic_copy(library, target)
        record["installed"] = True
        (STORE / "installation.json").write_text(json.dumps(record, indent=2) + "\n")
        print(f"Installed {target}; previous binary preserved at {backup}")
        print("No running plugin was changed. Restart Hyprland, or explicitly unload the old plugin and load the versioned library above.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError, OSError) as error:
        raise SystemExit(str(error)) from error
