#!/usr/bin/env python3
"""Exercise a disposable fish reader hook with a fake editing peer and private PTY."""
import argparse
import contextlib
import errno
import os
from pathlib import Path
import pty
import select
import signal
import socket
import struct
import tempfile
import time

LIMIT = 1024 * 1024


def exact(peer, size):
    result = b""
    while len(result) < size:
        chunk = peer.recv(size - len(result))
        if not chunk:
            raise EOFError("Reader disconnected")
        result += chunk
    return result


def receive(peer):
    size, = struct.unpack("!I", exact(peer, 4))
    assert size <= LIMIT
    return exact(peer, size).decode("utf-8")


def send(peer, message):
    data = message.encode("utf-8")
    peer.sendall(struct.pack("!I", len(data)) + data)


class Probe:
    def __init__(self, binary, root):
        self.root = root
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(str(root / "reader.sock"))
        self.server.listen(4)
        self.server.settimeout(8)
        for name in ("config", "data", "cache", "state"):
            (root / name).mkdir()
        environment = os.environ | {
            "XDG_CONFIG_HOME": str(root / "config"), "XDG_DATA_HOME": str(root / "data"),
            "XDG_STATE_HOME": str(root / "state"), "XDG_CACHE_HOME": str(root / "cache"),
            "fish_history": "reader_probe", "TERM": "xterm-256color",
            "FISH_EXTERNAL_READER_PROBE": str(root / "reader.sock"),
        }
        self.pid, self.fd = pty.fork()
        if not self.pid:
            os.chdir(root)
            # This fish revision makes --no-config private. Enable persistence only
            # inside this disposable data directory, with a synthetic prompt.
            setup = "set -e fish_private_mode; function fish_prompt; printf 'probe> '; end; function fish_greeting; end"
            os.execve(binary, [str(binary), "--no-config", "--interactive", "-C", setup], environment)
        self.last_id = 0
        self.peer = None
        self.reaped = False
        self.output = b""

    def begin(self, kind="command"):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            self.drain()
            if select.select([self.server], [], [], 0.02)[0]:
                break
        else:
            raise AssertionError(f"No external read: {self.output!r}")
        self.peer, _ = self.server.accept()
        self.peer.settimeout(5)
        self._begin(kind)
        assert int(self.read_id) > self.last_id
        self.last_id = int(self.read_id)
        return self

    def _begin(self, kind):
        version, action, self.read_id, actual_kind, self.draft = receive(self.peer).split("\0", 4)
        assert (version, action, actual_kind) == ("v1", "begin", kind)

    def submit(self, source, result="accepted", kind="command"):
        send(self.peer, f"submit\0{self.read_id}\0{source}")
        assert receive(self.peer) == f"{result}\0{self.read_id}"
        if result == "accepted":
            self.peer.close()
            self.peer = None
        else:
            previous = self.read_id
            self._begin(kind)
            assert self.read_id == previous and self.draft == source

    def drain(self):
        while select.select([self.fd], [], [], 0)[0]:
            try:
                chunk = os.read(self.fd, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    return
                raise
            if not chunk:
                return
            self.output += chunk
            # Bound captures; only synthetic marker data belongs here.
            self.output = self.output[-1024 * 1024:]
            # Native reader fallback asks for cursor position.
            if b"\x1b[6n" in chunk:
                os.write(self.fd, b"\x1b[1;1R")
            if b"\x1b[0c" in chunk:
                os.write(self.fd, b"\x1b[?1;2c")

    def wait_file(self, name, expected):
        deadline = time.monotonic() + 5
        path = self.root / name
        while time.monotonic() < deadline:
            self.drain()
            if path.exists() and path.read_bytes() == expected:
                return
            time.sleep(0.01)
        raise AssertionError(f"Missing synthetic result {name}: {self.output!r}")

    def close(self):
        if self.peer:
            self.peer.close()
        self.server.close()
        if not self.reaped:
            with contextlib.suppress(ProcessLookupError):
                os.kill(self.pid, signal.SIGSTOP)
            def descendants(pid):
                try:
                    children = Path(f"/proc/{pid}/task/{pid}/children").read_text().split()
                except OSError:
                    return []
                result = []
                for child in map(int, children):
                    result.extend(descendants(child)); result.append(child)
                return result
            for child in descendants(self.pid):
                with contextlib.suppress(ProcessLookupError):
                    os.kill(child, signal.SIGKILL)
            with contextlib.suppress(ProcessLookupError):
                os.killpg(self.pid, signal.SIGKILL)
            with contextlib.suppress(ChildProcessError):
                os.waitpid(self.pid, 0)
        os.close(self.fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fish", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="shadowterm-reader-") as directory:
        root = Path(directory)
        fixture = Probe(args.fish.resolve(), root)
        try:
            # Values, functions and cwd survive in one real interactive shell.
            fixture.begin().submit("set -g probe_value persistent; function probe_function; printf '%s' $probe_value; end; mkdir child; cd child")
            fixture.begin().submit("probe_function > ../state-result; pwd > ../cwd-result")
            fixture.begin()
            fixture.wait_file("state-result", b"persistent")
            fixture.wait_file("cwd-result", str(root / "child").encode() + b"\n")
            fixture.submit("function source_capture --on-event fish_preexec; printf '%s' $argv[1] > ../source-result; end")
            fixture.begin().submit("if true", "incomplete")
            source = "if true\n printf '%s' 'λ 日本語 \uf600' > ../unicode-result\nend\n\n"
            fixture.submit(source)
            fixture.begin()
            fixture.wait_file("source-result", source.encode())
            fixture.wait_file("unicode-result", "λ 日本語 \uf600".encode())
            fixture.submit("")
            fixture.begin().submit("read --prompt-str 'literal> ' literal; printf '%s' $literal > ../literal-result")
            fixture.begin("literal").submit("literal (not executed) λ\n", kind="literal")
            fixture.begin()
            fixture.wait_file("literal-result", "literal (not executed) λ\n".encode())
            # Builtin interrupt returns to its caller; outer interrupt starts another read.
            fixture.submit("read --prompt-str 'cancel> ' cancelled; printf '%s' $status > ../cancel-result")
            fixture.begin("literal")
            send(fixture.peer, f"interrupt\0{fixture.read_id}")
            fixture.peer.close(); fixture.peer = None
            fixture.begin()
            fixture.wait_file("cancel-result", b"1")
            send(fixture.peer, f"interrupt\0{fixture.read_id}")
            fixture.peer.close(); fixture.peer = None
            fixture.begin().submit("printf '%s' $status > ../interrupt-result; sleep 0.05 &; wait; printf jobs-ok > ../jobs-result")
            fixture.begin()
            fixture.wait_file("interrupt-result", b"130")
            fixture.wait_file("jobs-result", b"jobs-ok")
            fixture.submit("read --prompt-str 'eof> ' missing; printf '%s' $status > ../literal-eof-result")
            fixture.begin("literal")
            send(fixture.peer, f"eof\0{fixture.read_id}")
            fixture.peer.close(); fixture.peer = None
            fixture.begin()
            fixture.wait_file("literal-eof-result", b"1")
            # Silent and character-limited reads stay in fish; no editor request.
            fixture.submit("read --silent --prompt-str '' secret; printf secret-ok > ../secret-result")
            time.sleep(0.1); fixture.drain()
            assert not select.select([fixture.server], [], [], 0)[0]
            os.write(fixture.fd, b"synthetic-private-value\r")
            fixture.begin()
            fixture.wait_file("secret-result", b"secret-ok")
            fixture.submit("read --nchars 1 --prompt-str '' char; printf '%s' $char > ../char-result")
            time.sleep(0.1); fixture.drain()
            assert not select.select([fixture.server], [], [], 0)[0]
            os.write(fixture.fd, b"q")
            fixture.begin()
            fixture.wait_file("char-result", b"q")
            fixture.submit("sleep 10 &; set -g probe_job $last_pid; fg")
            time.sleep(0.1); os.write(fixture.fd, b"\x1a")
            fixture.begin().submit("bg; kill -TERM $probe_job; wait; printf resumed > ../job-control-result")
            fixture.begin()
            fixture.wait_file("job-control-result", b"resumed")
            # Foreground unadapted input belongs to the PTY, not the shell reader.
            fixture.submit("python3 -c 'import sys; open(\"../foreground-result\",\"w\").write(input())'")
            time.sleep(0.1)
            os.write(fixture.fd, b"foreground-value\n")
            fixture.begin()
            fixture.wait_file("foreground-result", b"foreground-value")
            # Acknowledged native transfer retains source in the same process.
            send(fixture.peer, f"native\0{fixture.read_id}\0printf native-ok > ../native-result")
            assert receive(fixture.peer) == f"native\0{fixture.read_id}"
            fixture.peer.close(); fixture.peer = None
            time.sleep(0.1); fixture.drain(); os.write(fixture.fd, b"\r")
            fixture.begin()
            fixture.wait_file("native-result", b"native-ok")
            # Drop before submitting: native fallback executes only explicitly typed input.
            fixture.peer.close(); fixture.peer = None
            time.sleep(0.1); fixture.drain()
            os.write(fixture.fd, b"printf before-ok > ../before-result\r")
            fixture.begin()
            fixture.wait_file("before-result", b"before-ok")
            # Drop after submitting: unknown acknowledgement must never replay source.
            send(fixture.peer, f"submit\0{fixture.read_id}\0printf once >> ../once-result")
            fixture.peer.close(); fixture.peer = None
            fixture.begin()
            fixture.wait_file("once-result", b"once")
            fixture.submit("history --null > ../history-live; history save")
            fixture.begin()
            send(fixture.peer, f"eof\0{fixture.read_id}")
            fixture.peer.close(); fixture.peer = None
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                fixture.drain()
                pid, _ = os.waitpid(fixture.pid, os.WNOHANG)
                if pid:
                    fixture.reaped = True
                    break
                time.sleep(0.02)
            else:
                raise AssertionError("Shell did not exit")
            history = root / "data/fish/reader_probe_history"
            assert history.exists()
            assert history.read_text().count("- cmd: set -g probe_value") == 1
            assert (root / "history-live").read_bytes().count(b"set -g probe_value") == 1
            assert "synthetic-private-value" not in history.read_text()
            print("Reader probe passed: live state, exact source, incomplete/empty/nested reads, interrupt, jobs, foreground PTY, native transfer, disconnects, history")
        finally:
            fixture.close()


if __name__ == "__main__":
    main()
