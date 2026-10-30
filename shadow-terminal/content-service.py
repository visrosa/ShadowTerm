#!/usr/bin/env python3
"""Bounded, headless content services. Requests are data, never shell programs."""
import argparse
import json
import os
from pathlib import Path
import re
import selectors
import shlex
import stat
import subprocess
import sys
import time
import unicodedata

LIMIT = 48 * 1024


def literal(word):
    # Fish single quotes escape only apostrophe/backslash; shlex handles the
    # common unquoted/double-quoted subset after that spelling is normalized.
    if word.startswith("'") and word.endswith("'"):
        return word[1:-1].replace("\\'", "'").replace("\\\\", "\\")
    try:
        parts = shlex.split(word)
        return parts[0] if len(parts) == 1 else word
    except ValueError:
        return word.strip("'\"")


def lookup(source, cursor, selection=""):
    """Lex only command scope; never expand or evaluate a token.

    Scopes retain their own quote and process state. An unfinished substitution
    is still a scope. Parenthesis bytes inside single quotes or escapes are data.
    """
    if len(source.encode()) > 65536 or not 0 <= cursor <= len(source):
        raise ValueError("Invalid source/cursor")
    scopes = [{"start": 0, "end": len(source), "tokens": [], "breaks": []}]
    stack = [(0, "")]
    quote = ""
    escaped = False
    token_start = None

    def flush(end):
        nonlocal token_start
        if token_start is not None:
            scopes[stack[-1][0]]["tokens"].append((token_start, end, source[token_start:end]))
            token_start = None

    i = 0
    while i < len(source):
        c = source[i]
        if escaped:
            escaped = False
            i += 1
            continue
        if c == "\\" and quote != "'":
            if token_start is None:
                token_start = i
            escaped = True
        elif c == "\\" and quote == "'" and i + 1 < len(source) and source[i + 1] in "'\\":
            escaped = True
        elif c == "'" and quote != '"':
            if token_start is None:
                token_start = i
            quote = "" if quote else "'"
        elif c == '"' and quote != "'":
            if token_start is None:
                token_start = i
            quote = "" if quote else '"'
        elif c == "(" and (not quote or quote == '"' and i > 0 and source[i - 1] == "$"):
            flush(i)
            scopes.append({"start": i + 1, "end": len(source), "tokens": [], "breaks": []})
            stack.append((len(scopes) - 1, quote))
            quote = ""
        elif c == ")" and not quote and len(stack) > 1:
            flush(i)
            scopes[stack[-1][0]]["end"] = i
            _, quote = stack.pop()
        elif not quote and c == "#" and token_start is None:
            end = source.find("\n", i)
            i = len(source) if end < 0 else end
            continue
        elif not quote and (c.isspace() or c in "|;&<>"):
            flush(i)
            if c in "|;&\n":
                scopes[stack[-1][0]]["breaks"].append(i)
        elif token_start is None:
            token_start = i
        i += 1
    flush(len(source))
    scope = max((s for s in scopes if s["start"] <= cursor <= s["end"]), key=lambda s: s["start"])
    left = max([scope["start"] - 1] + [b for b in scope["breaks"] if b < cursor])
    right = min([scope["end"] + 1] + [b for b in scope["breaks"] if b >= cursor])
    words = [(a, b, literal(w)) for a, b, w in scope["tokens"] if left < a < right]
    while words and (words[0][2] in {"command", "builtin", "exec", "not", "and", "or", "sudo", "env"} or re.match(r"^[A-Za-z_][A-Za-z_0-9]*=", words[0][2])):
        words.pop(0)
    command = Path(words[0][2]).name if words else ""
    token = next((w for a, b, w in words if a <= cursor <= b), "")
    subcommand = words[1][2] if len(words) > 1 and re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", words[1][2]) else ""
    query = selection.strip() or command
    # Options are documented by their owning command; explicit arbitrary
    # selections remain literal queries rather than executable expressions.
    if selection.strip().startswith("-"):
        query = command
    return {"command": command, "token": token, "query": query, "subcommand": subcommand,
            "selection": selection, "words": [w for _, _, w in words], "scope": [scope["start"], scope["end"]]}


