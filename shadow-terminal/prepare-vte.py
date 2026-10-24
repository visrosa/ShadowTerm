#!/usr/bin/env python3
"""Prepare an ABI-compatible, privately linked VTE; never install a system package."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent
VERSION = "0.82.4"
ARCHIVE = f"vte-{VERSION}.tar.xz"
URL = f"https://download.gnome.org/sources/vte/0.82/{ARCHIVE}"
SHA256 = "6b1c06fb4df10c82661e3596130fc6bf77a2fa9f57d8432826b1d5eca23bf3e1"
PATCH = ROOT / "patches/vte-0.82.4-hover-only-hyperlinks.patch"


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def prepare(archive, build):
    work = build / "private-vte"
    source = work / f"vte-{VERSION}"
    output = work / "compile"
    work.mkdir(parents=True, exist_ok=True)
    if archive is None:
        archive = work / ARCHIVE
        if not archive.exists():
            urllib.request.urlretrieve(URL, archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != SHA256:
        raise SystemExit("VTE archive checksum does not match GNOME's published release")
    patch_digest = hashlib.sha256(PATCH.read_bytes()).hexdigest()
    stamp = work / "presentation-patch.sha256"
    if source.exists() and (not stamp.exists() or stamp.read_text().strip() != patch_digest):
        reverse = subprocess.run(["patch", "--dry-run", "--reverse", "-p1", "-i", str(PATCH)],
                                 cwd=source, capture_output=True)
        if reverse.returncode != 0:
            # A new patch gets its own source/build tree. Keep the library that
            # existing windows or their launchers still reference available.
            work = work / patch_digest[:12]
            source = work / f"vte-{VERSION}"
            output = work / "compile"
            work.mkdir(parents=True, exist_ok=True)
            stamp = work / "presentation-patch.sha256"
    if not source.exists():
        # The data filter rejects external paths/links and leaves ownership with
        # the caller, rather than restoring the release archive's numeric owners.
        with tarfile.open(archive) as package:
            package.extractall(work, filter="data")
    if not stamp.exists() or stamp.read_text().strip() != patch_digest:
        reverse = subprocess.run(["patch", "--dry-run", "--reverse", "-p1", "-i", str(PATCH)],
                                 cwd=source, capture_output=True)
        if reverse.returncode != 0:
            run("patch", "--forward", "-p1", "-i", PATCH, cwd=source)
        stamp.write_text(patch_digest + "\n")
    options = ["-Dgtk3=false", "-Dgtk4=true", "-Dapp=false", "-Ddocs=false", "-Dgir=false",
               "-Dvapi=false", "-Dglade=false", "-D_systemd=false", "-Dbuildtype=release"]
    # Building only the library avoids VTE's examples and test executables.
    if not (output / "meson-info/intro-projectinfo.json").exists():
        run("meson", "setup", output, source, *options)
    run("meson", "compile", "-C", output, "-j", "1", "vte-2.91-gtk4")
    return output / "src"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Use a local release tarball instead of downloading")
    parser.add_argument("--build", type=Path, default=ROOT / "build", help="Shadow Term build directory")
    parser.add_argument("--configure", action="store_true", help="Point this Shadow Term build at the private library")
    args = parser.parse_args()
    build = args.build.resolve()
    library = prepare(args.archive.resolve() if args.archive else None, build)
    if args.configure:
        # Refresh option definitions before applying a newly introduced option
        # to a build directory created by an earlier Shadow Term release.
        run("meson", "setup", "--reconfigure", build)
        run("meson", "configure", build, "-Dvte-library-dir=" + str(library))
    print(library)


if __name__ == "__main__":
    main()
