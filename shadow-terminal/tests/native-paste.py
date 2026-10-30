#!/usr/bin/env python3
"""Exercise native fish bulk paste inside integration.py's private harness."""
import importlib.util
import os
from pathlib import Path
import select
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("terminal_integration", HERE / "integration.py")
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


def worker(tmp):
    env = os.environ.copy()
    log = open(tmp / "paste.log", "wb")
    app = subprocess.Popen([str(harness.BINARY), "--session", "paste", "--input", "terminal",
                            "--size", "1040x780"], env=env, cwd=tmp, stdout=log, stderr=log)

    def xdo(*args):
        return subprocess.run(["xdotool", *args], env=env, capture_output=True,
                              text=True, timeout=4).stdout.strip()

    def ready():
        result = subprocess.run(["gdbus", "call", "--session", "--dest", "io.github.visrosa.Vibrant.ShadowTerm",
                                 "--object-path", "/io/github/visrosa/Vibrant/Shell", "--method",
                                 "io.github.visrosa.Vibrant.Shell1.GetState", "paste"],
                                env=env, capture_output=True, text=True, timeout=3)
        return "ready" in result.stdout

    def command(source):
        xdo("type", "--clearmodifiers", "--delay", "1", "--", source)
        xdo("key", "Return")

    def paste(source, expected, primary=False, prefix=""):
        payload = tmp / "payload"
        payload.write_text(source)
        args = [sys.executable, str(HERE / "clipboard.py"), str(payload)]
        if primary:
            args.append("--primary")
        owner = subprocess.Popen(args, env=env, stdout=subprocess.PIPE, text=True)
        try:
            assert select.select([owner.stdout], [], [], 4)[0]
            assert owner.stdout.readline().strip() == "ready"
            if primary:
                xdo("mousemove", "--window", wid, "350", "200", "click", "2")
            else:
                xdo("key", "ctrl+shift+v")
            # Read only through an explicit native binding; Return is never
            # sent to the inserted source, even when it resembles commands.
            def inserted():
                xdo("key", "ctrl+alt+o")
                snapshot = tmp / "buffer"
                if not snapshot.exists():
                    return None
                result = snapshot.read_text()
                return result if result == prefix + expected + "\n" else None
            return harness.wait_for(inserted, "native paste insertion", timeout=5)
        finally:
            owner.terminate()
            owner.wait(timeout=3)

    try:
        wid = harness.wait_for(lambda: xdo("search", "--onlyvisible", "--name", " · paste$"), "native fish window")
        xdo("windowfocus", "--sync", wid)
        harness.wait_for(ready, "native fish readiness")
        command(f"bind alt-ctrl-o 'commandline > {tmp}/buffer.next; command mv {tmp}/buffer.next {tmp}/buffer'; printf ready > {tmp}/bound")
        harness.wait_for(lambda: (tmp / "bound").exists(), "native snapshot binding")
        harness.wait_for(ready, "ready after binding")
        # Include an executable-looking first line to prove insertion never
        # evaluates it, and enough short lines to expose per-line shell work.
        dense = f"printf executed > {tmp}/unexpected\n" + "x\n" * 40500
        source = "  const value = 'a\\\\b'; // λ\n" * 2800
        cases = [
            ("small", "echo first\n    echo second\n", "echo first\necho second\n", False, ""),
            ("dense", dense, dense, False, ""),
            ("primary", dense, dense, True, ""),
            ("source", source, source.lstrip(), False, ""),
            ("quoted", source, source.replace("\\", "\\\\").replace("'", "\\'"), False, "echo '"),
            ("controls", "a\t\x03b\r\n" * 6000, "a␃b\n" * 6000, False, ""),
        ]
        for name, payload, expected, primary, prefix in cases:
            if prefix:
                xdo("type", "--clearmodifiers", "--delay", "1", "--", prefix)
            started = time.monotonic()
            actual = paste(payload, expected, primary, prefix)
            elapsed = time.monotonic() - started
            assert actual == prefix + expected + "\n", (name, len(actual), len(expected), repr(actual[:40]), repr(expected[:40]))
            assert not (tmp / "unexpected").exists(), "Paste executed source"
            # Bracketed paste remains a single native undo group, including
            # large insertions into an already occupied/quoted prompt.
            (tmp / "buffer").unlink()
            xdo("key", "ctrl+z", "ctrl+alt+o")
            harness.wait_for(lambda: (tmp / "buffer").exists() and (tmp / "buffer").read_text() == prefix + "\n", "native paste undo")
            assert (tmp / "buffer").read_text() == prefix + "\n", name
            (tmp / "buffer").unlink()
            xdo("key", "ctrl+c")
            harness.wait_for(ready, "ready after paste cancellation")
            print(f"PASS: native {name} paste, {len(payload.encode())} bytes, {elapsed:.3f}s, exact insertion/undo, no execution")
        command(f"printf checked > {tmp}/responsive")
        harness.wait_for(lambda: (tmp / "responsive").exists(), "fish responsive after bulk paste")
    finally:
        subprocess.run([str(harness.BINARY), "--session", "paste", "--quit"], env=env, timeout=4)
        app.wait(timeout=4)
        log.close()