def clean(text):
    text = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\|$)", "", text)
    text = re.sub(r".\x08", "", text)
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    return "".join(c for c in text if c in "\n\t" or ord(c) >= 32 and ord(c) != 127)


def run(argv, cwd=None, extra_env=None, binary=False, with_title=False):
    if not argv or any(not isinstance(a, str) or "\0" in a for a in argv):
        raise ValueError("Provider argv must contain literal strings")
    env = os.environ | {"PAGER": "cat", "MANPAGER": "cat", "MANWIDTH": "100", "TERM": "dumb", "NO_COLOR": "1"}
    for key, value in (extra_env or {}).items():
        if value is None:
            env.pop(key, None)
        else:
            env[key] = value
    with subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as proc:
        data = bytearray()
        truncated = False
        try:
            with selectors.DefaultSelector() as poll:
                poll.register(proc.stdout, selectors.EVENT_READ)
                deadline = time.monotonic() + .85
                while True:
                    remain = deadline - time.monotonic()
                    if remain <= 0:
                        raise TimeoutError("Documentation/preview provider timed out")
                    if not poll.select(remain):
                        raise TimeoutError("Documentation/preview provider timed out")
                    chunk = os.read(proc.stdout.fileno(), 4096)
                    if not chunk:
                        break
                    data.extend(chunk)
                    if len(data) > LIMIT:
                        truncated = True
                        break
            if truncated:
                proc.kill()
            code = proc.wait(timeout=max(.05, deadline - time.monotonic()))
            if binary:
                if truncated or code:
                    raise ValueError("Context provider failed or exceeded the output limit")
                return bytes(data)
            raw = bytes(data[:LIMIT]).decode("utf-8", "replace")
            titles = re.findall(r"\x1b\][02];([^\x07\x1b]*)(?:\x07|\x1b\\)", raw)
            title = "".join(c for c in titles[-1] if not unicodedata.category(c).startswith("C"))[:160] if titles else ""
            text = clean(raw)
            if code and not truncated:
                raise ValueError(text.strip() or f"Provider exited {code}")
            text += "\n[Preview truncated]" if truncated else ""
            return {"text": text, "title": title} if with_title else text
        except subprocess.TimeoutExpired as error:
            raise TimeoutError("Documentation/preview provider timed out") from error
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()


def preview(value, cwd):
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = Path(cwd) / path
    # No FIFO/device opens or recursive traversal. O_NONBLOCK also protects
    # the race between checking a regular file and opening a replacement FIFO.
    info = path.stat()
    if stat.S_ISDIR(info.st_mode):
        entries = []
        with os.scandir(path) as scan:
            for item in scan:
                entries.append(item.name + ("/" if item.is_dir(follow_symlinks=False) else ""))
                if len(entries) >= 128:
                    entries.append("[Directory preview limited to 128 entries]")
                    break
        return clean(str(path) + "\n\n" + "\n".join(sorted(entries)))[:LIMIT]
    if not stat.S_ISREG(info.st_mode):
        return "Preview unavailable for special files"
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return "Preview unavailable for special files"
        data = os.read(fd, LIMIT + 1)
    finally:
        os.close(fd)
    if b"\0" in data:
        return "Binary file · " + str(info.st_size) + " bytes"
    return clean(data[:LIMIT].decode("utf-8", "replace")) + ("\n[Preview truncated]" if len(data) > LIMIT else "")


