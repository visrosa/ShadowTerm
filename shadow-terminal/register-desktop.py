#!/usr/bin/env python3
"""Register the existing build and its icon with the current user's desktop."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

APP_ID = "io.github.visrosa.Vibrant.ShadowTerm"
ROOT = Path(__file__).resolve().parent


def register(data_home, binary):
    binary = binary.resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise SystemExit(f"Build the executable first: {binary}")
    applications = data_home / "applications"
    icon = data_home / "icons/hicolor/scalable/apps" / f"{APP_ID}.svg"
    applications.mkdir(parents=True, exist_ok=True)
    icon.parent.mkdir(parents=True, exist_ok=True)
    # Desktop Exec quoting has its own escaping, independent of shell quoting.
    if any(c in str(binary) for c in "\n\r%"):
        raise SystemExit("Desktop executable paths must not contain line breaks or percent signs")
    quoted = "".join("\\" + c if c in '\\"`$' else c for c in str(binary))
    executable = quoted.replace("\\", "\\\\").replace("%", "%%")
    desktop = applications / f"{APP_ID}.desktop"
    content = ("[Desktop Entry]\nType=Application\nName=Shadow Term\n"
               "Comment=Terminal sessions with V Composer\n"
               f'Exec="{executable}"\nIcon={APP_ID}\nStartupWMClass={APP_ID}\n'
               "Terminal=false\nStartupNotify=true\nCategories=System;TerminalEmulator;\n")
    if desktop.exists() and desktop.read_text() != content:
        backup = desktop.with_suffix(".desktop.previous")
        if backup.exists():
            raise SystemExit(f"Existing desktop entry differs; preserve or remove its backup first: {backup}")
        backup.write_bytes(desktop.read_bytes())
    desktop.write_text(content)
    shutil.copyfile(ROOT / "data/icons/scalable/apps" / f"{APP_ID}.svg", icon)
    validator = shutil.which("desktop-file-validate")
    if validator:
        subprocess.run([validator, str(desktop)], check=True)
    updater = shutil.which("update-desktop-database")
    if updater:
        subprocess.run([updater, str(applications)], check=True)
    print(f"Registered {desktop}\nIcon: {icon}\nExecutable: {binary}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-home", type=Path, default=Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")))
    parser.add_argument("--binary", type=Path, default=ROOT / "build/shadow-term")
    args = parser.parse_args()
    register(args.data_home, args.binary)
