#!/usr/bin/env python3
"""Use the shared private-display harness to test normal Composer-to-fish input."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import select
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("terminal_integration", HERE / "integration.py")
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


def worker(tmp):
    binary = str(harness.BINARY)
    env = os.environ.copy()
    logs = open(tmp / "frontend.log", "wb")
    app = subprocess.Popen([binary, "--session", "composer", "--input", "terminal", "--size", "1040x780"],
                           env=env, cwd=tmp, stdout=logs, stderr=logs)

    def xdo(*args, check=True):
        return subprocess.run(["xdotool", *args], env=env, check=check,
                              capture_output=True, text=True, timeout=4).stdout.strip()

    def visible():
        return xdo("search", "--onlyvisible", "--name", " · composer$", check=False)

    def read(name):
        p = tmp / name
        return p.read_text() if p.exists() else ""

    def text(source):
        xdo("type", "--clearmodifiers", "--delay", "1", "--", source)

    def command(source, marker):
        text(source)
        xdo("key", "Return")
        harness.wait_for(lambda: read(marker), marker)
        time.sleep(0.08)

    def state(session="composer"):
        result = subprocess.run(["gdbus", "call", "--session", "--dest", "io.github.visrosa.Vibrant.ShadowTerm",
                                 "--object-path", "/io/github/visrosa/Vibrant/Shell", "--method",
                                 "io.github.visrosa.Vibrant.Shell1.GetState", session],
                                env=env, capture_output=True, text=True, timeout=3)
        return result.stdout.strip()

    def new_tab():
        rows = subprocess.check_output([binary, "--list"], env=env, text=True).splitlines()
        return next((row.split("\t")[0] for row in rows if row.startswith("tab-")), None)

    try:
        wid = harness.wait_for(visible, "Composer fish window").splitlines()[0]
        xdo("windowfocus", "--sync", wid)
        harness.wait_for(lambda: "ready" in state(), "fish readiness event")
        time.sleep(0.05)
        # Starting native still installs the adapter, so enabling Composer later
        # suppresses both prompts without restarting the shell.
        native_seed = f"fish_prompt > {tmp}/initial-native-prompt; printf initial > {tmp}/initial-native-ready"
        text(native_seed); xdo("key", "Return")
        harness.wait_for(lambda: read("initial-native-ready"), "native launch prompt")
        assert read("initial-native-prompt") == "LEFT[0]\n> "
        harness.wait_for(lambda: "ready" in state(), "ready before enabling Composer")
        xdo("key", "ctrl+shift+m"); time.sleep(.12)
        # Clicking output must not turn accidental text input into native
        # shell source. All three insertion paths edit the Composer instead.
        for mode in ("typing", "clipboard", "primary"):
            marker = f"guard-{mode}"
            source = f"printf guarded > {tmp}/{marker}"
            owner = None
            if mode != "typing":
                payload = tmp / "guard-payload"
                payload.write_text(source)
                args = [sys.executable, str(HERE / "clipboard.py"), str(payload)]
                if mode == "primary": args.append("--primary")
                owner = subprocess.Popen(args, env=env, stdout=subprocess.PIPE, text=True)
                assert select.select([owner.stdout], [], [], 4)[0]
                assert owner.stdout.readline().strip() == "ready"
            try:
                xdo("mousemove", "--window", wid, "350", "200", "click", "1")
                if mode == "typing": text(source)
                elif mode == "clipboard": xdo("key", "ctrl+shift+v")
                else: xdo("click", "2")
                time.sleep(.08)
                assert not read(marker), "Insertion must not execute"
                xdo("key", "ctrl+a", "ctrl+shift+c")
                copied = subprocess.check_output([sys.executable, str(HERE / "clipboard.py"), "--read"], env=env, text=True, timeout=4)
                assert copied == source, (mode, copied, source)
                xdo("key", "Right", "Return")
                try:
                    harness.wait_for(lambda: read(marker) == "guarded", marker)
                except AssertionError:
                    subprocess.run(["import", "-window", wid, "/tmp/shadow-input-failure.png"], env=env, timeout=4)
                    raise
                harness.wait_for(lambda: "ready" in state(), "ready after guard test")
            finally:
                if owner:
                    owner.terminate(); owner.wait(timeout=3)
        command(f"fish_prompt > {tmp}/hidden-prompt; fish_right_prompt > {tmp}/hidden-right; printf checked > {tmp}/hidden-ready", "hidden-ready")
        assert read("hidden-prompt") == "" and read("hidden-right") == ""
        xdo("key", "ctrl+shift+m")
        time.sleep(0.12)
        text(f"false; fish_prompt > {tmp}/native-prompt; fish_right_prompt > {tmp}/native-right; printf checked > {tmp}/native-ready")
        xdo("key", "Return")
        harness.wait_for(lambda: read("native-ready"), "native prompt restoration")
        assert read("native-prompt") == "LEFT[1]\n> ", repr(read("native-prompt"))
        assert read("native-right") == "RIGHT"
        xdo("key", "ctrl+shift+m")
        time.sleep(0.12)
        history_seed = f"printf history > {tmp}/history-seed"
        command(history_seed, "history-seed")
        xdo("key", "Up", "ctrl+a", "ctrl+shift+c")
        copied = subprocess.check_output([sys.executable, str(HERE / "clipboard.py"), "--read"], env=env, text=True, timeout=4)
        assert copied == history_seed, (copied, history_seed)
        xdo("key", "Right", "Down")
        text(f"fish_prompt > {tmp}/initial-")
        xdo("key", "Up", "ctrl+a", "ctrl+shift+c")
        copied = subprocess.check_output([sys.executable, str(HERE / "clipboard.py"), "--read"], env=env, text=True, timeout=4)
        assert copied == native_seed, (copied, native_seed)
        xdo("key", "Right", "Down", "ctrl+a", "BackSpace")
        xdo("key", "F1")
        help_window = harness.wait_for(lambda: xdo("search", "--onlyvisible", "--name", "^Keyboard Shortcuts$", check=False), "shortcut discovery")
        xdo("windowfocus", "--sync", help_window.splitlines()[0])
        xdo("key", "Escape")
        harness.wait_for(lambda: not xdo("search", "--onlyvisible", "--name", "^Keyboard Shortcuts$", check=False), "shortcut dismissal")
        xdo("windowfocus", "--sync", wid)
        command(f"printf normal > {tmp}/normal", "normal")
        # Native fish syntax, redirection, pipelines and shell state survive.
        command(f"printf lower | string upper > {tmp}/pipeline", "pipeline")
        assert read("pipeline") == "LOWER"
        command(f"false; printf '%s' $status > {tmp}/status", "status")
        assert read("status") == "1"
        text("false")
        xdo("key", "Return")
        time.sleep(0.15)
        command(f"printf '%s' $status > {tmp}/prior-status", "prior-status")
        assert read("prior-status") == "1", read("prior-status")
        # Record only the prompt fields while exec preserves the helper's real
        # parent-shell authentication. All files and state stay in this fixture.
        recorder = tmp / "context-recorder.py"
        recorder.write_text(f"#!{sys.executable}\n" +
                            "import json, os, sys\n" +
                            "from pathlib import Path\n" +
                            f"path = Path({str(tmp / 'prompt-context.json')!r})\n" +
                            "if sys.argv[1] == 'context':\n" +
                            " path.with_suffix('.pending').write_text(json.dumps(sys.argv[2:]))\n" +
                            " os.replace(path.with_suffix('.pending'), path)\n" +
                            f"os.execv({str(harness.ROOT / 'build/vcom-shell')!r}, ['vcom-shell', *sys.argv[1:]])\n")
        recorder.chmod(0o700)

        def prompt_fields():
            path = tmp / "prompt-context.json"
            return json.loads(path.read_text()) if path.exists() else None

        environment_fixture = tmp / "context-env.fish"
        environment_fixture.write_text(f"set -gx VIRTUAL_ENV '{tmp}/日本語'\n"
                                       "set -gx CONDA_DEFAULT_ENV science\nset -gx SSH_TTY fixture\n")
        command(f"set -g __vcom_test_helper $SHADOW_TERM_HELPER; set -gx SHADOW_TERM_HELPER {recorder}; "
                f"source {environment_fixture}; "
                f"printf configured > {tmp}/context-ready", "context-ready")
        fields = harness.wait_for(lambda: prompt_fields(), "live prompt context snapshot")
        harness.wait_for(lambda: "ready" in state(), "ready after context snapshot")
        assert fields[0] == "1" and fields[1] == "0" and fields[4] == f"{tmp}/日本語"
        assert fields[5] == "science" and fields[6] == "1" and fields[8] and fields[9], fields
        command(f'command "$SHADOW_TERM_HELPER" context 1 0 0 100 "" "" 0 0 fixture host; '
                f"printf '%s' $status > {tmp}/context-bridge-ack", "context-bridge-ack")
        assert read("context-bridge-ack") == "0", "Real prompt helper must accept the authenticated context method"
        text("false | true")
        xdo("key", "Return")
        harness.wait_for(lambda: (prompt_fields() or [None] * 10)[2] == "1,0", "pipeline statuses captured before helpers")
        harness.wait_for(lambda: "ready" in state(), "ready after pipeline snapshot")
        assert prompt_fields()[1] == "0"
        xdo("key", "ctrl+shift+m")
        time.sleep(0.12)
        xdo("key", "ctrl+shift+m")
        time.sleep(0.12)
        assert prompt_fields()[2] == "1,0", "Prompt redraw must retain the last command's pipeline"
        text("sleep 1.1")
        xdo("key", "Return")
        harness.wait_for(lambda: int((prompt_fields() or [None, None, None, "0"])[3]) >= 1000, "command duration")
        harness.wait_for(lambda: "ready" in state(), "ready after duration snapshot")
        text("sleep 30 &")
        xdo("key", "Return")
        harness.wait_for(lambda: (prompt_fields() or [None] * 10)[7] == "1", "background job count")
        harness.wait_for(lambda: "ready" in state(), "ready after jobs snapshot")
        command(f"kill $last_pid; set -e VIRTUAL_ENV CONDA_DEFAULT_ENV SSH_TTY; printf cleared > {tmp}/context-cleared", "context-cleared")
        harness.wait_for(lambda: prompt_fields()[4:8] == ["", "", "0", "0"], "deactivated environments and completed job")
        command(f"set -gx SHADOW_TERM_HELPER $__vcom_test_helper; printf restored > {tmp}/context-helper-restored", "context-helper-restored")
        # Composer queries live completion definitions without invoking native input.
        command(f"complete -c printf -f -a 'vcomtag' ; abbr -a vcomsay printf; printf configured > {tmp}/services-ready", "services-ready")
        text("printf vcomt")
        xdo("key", "Tab")
        time.sleep(0.18)
        text(f" > {tmp}/live-completion")
        xdo("key", "Return")
        harness.wait_for(lambda: read("live-completion") == "vcomtag", "live completion definition and unique Tab")
        harness.wait_for(lambda: "ready" in state(), "ready after live completion")
        text("vcomsay")
        xdo("key", "space")
        text(f"abbreviated > {tmp}/abbr-result")
        xdo("key", "Return")
        harness.wait_for(lambda: read("abbr-result") == "abbreviated", "live abbreviation expansion")
        harness.wait_for(lambda: "ready" in state(), "ready after abbreviation")
        # Enter accepts a suggestion as an edit; it must not run it immediately.
        text("strin")
        xdo("key", "ctrl+space")
        time.sleep(0.15)
        xdo("key", "Return")
        text(f" upper -- completion > {tmp}/completion")
        xdo("key", "Return")
        harness.wait_for(lambda: read("completion").strip() == "COMPLETION", "builtin completion insertion")
        harness.wait_for(lambda: "ready" in state(), "ready after completion")
        filename = "vcomfixture 'quote\\ 日本.txt"
        (tmp / filename).write_text("filename completion\n")
        text("cat ./vcomfi")
        xdo("key", "ctrl+space")
        time.sleep(0.15)
        xdo("key", "Tab")
        text(f" > {tmp}/file-completion")
        xdo("key", "Return")
        harness.wait_for(lambda: read("file-completion") == "filename completion\n", "quoted filename completion")
        harness.wait_for(lambda: "ready" in state(), "ready after filename completion")
        capture = tmp / "capture.py"
        capture.write_text("import json,sys\nfrom pathlib import Path\n"
                           f"Path({str(tmp / 'argv')!r}).write_text(json.dumps(sys.argv[1:]))\n")
        source = f"python3 {capture} '日本語 e\u0301' 'literal $value' 'first\nsecond\n'\n\n"
        payload = tmp / "clipboard-source"
        payload.write_text(source)
        clipboard = subprocess.Popen([sys.executable, str(HERE / "clipboard.py"), str(payload)],
                                     env=env, stdout=subprocess.PIPE, text=True)
        try:
            assert select.select([clipboard.stdout], [], [], 4)[0], "clipboard ownership"
            assert clipboard.stdout.readline().strip() == "ready"
            xdo("key", "ctrl+v")
            time.sleep(0.1)
            xdo("key", "ctrl+Return")
            harness.wait_for(lambda: read("argv"), "Unicode and newline argv")
        finally:
            clipboard.terminate()
            clipboard.wait(timeout=3)
        assert json.loads(read("argv")) == ["日本語 e\u0301", "literal $value", "first\nsecond\n"], read("argv")
        time.sleep(0.1)
        # Incomplete Enter keeps the draft and adds a line, as fish would.
        text("for value in one two")
        xdo("key", "Return")
        time.sleep(0.15)
        text(f"printf '%s\\n' $value >> {tmp}/loop")
        xdo("key", "shift+Return")
        text("end")
        xdo("key", "ctrl+Return")
        harness.wait_for(lambda: read("loop") == "one\ntwo\n", "multiline loop")
        time.sleep(0.1)
        # Recall proves Pane retained exact accepted input for re-editing.
        xdo("key", "ctrl+shift+l")
        xdo("key", "ctrl+Return")
        harness.wait_for(lambda: read("loop") == "one\ntwo\none\ntwo\n", "accepted-source recall")
        time.sleep(0.1)
        # A partial native line must not be prefixed to a Composer submission.
        xdo("key", "ctrl+shift+m")
        text("KEEP_NATIVE_PREFIX ")
        xdo("key", "ctrl+shift+m")
        text(f"printf safe > {tmp}/guarded")
        xdo("key", "Return")
        time.sleep(0.15)
        assert not (tmp / "guarded").exists()
        xdo("key", "ctrl+shift+m", "ctrl+u", "ctrl+shift+m", "ctrl+Return")
        harness.wait_for(lambda: read("guarded") == "safe", "native-buffer guard retry")
        time.sleep(0.1)
        # A foreground program receives ordinary terminal input and EOF.
        text(f"cat > {tmp}/program-input")
        xdo("key", "Return")
        time.sleep(0.15)
        text("ordinary program input")
        xdo("key", "Return", "ctrl+d")
        harness.wait_for(lambda: read("program-input") == "ordinary program input\n", "raw program input")
        time.sleep(0.1)
        command(f"printf restored > {tmp}/after-program", "after-program")
        # Ordinary readers receive Send + Return, without another terminal
        # keypress, shell abbreviation expansion, or a change of editor mode.
        text(f"begin; read --prompt 'printf reader' --local vcom_reader_line; printf '%s\\n' \"$vcom_reader_line\" > {tmp}/program-composer-input; read --prompt 'printf again' --local vcom_reader_next; printf '%s\\n' \"$vcom_reader_next\" > {tmp}/program-composer-next; end")
        xdo("key", "Return")
        time.sleep(0.15)
        # Runtime-enabled Composer retains focus across command execution.
        text("vcomsay literal $value; program text")
        xdo("key", "Return")
        harness.wait_for(lambda: read("program-composer-input") == "vcomsay literal $value; program text\n", "foreground Composer Enter without abbreviation expansion")
        text("second answer")
        xdo("key", "ctrl+Return")
        harness.wait_for(lambda: read("program-composer-next") == "second answer\n", "foreground Composer clears draft and retains focus")
        harness.wait_for(lambda: "ready" in state(), "ready after foreground Composer")
        # A nested fish has no integration hooks and keeps ordinary input.
        text("fish --no-config")
        xdo("key", "Return")
        time.sleep(0.15)
        command_text = f"printf nested > {tmp}/nested"
        text(command_text)
        xdo("key", "Return")
        harness.wait_for(lambda: read("nested") == "nested", "nested native fish")
        text("exit")
        xdo("key", "Return")
        time.sleep(0.15)
        command(f"printf outer > {tmp}/outer", "outer")
        command(f"cd {tmp}; pwd > {tmp}/cwd-composer", "cwd-composer")
        assert read("cwd-composer").strip() == str(tmp)
        # Ctrl+C still interrupts a foreground job, then restores Composer.
        text(f"sh -c 'echo $$ > {tmp}/interrupt-pid; exec sleep 30'")
        xdo("key", "Return")
        harness.wait_for(lambda: read("interrupt-pid"), "interruptible foreground job")
        xdo("key", "ctrl+c")
        time.sleep(0.1)
        command(f"printf interrupted > {tmp}/interrupted", "interrupted")
        # Delay only this shell's binding to make pending-state races observable.
        delayed = tmp / "delayed.fish"
        delayed.write_text("functions --copy __vcom_submit __vcom_original\n"
                           "set --global VCOM_TEST_DELAY 0.6\n"
                           "function __vcom_submit\n"
                           "    sleep $VCOM_TEST_DELAY\n"
                           "    __vcom_original\n"
                           "end\n")
        command(f"source {delayed}; printf configured > {tmp}/delayed", "delayed")
        text(f"printf accepted > {tmp}/pending-original")
        xdo("key", "Return", "ctrl+a")
        text(f"printf newer > {tmp}/newer-draft")
        harness.wait_for(lambda: read("pending-original"), "delayed acceptance")
        harness.wait_for(lambda: "ready" in state(), "ready after delayed acceptance")
        # An acknowledgement must not clear a draft edited while it was pending.
        xdo("key", "Return")
        harness.wait_for(lambda: read("newer-draft") == "newer", "concurrent draft retention")
        harness.wait_for(lambda: "ready" in state(), "ready after retained draft")
        text(f"printf retry > {tmp}/cancelled")
        xdo("key", "Return", "Escape")
        time.sleep(0.8)
        assert not (tmp / "cancelled").exists(), "cancelled request executed"
        xdo("key", "Return")
        harness.wait_for(lambda: read("cancelled") == "retry", "cancelled draft retry")
        harness.wait_for(lambda: "ready" in state(), "ready after cancellation retry")
        command(f"set --global VCOM_TEST_DELAY 3.3; printf configured > {tmp}/slow", "slow")
        text(f"printf retry > {tmp}/expired")
        xdo("key", "Return")
        harness.wait_for(lambda: "pending" in state(), "pending slow submission")
        harness.wait_for(lambda: "ready" in state(), "submission timeout")
        time.sleep(0.5)
        assert not (tmp / "expired").exists(), "expired request executed"
        # Recover through the native editor; the expired Composer draft survives.
        xdo("key", "ctrl+shift+m")
        text("set --global VCOM_TEST_DELAY 0.05")
        xdo("key", "Return")
        time.sleep(0.1)
        xdo("key", "ctrl+shift+m", "Return")
        harness.wait_for(lambda: read("expired") == "retry", "expired draft retry")
        harness.wait_for(lambda: "ready" in state(), "ready before search")
        command(f"printf 'FIND-TOKEN[one]\\n'; printf ready > {tmp}/search-ready", "search-ready")
        xdo("key", "ctrl+shift+f")
        text("FIND-TOKEN[one]")
        xdo("key", "Return", "ctrl+shift+c")
        selected = subprocess.check_output([sys.executable, str(HERE / "clipboard.py"), "--read"],
                                           env=env, text=True, timeout=4)
        assert selected == "FIND-TOKEN[one]", selected
        xdo("key", "Escape", "ctrl+comma")
        prefs = harness.wait_for(lambda: xdo("search", "--onlyvisible", "--name", "^Preferences$", check=False), "preferences window")
        xdo("windowfocus", "--sync", prefs.splitlines()[0])
        xdo("key", "Escape")
        harness.wait_for(lambda: not xdo("search", "--onlyvisible", "--name", "^Preferences$", check=False), "preferences dismissal")
        xdo("windowfocus", "--sync", wid)
        # The palette filters UI actions; its query is never shell input.
        xdo("key", "ctrl+shift+p")
        palette = harness.wait_for(lambda: xdo("search", "--onlyvisible", "--name", "^Command Palette$", check=False), "command palette")
        xdo("windowfocus", "--sync", palette.splitlines()[0])
        text("keyboard shortcuts")
        xdo("key", "Return")
        help_window = harness.wait_for(lambda: xdo("search", "--onlyvisible", "--name", "^Keyboard Shortcuts$", check=False), "palette activation")
        xdo("windowfocus", "--sync", help_window.splitlines()[0])
        xdo("key", "Escape")
        xdo("windowfocus", "--sync", wid)
        time.sleep(0.08)
        # Ctrl+N uses this window's initial directory; Ctrl+T uses the current one.
        (tmp / "subdirectory").mkdir()
        command(f"cd {tmp}/subdirectory; printf changed > {tmp}/tab-directory-ready", "tab-directory-ready")
        xdo("key", "ctrl+n")
        default_tab = harness.wait_for(new_tab, "default-directory tab")
        harness.wait_for(lambda: "ready" in state(default_tab), "default-directory tab readiness")
        command(f"pwd > {tmp}/default-tab-cwd", "default-tab-cwd")
        assert read("default-tab-cwd").strip() == str(tmp)
        xdo("key", "ctrl+w")
        harness.wait_for(lambda: default_tab not in subprocess.check_output([binary, "--list"], env=env, text=True), "default tab close")
        text(f"printf retained > {tmp}/tab-draft")
        before = subprocess.check_output([binary, "--list"], env=env, text=True)
        xdo("key", "ctrl+t")
        tab = harness.wait_for(new_tab, "new tab session")
        harness.wait_for(lambda: "ready" in state(tab), "new tab readiness")
        windows = xdo("search", "--onlyvisible", "--name", " · (composer|tab-[0-9a-f]+)$", check=False).splitlines()
        assert windows == [wid], windows
        command(f"pwd > {tmp}/current-tab-cwd; printf separate > {tmp}/tab-command", "tab-command")
        assert read("current-tab-cwd").strip() == str(tmp / "subdirectory")
        xdo("key", "ctrl+w")
        harness.wait_for(lambda: tab not in subprocess.check_output([binary, "--list"], env=env, text=True), "tab cleanup")
        xdo("key", "Return")
        harness.wait_for(lambda: read("tab-draft") == "retained", "per-tab draft preservation")
        assert subprocess.check_output([binary, "--list"], env=env, text=True).split("\t")[-1] == before.split("\t")[-1]
        xdo("key", "ctrl+shift+t")
        tab = harness.wait_for(new_tab, "second tab session")
        harness.wait_for(lambda: "ready" in state(tab), "second tab readiness")
        xdo("key", "ctrl+Page_Up")
        harness.wait_for(visible, "previous tab shortcut")
        xdo("key", "ctrl+Page_Down")
        harness.wait_for(lambda: xdo("search", "--onlyvisible", "--name", " · " + tab + "$", check=False), "next tab shortcut")
        # Split moves and detaches retain process identity and exact drafts.
        xdo("key", "ctrl+w")
        harness.wait_for(lambda: tab not in subprocess.check_output([binary, "--list"], env=env, text=True), "close spare tab")
        root_pid = int(subprocess.check_output([binary, "--list"], env=env, text=True).split("\t")[2])
        text(f"printf root > {tmp}/split-root-draft")
        xdo("key", "ctrl+shift+e")
        def pane_session():
            rows = subprocess.check_output([binary, "--list"], env=env, text=True).splitlines()
            return next((row.split("\t")[0] for row in rows if row.startswith("pane-")), None)
        pane = harness.wait_for(pane_session, "split session")
        harness.wait_for(lambda: "ready" in state(pane), "split readiness")
        listing = subprocess.check_output([binary, "--list"], env=env, text=True)
        assert listing.count("\tvisible\t") == 2, listing
        pane_pid = next(int(row.split("\t")[2]) for row in listing.splitlines() if row.startswith(pane + "\t"))
        command(f"pwd > {tmp}/split-cwd", "split-cwd")
        assert read("split-cwd").strip() == str(tmp / "subdirectory")
        text(f"printf pane > {tmp}/split-pane-draft")
        xdo("key", "ctrl+alt+Left", "Return")
        harness.wait_for(lambda: read("split-root-draft") == "root", "original split draft retained")
        harness.wait_for(lambda: "ready" in state(), "root ready after split command")
        xdo("key", "ctrl+alt+Right")
        def palette_action(label):
            xdo("key", "ctrl+shift+p")
            popup = harness.wait_for(lambda: xdo("search", "--onlyvisible", "--name", "^Command Palette$", check=False), "layout action palette")
            xdo("windowfocus", "--sync", popup.splitlines()[0]); text(label); xdo("key", "Return"); time.sleep(.1)
        palette_action("Move Pane to New Tab")
        listing = subprocess.check_output([binary, "--list"], env=env, text=True)
        assert listing.count("\tvisible\t") == 1, listing
        palette_action("Move Pane to New Window")
        detached = harness.wait_for(lambda: xdo("search", "--onlyvisible", "--name", " · " + pane + "$", check=False), "detached pane window").splitlines()[0]
        assert detached != wid
        xdo("windowfocus", "--sync", detached)
        listing = subprocess.check_output([binary, "--list"], env=env, text=True)
        assert next(int(row.split("\t")[2]) for row in listing.splitlines() if row.startswith(pane + "\t")) == pane_pid
        assert next(int(row.split("\t")[2]) for row in listing.splitlines() if row.startswith("composer\t")) == root_pid
        xdo("key", "Return")
        harness.wait_for(lambda: read("split-pane-draft") == "pane", "draft survives tab and window transfer")
        harness.wait_for(lambda: "ready" in state(pane), "detached prompt ready")
        xdo("key", "ctrl+shift+q")
        harness.wait_for(lambda: not Path(f"/proc/{pane_pid}").exists(), "detached child cleanup")
        assert Path(f"/proc/{root_pid}").exists() and app.poll() is None
        xdo("windowfocus", "--sync", wid)
        children = [int(row.split("\t")[2]) for row in subprocess.check_output([binary, "--list"], env=env, text=True).splitlines()]
        xdo("key", "ctrl+shift+q")
        app.wait(timeout=5)
        assert all(not Path(f"/proc/{pid}").exists() for pid in children), "Window close must reap every tab's shell"
        logs.flush()
        data = (tmp / "frontend.log").read_text(errors="replace")
        assert "CRITICAL" not in data and "ERROR **" not in data, data
        print("PASS: Composer fish input, completions, Unicode/multiline argv, status, recall, native-buffer guard, foreground input/interrupt, nested fish, cwd, concurrent drafts, cancellation/timeout, search, preferences, command palette, independent tabs, tab cycling, history, runtime prompt activation, split transfers and window cleanup")
    except Exception as error:
        if visible():
            subprocess.run(["import", "-display", env["DISPLAY"], "-window", visible().splitlines()[0],
                            "/tmp/vcom-fish-failure.png"], timeout=4, check=False)
        raise AssertionError(f"{error}; shell state {state()}; prompt {prompt_fields() if (tmp / 'prompt-context.json').exists() else None}") from error
    finally:
        if app.poll() is None:
            listing = subprocess.run([binary, "--list"], env=env, timeout=4, capture_output=True, text=True)
            for row in listing.stdout.splitlines():
                subprocess.run([binary, "--session", row.split("\t")[0], "--quit"], env=env, timeout=4,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            app.wait(timeout=5)
        logs.close()


if __name__ == "__main__":
    raise SystemExit("Run python3 tests/integration.py --frontend")
