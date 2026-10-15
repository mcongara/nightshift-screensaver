#!/usr/bin/env python3
"""Package either language from an explicit allowlist, excluding local user data."""
import argparse
from pathlib import Path
import shutil
import zipfile

REPO = Path(__file__).resolve().parents[1]


def launcher(language, uninstall=False):
    argument = " --uninstall" if uninstall else ""
    prompt = "Press Enter to close this window." if language == "en" else "Pencereyi kapatmak için Enter tuşuna bas."
    return f'''#!/bin/bash
cd "$(dirname "$0")" || exit 1
/bin/bash scripts/run-installer.sh{argument}
result=$?
printf '\\n{prompt}\\n'
read -r _reply
exit "$result"
'''


def package(language):
    build = REPO / "build" / language
    version = (REPO / "VERSION").read_text().strip()
    stage = REPO / "build/share" / language / "NightShift"
    archive_path = REPO / "build" / f"NightShift-{version}-macOS-arm64-{language.upper()}.zip"
    for relative in ("NightShift.saver/Contents/MacOS/NightShift", "NightShiftMonitor", "language.txt"):
        if not (build / relative).is_file():
            raise SystemExit(f"Build first: bash scripts/build.sh {language}")
    if (build / "language.txt").read_text().strip() != language:
        raise SystemExit("Build language does not match package language")
    if stage.exists():
        shutil.rmtree(stage)
    for directory in ("build", "bridge", "scripts"):
        (stage / directory).mkdir(parents=True, exist_ok=True)
    shutil.copytree(build / "NightShift.saver", stage / "build/NightShift.saver")
    for name in ("NightShiftMonitor", "language.txt"):
        shutil.copy2(build / name, stage / "build" / name)
    for relative in ("bridge/nightshift.py", "scripts/install.py", "scripts/run-installer.sh"):
        shutil.copy2(REPO / relative, stage / relative)
    names = ("Install.command", "Uninstall.command") if language == "en" else ("Kur.command", "Kaldir.command")
    for name, uninstall in zip(names, (False, True)):
        path = stage / name
        path.write_text(launcher(language, uninstall))
        path.chmod(0o755)
    (stage / "scripts/run-installer.sh").chmod(0o755)
    guide = "INSTALL.md" if language == "en" else "KURULUM.md"
    shutil.copy2(REPO / "docs" / f"INSTALL.{language}.md", stage / guide)
    for name in ("LICENSE", "VERSION"):
        shutil.copy2(REPO / name, stage / name)
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(stage.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(stage.parent))
    print(f"{archive_path} ({archive_path.stat().st_size / 1024:.0f} KB)")
    return archive_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("language", choices=("tr", "en", "all"), nargs="?", default="all")
    args = parser.parse_args()
    for language in (("tr", "en") if args.language == "all" else (args.language,)):
        package(language)


if __name__ == "__main__":
    main()
