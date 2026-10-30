#!/usr/bin/env python3
"""Build a pinned, private Vala compiler; do not replace the system toolchain."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent
VERSION = "0.56.19"
SHA256 = "5ad7cbbfcc0de61b403d6797c9ef60455bfbebd8e162aec33b5b0b097adfb9d5"
PATCH = ROOT / f"vala-{VERSION}-constness.patch"


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, default=ROOT.parents[1] / "shadow-terminal/build")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--bootstrap", default="valac-0.56")
    args = parser.parse_args()
    bootstrap = shutil.which(args.bootstrap)
    if not bootstrap:
        parser.error("A working bootstrap Vala compiler is required")
    revision = hashlib.sha256(PATCH.read_bytes()).hexdigest()[:12]
    work = args.build.resolve() / "vala-toolchain" / revision
    work.mkdir(parents=True, exist_ok=True)
    archive = args.archive.resolve() if args.archive else work.parent / f"vala-{VERSION}.tar.xz"
    if not archive.exists():
        urllib.request.urlretrieve(f"https://download.gnome.org/sources/vala/0.56/vala-{VERSION}.tar.xz", archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise SystemExit("Vala archive checksum mismatch")
    source = work / f"vala-{VERSION}"
    stamp = work / "prepared"
    if not stamp.exists():
        if source.exists():
            raise SystemExit(f"Incomplete preparation retained at {source}; choose another --build directory")
        with tarfile.open(archive) as package:
            package.extractall(work, filter="data")
        run("patch", "-p1", "-i", PATCH, cwd=source)
        stamp.touch()
    output = work / "compile"
    prefix = work / "prefix"
    output.mkdir(exist_ok=True)
    # AC_PATH_PROG needs an absolute bootstrap path. A missing compiler makes
    # the release build silently reuse its pre-generated, unpatched C instead.
    environment = os.environ | {"VALAC": str(Path(bootstrap).resolve())}
    if not (output / "Makefile").exists():
        run(source / "configure", f"--prefix={prefix}", "--disable-valadoc", cwd=output, env=environment)
    run("make", "-j1", f"VALAC={bootstrap}", cwd=output)
    run("make", "-j1", "install", f"VALAC={bootstrap}", cwd=output)
    wrapper = work / "valac"
    # Explicit VAPI precedence matters when the system provides the same slot.
    wrapper.write_text("#!/usr/bin/env python3\nimport os, sys\n"
                       f"os.execv({str(prefix / 'bin/valac')!r}, [{str(prefix / 'bin/valac')!r}, "
                       f"{'--vapidir=' + str(prefix / 'share/vala-0.56/vapi')!r}, *sys.argv[1:]])\n")
    wrapper.chmod(0o755)
    run(wrapper, "--target-glib=2.76", "-X", "-Wall", "-X", "-Werror=discarded-qualifiers",
        "-X", "-Werror=incompatible-pointer-types", "-X", "-Werror=pointer-sign",
        ROOT / "constness.vala", "--directory", work, "-o", work / "constness-test")
    run(work / "constness-test")
    flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", "glib-2.0"], text=True))
    run(*shlex.split(os.environ.get("CC", "cc")), "-Wall", "-Wextra", "-Werror", "-I" + str(source / "vala"),
        ROOT / "system-dirs.c", *flags, "-o", work / "system-dirs-test")
    run(work / "system-dirs-test")
    print(wrapper)


if __name__ == "__main__":
    main()
