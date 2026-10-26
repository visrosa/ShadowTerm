#!/usr/bin/env python3
"""Exercise real terminal sessions on a private software-X11 display and bus."""

import argparse
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "build/shadow-term"


def wait_for(check, description, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError(f"Timed out: {description}")


def worker(tmp):
    env = os.environ.copy()
    processes = []
    known_children = {}
    log = open(tmp / "app.log", "wb")

    def invoke(*args, expect=0):
        result = subprocess.run([str(BINARY), *args], env=env, text=True,
                                capture_output=True, timeout=5)
        assert result.returncode == expect, (args, result.returncode, result.stderr)
        return result.stdout

    def launch(*args):
        p = subprocess.Popen([str(BINARY), *args], env=env, stdout=log, stderr=log)
        processes.append(p)
        return p

    def sessions():
        rows = invoke("--list").splitlines()
        return {name: (state, int(pid)) for name, state, pid in (r.split("\t") for r in rows)}

    def xdo(*args, check=True):
        return subprocess.run(["xdotool", *args], env=env, capture_output=True,
                              text=True, timeout=4, check=check).stdout.strip()

    def window(name):
        result = xdo("search", "--onlyvisible", "--name", " · " + name + "$", check=False)
        return result.splitlines()[0] if result else None

    def focus(name):
        wid = wait_for(lambda: window(name), name + " window")
        xdo("windowfocus", "--sync", wid)
        time.sleep(0.08)
        return wid

    def type_text(text):
        xdo("type", "--clearmodifiers", "--delay", "1", "--", text)

    def shell(command):
        type_text(command)
        xdo("key", "Return")

    def read(path):
        return path.read_text() if path.exists() else ""

    def identity(pid):
        try:
            return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]
        except FileNotFoundError:
            return None

    def track(pid):
        known_children[pid] = identity(pid)

    try:
        subprocess.run([str(ROOT / "build/editor-test")], env=env, check=True, timeout=5)
        subprocess.run([str(ROOT / "build/appearance-test")], env=env, check=True, timeout=5)
        subprocess.run([str(ROOT / "build/presentation-test")], env=env, check=True, timeout=25)
        launch("--input", "terminal", "--cwd", str(tmp), "--size", "900x620")
        wait_for(lambda: window("default"), "initial terminal window")
        pid = wait_for(lambda: sessions().get("default", (None, 0))[1], "default shell PID")
        track(pid)
        assert "fish" in Path(f"/proc/{pid}/cmdline").read_text()
        wid = focus("default")
        identity_properties = subprocess.check_output(
            ["xprop", "-id", wid, "WM_CLASS", "_GTK_APPLICATION_ID"], env=env, text=True)
        assert identity_properties.count("io.github.visrosa.Vibrant.ShadowTerm") >= 2, identity_properties
        icon_property = subprocess.check_output(["xprop", "-id", wid, "_NET_WM_ICON"], env=env, text=True)
        assert "not found" not in icon_property and "no such atom" not in icon_property, "Missing application icon"
        shell(f"printf '%s' ready > {tmp}/ready")
        wait_for(lambda: read(tmp / "ready") == "ready", "interactive fish input")
        shell(f"pwd > {tmp}/cwd; printf '%s\\n' $TERM $TERM_PROGRAM > {tmp}/env")
        wait_for(lambda: read(tmp / "env") == "xterm-256color\nshadow-term\n", "terminal environment")
        assert read(tmp / "cwd").strip() == str(tmp)
        shell("set kept retained")
        invoke("--hide")
        assert sessions()["default"] == ("hidden", pid)
        assert not window("default")
        invoke("--show")
        focus("default")
        assert sessions()["default"][1] == pid
        shell(f"printf '%s' $kept > {tmp}/kept")
        wait_for(lambda: read(tmp / "kept") == "retained", "shell state after hide/show")
        shell(f"stty size > {tmp}/size-before")
        wait_for(lambda: read(tmp / "size-before"), "initial PTY size")
        xdo("windowsize", wid, "1050", "730")
        time.sleep(0.15)
        shell(f"stty size > {tmp}/size-after")
        wait_for(lambda: read(tmp / "size-after"), "resized PTY")
        assert read(tmp / "size-before") != read(tmp / "size-after")
        shell(f"sh -c 'echo $$ > {tmp}/sleep-pid; exec sleep 30'")
        sleeper = int(wait_for(lambda: read(tmp / "sleep-pid"), "foreground process"))
        track(sleeper)
        xdo("key", "ctrl+c")
        wait_for(lambda: not Path(f"/proc/{sleeper}").exists(), "Ctrl+C interrupts foreground job")
        shell(f"printf alive > {tmp}/after-interrupt")
        wait_for(lambda: read(tmp / "after-interrupt") == "alive", "shell survives Ctrl+C")

        fixture = tmp / "raw.py"
        fixture.write_text("""import json,os,sys,tty
from pathlib import Path
root=Path(sys.argv[1])
(root/'raw-info').write_text(json.dumps({'argv':sys.argv[2:],'cwd':os.getcwd(),'tty':os.isatty(0),'pid':os.getpid()}))
tty.setraw(0)
os.write(1,b'\\x1b[?1049h\\x1b[?2004hRaw input ready')
with (root/'raw-input').open('ab',buffering=0) as out:
 while True:
  data=os.read(0,65536)
  if not data: break
  out.write(data)
""")
        argv = ("--session", "raw", "--hide-on-focus-loss", "--cwd", str(tmp), "--",
                sys.executable, str(fixture), str(tmp), "literal $value", "quotes ' \"", "日本語")
        invoke(*argv)
        info = json.loads(wait_for(lambda: read(tmp / "raw-info"), "arbitrary argv process"))
        raw_pid = info["pid"]
        track(raw_pid)
        assert info["argv"] == ["literal $value", "quotes ' \"", "日本語"]
        assert info["tty"] and info["cwd"] == str(tmp)
        raw_wid = focus("raw")
        xdo("key", "ctrl+shift+m")
        source = "# Heading\n**bold** `code` $literal"
        for i, line in enumerate(source.splitlines()):
            if i:
                xdo("key", "Return")
            type_text(line)
        # Source-copy includes markup hidden by the WYSIWYG presentation.
        xdo("key", "ctrl+a", "ctrl+shift+c", "ctrl+shift+Return")
        capture = tmp / "raw-input"
        expected = b"\x1b[200~" + source.replace("\n", "\r").encode() + b"\x1b[201~"
        wait_for(lambda: capture.exists() and capture.read_bytes(), "composer paste")
        assert capture.read_bytes() == expected, (capture.read_bytes(), expected)
        xdo("key", "ctrl+shift+v")
        wait_for(lambda: len(capture.read_bytes()) > len(expected), "clipboard paste")
        assert capture.read_bytes() == expected * 2, (capture.read_bytes(), expected * 2)
        xdo("key", "Page_Up", "Page_Down", "F1")
        raw_keys = b"\x1b[5~\x1b[6~\x1bOP"
        wait_for(lambda: len(capture.read_bytes()) >= len(expected) * 2 + len(raw_keys), "alternate-screen program keys")
        assert capture.read_bytes() == expected * 2 + raw_keys
        # Repeating a launcher with identical argv must reuse the session.
        invoke(*argv)
        assert sessions()["raw"][1] == raw_pid
        invoke("--session", "raw", "--", "/bin/false", expect=2)
        focus("raw")
        focus("default")
        wait_for(lambda: sessions()["raw"][0] == "hidden", "hide on external focus loss")
        assert sessions()["raw"][1] == raw_pid
        invoke("--session", "raw", "--show")
        focus("raw")
        invoke("--session", "raw", "--toggle")
        assert sessions()["raw"][0] == "hidden"
        invoke("--session", "raw", "--quit")
        wait_for(lambda: "raw" not in sessions(), "raw session cleanup")
        wait_for(lambda: not Path(f"/proc/{raw_pid}").exists(), "raw child reaped")

        invoke("--session", "bad", "--", "/no/such/shadow-test-command")
        wait_for(lambda: window("bad"), "visible spawn failure")
        assert sessions()["bad"][1] == 0
        invoke("--session", "bad", "--quit")
        invoke("--session", "short", "--", "/bin/true")
        wait_for(lambda: "short" not in sessions(), "normal command exit")
        invoke("--session", "held", "--hold", "--", "/bin/true")
        wait_for(lambda: window("held"), "held command output")
        invoke("--session", "held", "--quit")
        # Exercise the bounded shutdown path when graceful signals are ignored.
        stubborn = tmp / "stubborn.py"
        stubborn.write_text("import os,signal,time\nfrom pathlib import Path\n"
                            "signal.signal(signal.SIGHUP,signal.SIG_IGN)\n"
                            "signal.signal(signal.SIGTERM,signal.SIG_IGN)\n"
                            f"Path({str(tmp / 'stubborn-ready')!r}).write_text(str(os.getpid()))\n"
                            "time.sleep(30)\n")
        invoke("--session", "stubborn", "--", sys.executable, str(stubborn))
        stubborn_pid = int(wait_for(lambda: read(tmp / "stubborn-ready"), "signal-resistant child"))
        track(stubborn_pid)
        invoke("--session", "stubborn", "--quit")
        wait_for(lambda: "stubborn" not in sessions(), "forced child cleanup")
        wait_for(lambda: not Path(f"/proc/{stubborn_pid}").exists(), "forced child reaped")
        invoke("--hide")
        geometry = read(tmp / "state/shadow-term/geometry.ini")
        assert "width=1050" in geometry and "height=730" in geometry, geometry
        invoke("--quit")
        processes[0].wait(timeout=5)
        wait_for(lambda: not Path(f"/proc/{pid}").exists(), "shell reaped on quit")
        restored = launch()
        restored_wid = wait_for(lambda: window("default"), "restored terminal")
        new_pid = wait_for(lambda: sessions().get("default", (None, 0))[1], "restored shell PID")
        track(new_pid)
        geometry = xdo("getwindowgeometry", "--shell", restored_wid)
        assert "WIDTH=1050" in geometry and "HEIGHT=730" in geometry, geometry
        invoke("--quit")
        restored.wait(timeout=5)
        assert invoke("--list") == ""
        invoke("--session", "missing", "--quit", expect=1)
        log.flush()
        app_log = read(tmp / "app.log")
        assert "CRITICAL" not in app_log and "ERROR **" not in app_log, app_log
        print("PASS: fish/argv/cwd, Ctrl+C, PTY resize, persistent sessions, composer/clipboard paste, focus/hide, launch/exit/cleanup")
    finally:
        for name in ("raw", "held", "short", "bad", "stubborn", "default"):
            try:
                invoke("--session", name, "--quit", expect=0)
            except (AssertionError, subprocess.TimeoutExpired):
                pass
        for process in processes:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        for pid, started in known_children.items():
            try:
                if started is not None and identity(pid) == started:
                    os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--frontend", action="store_true", help="test Composer's interactive fish adapter")
    parser.add_argument("--presentation", action="store_true", help="only check layout and live rendering on a private display")
    args = parser.parse_args()
    if args.worker:
        if os.environ.get("SHADOW_TERM_PRIVATE_TEST") != "1":
            raise SystemExit("Workers must be launched by the private-display harness")
        if args.presentation:
            subprocess.run([str(ROOT / "build/editor-test")], check=True, timeout=8)
            subprocess.run([str(ROOT / "build/appearance-test")], check=True, timeout=5)
            subprocess.run([str(ROOT / "build/presentation-test")], check=True, timeout=25)
        elif args.frontend:
            import runpy
            runpy.run_path(str(Path(__file__).with_name("fish-frontend.py")))["worker"](args.worker)
        else:
            worker(args.worker)
        return
    # The CLI should give these answers even without any graphical session.
    clean_env = os.environ.copy()
    clean_env.pop("DISPLAY", None)
    clean_env.pop("WAYLAND_DISPLAY", None)
    assert subprocess.check_output([str(BINARY), "--version"], env=clean_env, text=True).strip() == "Shadow Term 0.0.8"
    assert subprocess.run([str(BINARY), "--size", "3x4"], env=clean_env, capture_output=True).returncode == 2
    with tempfile.TemporaryDirectory(prefix="shadow-term-test-") as directory:
        tmp = Path(directory)
        config = tmp / "bus.conf"
        config.write_text('<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>'
                          '<policy context="default"><allow send_destination="*"/>'
                          '<allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
        (tmp / "config").mkdir()
        (tmp / "config/fish").mkdir()
        (tmp / "config/fish/config.fish").write_text(
            "function fish_prompt\n set -l previous_status $status\n printf 'LEFT[%s]\\n> ' $previous_status\nend\n"
            "function fish_right_prompt; printf RIGHT; end\nfunction fish_greeting; end\n")
        # A fresh GTK compose cache must not compile the user's custom table.
        compose = tmp / "config/gtk-4.0/Compose"
        compose.parent.mkdir()
        compose.write_text('<Multi_key> <a> <e> : "\u00e6" ae\n')
        read_fd, write_fd = os.pipe()
        display_log = open(tmp / "display.log", "w+")
        server = subprocess.Popen(["Xvfb", "-displayfd", str(write_fd), "-screen", "0", "1200x900x24",
                                   "-nolisten", "tcp", "-noreset"], pass_fds=(write_fd,),
                                  stdout=subprocess.DEVNULL, stderr=display_log)
        os.close(write_fd)
        try:
            if not select.select([read_fd], [], [], 15)[0]:
                display_log.seek(0)
                raise AssertionError("Private Xvfb did not start: " + display_log.read())
            with os.fdopen(read_fd) as pipe:
                display = ":" + pipe.readline().strip()
            env = os.environ | {"DISPLAY": display, "GDK_BACKEND": "x11", "GSK_RENDERER": "cairo",
                                "LIBGL_ALWAYS_SOFTWARE": "1", "GTK_A11Y": "none", "GTK_USE_PORTAL": "0",
                                "GIO_USE_VFS": "local", "SHADOW_TERM_PRIVATE_TEST": "1", "XDG_CONFIG_HOME": str(tmp / "config"),
                                "XDG_STATE_HOME": str(tmp / "state"), "XDG_DATA_HOME": str(tmp / "data"),
                                "XDG_CACHE_HOME": str(tmp / "cache"), "fish_history": "shadow_term_test",
                                "SHELL": "/usr/bin/fish"}
            arguments = ["dbus-run-session", "--config-file=" + str(config), "--", sys.executable,
                         str(Path(__file__).resolve()), "--worker", str(tmp)]
            if args.frontend:
                arguments.append("--frontend")
            if args.presentation:
                arguments.append("--presentation")
            result = subprocess.run(arguments, env=env,
                                    capture_output=True, text=True, timeout=90)
            if result.returncode:
                app_log = "\n".join(p.read_text(errors="replace") for p in (tmp / "app.log", tmp / "frontend.log") if p.exists())
                raise AssertionError(result.stdout + result.stderr + "\n" + app_log)
            if not args.presentation:
                # Interactive fish persists history in its data directory,
                # independently of the configuration directory and display.
                history = tmp / "data/fish/shadow_term_test_history"
                assert history.exists() and str(tmp).encode() in history.read_bytes(), "Missing isolated fish history"
            print(result.stdout.strip())
        finally:
            server.terminate()
            server.wait(timeout=3)
            display_log.close()


if __name__ == "__main__":
    main()
