"""Read-only context snapshots; operation preparation belongs to the host."""
import json
import os
from pathlib import Path
import shutil
import stat
import time


def directory_details(directory, run, scratch):
    root = Path(directory)
    if not root.is_absolute() or not root.is_dir():
        raise ValueError("Directory is unavailable")
    entries = []
    seen = {str(root)}
    budget = 18000
    truncated = False

    def add(group, path):
        nonlocal budget, truncated
        path = str(path)
        try:
            size = len(json.dumps(path, ensure_ascii=False).encode())
        except UnicodeEncodeError:
            truncated = True
            return
        if path in seen:
            return
        if size > budget:
            truncated = True
            return
        seen.add(path)
        budget -= size
        entries.append({"group": group, "path": path})

    parent = root.parent
    for _ in range(6):
        add("Parents", parent)
        if parent == parent.parent:
            break
        parent = parent.parent
    deadline = time.monotonic() + .15
    children = []
    with os.scandir(root) as scan:
        for index, entry in enumerate(scan):
            if index >= 512 or time.monotonic() > deadline:
                truncated = True
                break
            try:
                if entry.is_dir():
                    children.append(entry.path)
            except OSError:
                continue
    for child in sorted(children, key=str.casefold)[:32]:
        add("Children", child)
    truncated |= len(children) > 32
    frecency = "zoxide is unavailable"
    if shutil.which("zoxide"):
        try:
            database_dir = (Path(os.environ["_ZO_DATA_DIR"]) if "_ZO_DATA_DIR" in os.environ else
                            Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "zoxide")
            if not database_dir.is_absolute():
                raise ValueError("zoxide data directory must be absolute")
            fd = os.open(database_dir / "db.zo", os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
            with os.fdopen(fd, "rb") as source:
                metadata = os.fstat(source.fileno())
                if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 4 * 1024 * 1024:
                    raise ValueError("zoxide database exceeds the snapshot limit")
                data = source.read(4 * 1024 * 1024 + 1)
            if len(data) > 4 * 1024 * 1024:
                raise ValueError("zoxide database exceeds the snapshot limit")
            # Query can prune/sort/save. The host owns this staging directory
            # and removes its files even when the worker is cancelled/killed.
            (Path(scratch) / "db.zo").write_bytes(data)
            ranked = run(["zoxide", "query", "--list"], directory, {"_ZO_DATA_DIR": str(scratch)})
            for path in ranked.splitlines()[:8]:
                if Path(path).is_absolute() and Path(path).is_dir():
                    add("Frequent directories", path)
            frecency = "Ranked by zoxide; no visits recorded"
        except (OSError, ValueError, TimeoutError):
            frecency = "No available zoxide matches"
    return {"entries": entries, "truncated": truncated, "notice": frecency}


def git_details(directory, run):
    # Repository overrides belong to the invoking program, not this cwd.
    env = {key: None for key in os.environ if key.startswith("GIT_")}
    env["GIT_OPTIONAL_LOCKS"] = "0"
    prefix = ["git", "--no-optional-locks", "-c", "core.fsmonitor=false", "--no-pager"]
    raw_root = run(prefix + ["rev-parse", "--show-toplevel"], directory, env, binary=True)
    if not raw_root.endswith(b"\n"):
        raise ValueError("Repository directory is unavailable")
    root = raw_root[:-1].decode("utf-8")
    status = run(prefix + ["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=normal", "--ignore-submodules=all"], root, env, binary=True)
    records = status.split(b"\0")
    if records[-1] != b"":
        raise ValueError("Incomplete repository status")
    summary = ""
    files = []
    total = 0
    i = 0
    while i < len(records) - 1:
        record = records[i]
        i += 1
        if record.startswith(b"## "):
            summary = record[3:].decode("utf-8", "replace")
            continue
        if len(record) < 3 or record[2:3] != b" ":
            raise ValueError("Invalid repository status")
        flags = record[:2].decode("ascii")
        path = record[3:].decode("utf-8", "replace")
        label = flags + " " + json.dumps(path, ensure_ascii=False)
        if "R" in flags or "C" in flags:
            if i >= len(records) - 1:
                raise ValueError("Incomplete rename status")
            label += " ← " + json.dumps(records[i].decode("utf-8", "replace"), ensure_ascii=False)
            i += 1
        total += 1
        if len(files) < 48:
            files.append(label[:240])
    branch_data = run(prefix + ["for-each-ref", "--count=25", "--sort=-committerdate", "--format=%(refname:short)%00%(HEAD)", "refs/heads/"], root, env, binary=True)
    branches = []
    for line in branch_data.splitlines():
        name, active = line.split(b"\0", 1)
        try:
            name = name.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if len(name.encode()) <= 1024:
            branches.append({"name": name, "current": active == b"*"})
    return {"root": root, "summary": summary, "files": files, "total": total,
            "branches": branches, "truncated": total > len(files) or len(branches) == 25}
