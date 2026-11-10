#!/usr/bin/env python3
"""Install/uninstall a per-user screensaver, bridge and additive Claude hooks."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "bridge"))
from nightshift import EVENTS

LABEL = "local.nightshift.bridge"
MARKER = "# nightshift-hook-v1"


def stop_bridge(domain, launch, timeout=10):
    # bootout returns before launchd has torn the job down; bootstrapping too
    # early fails with "Input/output error" and leaves the bridge stopped.
    subprocess.run(["launchctl", "bootout", domain, str(launch)], capture_output=True)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if subprocess.run(["launchctl", "print", f"{domain}/{LABEL}"], capture_output=True).returncode:
            return
        time.sleep(0.25)


def start_bridge(domain, launch, attempts=5):
    for attempt in range(attempts):
        result = subprocess.run(["launchctl", "bootstrap", domain, str(launch)], capture_output=True, text=True)
        if not result.returncode:
            return result
        time.sleep(1 + attempt)
    return result


SYSTEM_PYTHON = "/usr/bin/python3"


def runtime_path():
    # Homebrew keeps moving its entry points (bin/python3 unlinked, then
    # libexec/bin/python3 dropped in 3.15), which breaks every hook and the
    # LaunchAgent at once. macOS's own Python never moves; the bridge only
    # needs the standard library, so use it whenever it actually runs.
    try:
        if subprocess.run([SYSTEM_PYTHON, "-c", "pass"], capture_output=True, timeout=10).returncode == 0:
            return SYSTEM_PYTHON
    except (OSError, subprocess.TimeoutExpired):
        pass
    return sys.executable


def merge_settings(settings, command=None):
    """Keep other hooks and options, remove only our marked handlers."""
    settings = json.loads(json.dumps(settings))
    hooks = settings.setdefault("hooks", {})
    for event, groups in list(hooks.items()):
        kept = []
        for group in groups:
            handlers = [h for h in group.get("hooks", []) if MARKER not in h.get("command", "")]
            if handlers:
                kept.append({**group, "hooks": handlers})
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if command:
        for event in EVENTS:
            hooks.setdefault(event, []).append({"hooks": [{"type": "command", "command": command, "timeout": 3}]})
    if not hooks:
        settings.pop("hooks", None)
    return settings


def write_settings(path, settings):
    path.parent.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    if path.exists():
        backup = path.with_name(path.name + ".nightshift-backup-" + stamp)
        shutil.copy2(path, backup)
        print("Settings backup:", backup)
    temp = path.with_name(path.name + ".nightshift-tmp")
    temp.write_text(json.dumps(settings, indent=2, ensure_ascii=False) + "\n")
    os.chmod(temp, 0o600)
    os.replace(temp, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--uninstall", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--language", choices=("tr", "en"), default="tr")
    args = parser.parse_args()
    # Source builds live under build/<language>; ZIPs carry one edition in build/.
    build = REPO / "build" / args.language
    if not build.is_dir() and (REPO / "build/language.txt").is_file():
        build = REPO / "build"
    if (build / "language.txt").is_file():
        language = (build / "language.txt").read_text().strip()
    else:
        language = args.language
    home = Path.home()
    data = home / "Library/Application Support/NightShift"
    saver = home / "Library/Screen Savers/NightShift.saver"
    launch = home / "Library/LaunchAgents" / (LABEL + ".plist")
    settings_path = home / ".claude/settings.json"
    settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
    python = runtime_path()
    command = f"{shlex.quote(python)} {shlex.quote(str(data / 'nightshift.py'))} hook {MARKER}"
    merged = merge_settings(settings, None if args.uninstall else command)
    if args.dry_run:
        print(json.dumps({"saver": str(saver), "bridge": str(data), "launchAgent": str(launch),
                          "settings": str(settings_path), "language": language, "hookEvents": list(EVENTS)}, indent=2))
        return
    if not args.uninstall:
        required = (build / "NightShift.saver/Contents/MacOS/NightShift", build / "NightShiftMonitor", REPO / "bridge/nightshift.py")
        if any(not path.is_file() for path in required):
            raise SystemExit("Missing package files. Extract the entire ZIP before installing, or build from source.")
    # Capture and validate settings before modifying any installed files.
    domain = f"gui/{os.getuid()}"
    if launch.exists():
        stop_bridge(domain, launch)
    if args.uninstall:
        write_settings(settings_path, merged)
        if saver.exists():
            shutil.rmtree(saver)
        launch.unlink(missing_ok=True)
        (data / "nightshift.py").unlink(missing_ok=True)
        (data / "NightShiftMonitor").unlink(missing_ok=True)
        print("Removed Night Shift. Local session states and settings backups remain.")
        return
    data.mkdir(parents=True, exist_ok=True, mode=0o700)
    shutil.copy2(REPO / "bridge/nightshift.py", data / "nightshift.py")
    shutil.copy2(build / "NightShiftMonitor", data / "NightShiftMonitor")
    saver.parent.mkdir(parents=True, exist_ok=True)
    if saver.exists():
        shutil.rmtree(saver)
    shutil.copytree(build / "NightShift.saver", saver)
    launch.parent.mkdir(parents=True, exist_ok=True)
    plist = {"Label": LABEL, "ProgramArguments": [python, str(data / "nightshift.py"), "serve"],
             "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 10,
             "StandardErrorPath": str(data / "bridge-error.log"),
             "StandardOutPath": str(data / "bridge.log")}
    with launch.open("wb") as output:
        plistlib.dump(plist, output)
    write_settings(settings_path, merged)
    result = start_bridge(domain, launch)
    if result.returncode:
        print("Installed files, but launchctl could not start the bridge:", result.stderr, file=sys.stderr)
        raise SystemExit(1)
    print("Installed Night Shift. Select it in macOS Screen Saver settings; restart Claude Code sessions.")


if __name__ == "__main__":
    main()