def sources(config):
    default = [{"name": "Manual", "argv": ["man", "--", "{query}"]},
               {"name": "Examples", "argv": ["tldr", "--offline", "--", "{query}"]},
               {"name": "Info", "argv": ["info", "--output=-", "--", "{query}"]}]
    if config and Path(config).exists():
        with Path(config).open("rb") as stream:
            raw = stream.read(128 * 1024 + 1)
        if len(raw) > 128 * 1024:
            raise ValueError("Documentation configuration exceeds 128 KiB")
        default = json.loads(raw)["sources"]
    if not isinstance(default, list) or not 1 <= len(default) <= 12:
        raise ValueError("Configure between 1 and 12 documentation sources")
    for item in default:
        if not isinstance(item, dict) or set(item) - {"name", "argv"}:
            raise ValueError("Documentation sources support name and argv fields")
        if not isinstance(item.get("name"), str) or not 1 <= len(item["name"]) <= 80 or not isinstance(item.get("argv"), list) or not 1 <= len(item["argv"]) <= 64:
            raise ValueError("Each source needs a short name and nonempty literal argv")
        if any(not isinstance(arg, str) or "\0" in arg for arg in item["argv"]):
            raise ValueError("Documentation argv must contain literal strings")
    return default


def respond(request):
    kind = request["kind"]
    if kind == "lookup":
        return lookup(request["source"], request["cursor"], request.get("selection", ""))
    if kind == "complete":
        import importlib.util
        spec = importlib.util.spec_from_file_location("completion_definitions", Path(__file__).with_name("completion-definitions.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.complete(request["context"], request["config"])
    if kind in ("context-directory", "context-git"):
        import importlib.util
        spec = importlib.util.spec_from_file_location("context_details", Path(__file__).with_name("context-details.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        provider = module.directory_details if kind == "context-directory" else module.git_details
        result = (provider(request["cwd"], run, request["scratch"]) if kind == "context-directory"
                  else provider(request["cwd"], run))
        # Bound the serialized result as well as subprocess output. Long names
        # can otherwise amplify a bounded raw response through JSON escaping.
        while len(json.dumps(result, ensure_ascii=False).encode()) > 40000:
            for field in ("files", "branches", "entries"):
                if result.get(field):
                    result[field].pop()
                    result["truncated"] = True
                    break
            else:
                raise ValueError("Context metadata exceeds the display limit")
        return result
    if kind == "sources":
        return sources(request.get("config"))
    if kind == "preview":
        if request.get("preview_kind") == "git" and request["value"] and not request["value"].startswith("-"):
            try:
                return run(["git", "--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "log.showSignature=false", "--no-pager", "show", "--no-ext-diff", "--no-textconv", "--format=fuller", "--stat", request["value"], "--"], request["cwd"])
            except (ValueError, OSError):
                pass
        try:
            return preview(request["value"], request["cwd"])
        except FileNotFoundError:
            return "No local file preview · " + request.get("description", "")
    if kind == "document":
        context = request["context"]
        query = context["query"]
        if not query or "\0" in query:
            text = "No documentation query at the caret"
            return {"text": text, "title": ""} if request.get("with_title") else text
        spec = sources(request.get("config"))[request["index"]]
        queries = [query]
        if not context.get("selection") and context.get("subcommand"):
            queries.insert(0, context["command"] + "-" + context["subcommand"])
        failure = None
        for query in queries:
            values = context | {"query": query}
            argv = [re.sub(r"\{(query|command|token|subcommand)\}", lambda m: values.get(m[1], ""), arg) for arg in spec["argv"]]
            try:
                extra_env = {}
                if spec["argv"][0] == "man":
                    # Match fish's manual precedence without sourcing the user's
                    # interactive configuration or executing the draft.
                    try:
                        fish_man = run(["fish", "--no-config", "-c", "printf %s $__fish_man_dir"]).strip()
                        if fish_man:
                            extra_env["MANPATH"] = fish_man + ":" + os.environ.get("MANPATH", "")
                    except (OSError, ValueError, TimeoutError):
                        pass
                return run(argv, request.get("cwd"), extra_env, with_title=request.get("with_title", False))
            except (ValueError, FileNotFoundError) as error:
                failure = error
        raise ValueError(str(failure))
    raise ValueError("Unknown content request")


def main():
    try:
        raw = sys.stdin.buffer.read(1024 * 1024 + 1)
        if len(raw) > 1024 * 1024:
            raise ValueError("Content request exceeds 1 MiB")
        request = json.loads(raw)
        print(json.dumps({"result": respond(request)}, ensure_ascii=False))
    except (OSError, ValueError, KeyError, TypeError, TimeoutError, IndexError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
