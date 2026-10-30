#!/usr/bin/env python3
"""Build the pinned reader-seam experiment without editing or installing fish."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parent
REVISION = "141e1cb742614e0bcc2f43515f65b6fa2b1d595d"


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fish_source", type=Path)
    parser.add_argument("--build", required=True, type=Path)
    args = parser.parse_args()
    patch = ROOT / "fish-reader.patch"
    digest = hashlib.sha256(patch.read_bytes()).hexdigest()[:12]
    work = args.build.resolve() / digest
    source = work / "source"
    stamp = work / "prepared"
    work.mkdir(parents=True, exist_ok=True)
    if not stamp.exists():
        if source.exists():
            raise SystemExit(f"Incomplete source retained at {source}; use another --build path")
        source.mkdir()
        # Export the exact commit, independently of local branches or dirty files.
        with subprocess.Popen(["git", "-C", str(args.fish_source.resolve()), "archive", REVISION], stdout=subprocess.PIPE) as archive:
            with tarfile.open(fileobj=archive.stdout, mode="r|") as package:
                package.extractall(source, filter="data")
            if archive.wait():
                raise SystemExit("Cannot export the pinned fish revision")
        run("patch", "-p1", "-i", patch, cwd=source)
        stamp.touch()
    target = work / "target"
    run("cargo", "build", "--offline", "-j1", "--bin", "fish", cwd=source,
        env=os.environ | {"CARGO_TARGET_DIR": str(target)})
    binary = target / "debug/fish"
    run("python3", ROOT / "check.py", binary)
    print(binary)


if __name__ == "__main__":
    main()
