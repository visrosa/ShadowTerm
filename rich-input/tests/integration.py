#!/usr/bin/env python3
"""Exercise the real GTK client and cv broker under a short-lived private Xvfb."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def wait_for(check, description, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError(f"Timed out: {description}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cv", type=Path, required=True, help="ClaudeVassal repository")
    parser.add_argument("--screenshot", type=Path, help="optional isolated-window capture")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="rich-input-test-") as directory:
        tmp = Path(directory)
        (tmp / "config").mkdir()
        # No service directories: a test settings lookup must not autostart
        # desktop portals, file managers or other unrelated session services.
        bus_config = tmp / "bus.conf"
        bus_config.write_text('<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>'
                              '<policy context="default"><allow send_destination="*"/>'
                              '<allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
        stub = tmp / "claude"
        stub.write_text("#!/usr/bin/env python3\nimport json,os,sys\n"
                        "open(os.environ['ARGV_CAPTURE'],'a').write(json.dumps(sys.argv[-1])+'\\n')\n"
                        "print(json.dumps({'type':'system','subtype':'init','session_id':'gui-test'}))\n"
                        "print(json.dumps({'type':'assistant','session_id':'gui-test',"
                        "'message':{'content':[{'type':'text','text':'**Stub reply**'}]}}))\n")
        stub.chmod(0o755)
        read_fd, write_fd = os.pipe()
        with open(tmp / "xvfb.log", "wb") as log:
            server = subprocess.Popen(["Xvfb", "-displayfd", str(write_fd), "-screen", "0",
                                       "1024x850x24", "-nolisten", "tcp", "-noreset"],
                                      pass_fds=(write_fd,), stdout=log, stderr=log)
        os.close(write_fd)
        broker = None
        try:
            with os.fdopen(read_fd) as pipe:
                display = ":" + pipe.readline().strip()
            env = os.environ | {"DISPLAY": display, "GSK_RENDERER": "cairo",
                                "LIBGL_ALWAYS_SOFTWARE": "1", "GTK_A11Y": "none", "GDK_BACKEND": "x11",
                                "GIO_USE_VFS": "local", "GTK_USE_PORTAL": "0",
                                "PATH": str(tmp) + os.pathsep + os.environ["PATH"],
                                "XDG_CONFIG_HOME": str(tmp / "config"),
                                "ARGV_CAPTURE": str(tmp / "argv.json"),
                                "CLAUDEVASSAL_CACHE_DIR": str(tmp / "cache")}
            # A private D-Bus session prevents the test app from touching the
            # desktop's existing application/settings services.
            with open(tmp / "broker.log", "wb") as log:
                broker = subprocess.Popen(["dbus-run-session", "--config-file=" + str(bus_config), "--", "python3",
                                           str(args.cv / "shadow_terminal.py"), "run",
                                           "--rich-input", "--gui", str(ROOT / "build/vibrant-rich-input")],
                                          env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                          start_new_session=True)

            def xdo(*arguments, check=True):
                return subprocess.run(["xdotool", *arguments], env=env, capture_output=True,
                                      text=True, check=check, timeout=4)

            def find_window():
                proc = xdo("search", "--onlyvisible", "--name", "^V Composer$", check=False)
                return proc.stdout.strip().splitlines()[:1]

            window = wait_for(find_window, "composer window")[0]
            # --sync focuses only this private display, never a desktop window.
            xdo("windowfocus", "--sync", window)
            source = "# A heading\n\n**bold** and `fish`\n"
            xdo("key", "alt+m")
            for index, line in enumerate(source.split("\n")):
                if index:
                    xdo("key", "Return")
                if line:
                    xdo("type", "--clearmodifiers", "--delay", "1", "--", line)
            time.sleep(0.1)
            xdo("key", "ctrl+Return")
            wait_for((tmp / "argv.json").exists, "GUI submission")
            received = json.loads((tmp / "argv.json").read_text().splitlines()[0])
            assert received == source, (received, source)
            cache = tmp / "cache/gui-test.jsonl"
            wait_for(cache.exists, "session cache")
            records = [json.loads(line) for line in cache.read_text().splitlines()]
            assert records[0]["prompt"] == source
            time.sleep(0.15)
            assert len((tmp / "argv.json").read_text().splitlines()) == 1
            # No window manager runs on this display. Click the fixed footer
            # action directly instead of depending on desktop mnemonic policy.
            geometry = xdo("getwindowgeometry", "--shell", window).stdout
            size = dict(line.split("=", 1) for line in geometry.splitlines() if "=" in line)
            xdo("mousemove", "--window", window, str(int(size["WIDTH"]) - 128),
                str(int(size["HEIGHT"]) - 25), "click", "1")
            if args.screenshot:
                time.sleep(0.1)
                subprocess.run(["import", "-display", display, "-window", window,
                                str(args.screenshot)], check=True, timeout=4)
            # Recalling source exercises broker -> editor communication, then
            # submitting it again proves hidden delimiters survive that path.
            xdo("key", "ctrl+Return")
            wait_for(lambda: len((tmp / "argv.json").read_text().splitlines()) == 2,
                     "recalled source submission")
            assert json.loads((tmp / "argv.json").read_text().splitlines()[1]) == source
            xdo("key", "ctrl+q")
            broker.wait(timeout=5)
            log = (tmp / "broker.log").read_text(errors="replace")
            assert "CRITICAL" not in log and "Traceback" not in log, log
            print("GTK -> broker -> fish -> Claude argv/cache: exact source preserved")
        except Exception as error:
            log_path = tmp / "broker.log"
            log = log_path.read_text(errors="replace") if log_path.exists() else ""
            raise AssertionError(f"{error}; broker status {broker.poll()}\n{log}") from error
        finally:
            if broker and broker.poll() is None:
                import signal
                os.killpg(broker.pid, signal.SIGTERM)
                try:
                    broker.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(broker.pid, signal.SIGKILL)
                    broker.wait()
            server.terminate()
            server.wait(timeout=3)


if __name__ == "__main__":
    main()
