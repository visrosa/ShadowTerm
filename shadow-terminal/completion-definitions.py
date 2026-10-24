#!/usr/bin/env python3
"""Native completion definitions and deterministic fish export, without a GUI.

Only documented fields are accepted: unsupported semantics fail explicitly.
Dynamic providers are configured literal argv, never interpolated shell source.
"""
import argparse
import json
import itertools
import os
from pathlib import Path
import sys

FIELDS = {"short", "long", "old", "description", "requires_argument", "files", "values", "dynamic", "when_subcommand", "keep_order"}
VALUE_FIELDS = {"value", "description", "kind", "group", "preview", "continue"}


def quote(value):
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def fish_literal(value):
    return quote(value)


def load(path):
    with Path(path).open("rb") as stream:
        raw = stream.read(256 * 1024 + 1)
    if len(raw) > 256 * 1024:
        raise ValueError("Definition exceeds 256 KiB")
    data = json.loads(raw)
    if set(data) - {"version", "command", "rules"} or data.get("version") != 1:
        raise ValueError("Unsupported definition version or fields")
    if not isinstance(data.get("command"), str) or not data["command"] or data["command"].startswith("-") or "/" in data["command"]:
        raise ValueError("Expected a command basename")
    rules = data.get("rules")
    if not isinstance(rules, list) or len(rules) > 128:
        raise ValueError("Expected at most 128 completion rules")
    for rule in rules:
        if not isinstance(rule, dict) or set(rule) - FIELDS:
            raise ValueError("Unsupported completion rule fields")
        for name in ("short", "long", "old", "description", "when_subcommand"):
            if name in rule and (not isinstance(rule[name], str) or any(c in rule[name] for c in "\0\n\t")):
                raise ValueError("Invalid " + name)
        if "short" in rule and len(rule["short"]) != 1:
            raise ValueError("Short options contain one character")
        if rule.get("files", "allow") not in {"allow", "disable", "force"}:
            raise ValueError("files must be allow, disable or force")
        for name in ("requires_argument", "keep_order"):
            if name in rule and not isinstance(rule[name], bool):
                raise ValueError(name + " must be a boolean")
        if not isinstance(rule.get("values", []), list):
            raise ValueError("values must be an array")
        for value in rule.get("values", []):
            if not isinstance(value, dict) or set(value) - VALUE_FIELDS or not isinstance(value.get("value"), str):
                raise ValueError("Invalid completion value")
            for name in ("description", "kind", "group", "preview"):
                if name in value and not isinstance(value[name], str):
                    raise ValueError(name + " must be text")
            if "continue" in value and not isinstance(value["continue"], bool):
                raise ValueError("continue must be a boolean")
            if any(c in value["value"] for c in "\0\n\t"):
                raise ValueError("Completion values cannot contain NUL, newline or tab")
        if "dynamic" in rule and (not isinstance(rule["dynamic"], list) or not rule["dynamic"] or
                                  any(not isinstance(a, str) or "\0" in a for a in rule["dynamic"])):
            raise ValueError("dynamic must be a literal argv list")
    return data


def values(rule, cwd):
    result = list(rule.get("values", []))
    if rule.get("dynamic"):
        # Import the bounded runner without importing GTK or starting a shell.
        import importlib.util
        spec = importlib.util.spec_from_file_location("content_service", Path(__file__).with_name("content-service.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        output = module.run(rule["dynamic"], cwd)
        if output.endswith("\n[Preview truncated]"):
            raise ValueError("Dynamic completion output exceeds its byte limit")
        for line in output.splitlines():
            value, _, description = line.partition("\t")
            if value:
                result.append({"value": value, "description": description})
    return result


def export(path):
    data = load(path)
    result = ["# Native completion definition. Preview/group metadata is Composer-only.",
              "# Dynamic rules require this definition and the headless completion-definitions.py helper."]
    for index, rule in enumerate(data["rules"]):
        args = ["complete", "-c", quote(data["command"])]
        for key, flag in (("short", "-s"), ("long", "-l"), ("old", "-o")):
            if rule.get(key):
                args += [flag, quote(rule[key])]
        if rule.get("when_subcommand"):
            args += ["-n", quote("__fish_seen_subcommand_from " + quote(rule["when_subcommand"]))]
        if rule.get("requires_argument"):
            args.append("-r")
        if rule.get("keep_order"):
            args.append("-k")
        if rule.get("files") == "disable":
            args.append("-f")
        elif rule.get("files") == "force":
            args.append("-F")
        if rule.get("description"):
            args += ["-d", quote(rule["description"])]
        # One declaration per value preserves distinct candidate descriptions.
        for value in rule.get("values", []):
            candidate = value["value"]
            if value.get("description"):
                candidate += "\t" + value["description"]
            row = args + ["-a", quote(fish_literal(candidate))]
            result.append(" ".join(row))
        if rule.get("dynamic"):
            helper = "(" + " ".join(["python3", quote(str(Path(__file__).resolve())), "--dynamic", quote(str(Path(path).resolve())), str(index)]) + ")"
            result.append(" ".join(args + ["-a", quote(helper)]))
        if not rule.get("values") and not rule.get("dynamic"):
            result.append(" ".join(args))
    return "\n".join(result) + "\n"


def complete(context, config):
    result = []
    problems = []
    root = Path(config)
    if not root.exists():
        return {"items": [], "complete": True, "matched": False, "files": False, "message": ""}
    from_context = context["words"]
    # Reuse the non-evaluating literal decoder from the lookup service.
    import importlib.util
    spec = importlib.util.spec_from_file_location("literal_context", Path(__file__).with_name("content-service.py"))
    decoder = importlib.util.module_from_spec(spec); spec.loader.exec_module(decoder)
    prefix = decoder.literal(context["prefix"])
    suffix = decoder.literal(context.get("suffix", ""))
    matched = False
    files = not prefix.startswith("-")
    # Providers receive literal tokens. Unsupported expanding contexts are
    # excluded by the host before calling this helper.
    command = context["command"]
    paths = sorted(itertools.islice(root.glob("*.json"), 33))
    truncated = len(paths) > 32
    for path in paths[:32]:
        try:
            data = load(path)
            if data["command"] != command:
                continue
            matched = True
            for rule in data["rules"]:
                if rule.get("when_subcommand") and rule["when_subcommand"] not in from_context[1:]:
                    continue
                options = [a + rule[b] for a, b in (("-", "short"), ("--", "long"), ("-", "old")) if rule.get(b)]
                argument = len(from_context) > 1 and from_context[-1] in options
                if argument or not options:
                    if rule.get("files") == "disable": files = False
                    elif rule.get("files") == "force": files = True
                if not argument:
                    for option in options:
                        if option.startswith(prefix):
                            result.append({"value": option, "description": rule.get("description", ""), "kind": "option"})
                if not options or argument:
                    for value in values(rule, context["cwd"]):
                        if value["value"].startswith(prefix) and value["value"].endswith(suffix):
                            result.append(value | {"description": value.get("description", rule.get("description", ""))})
        except (ValueError, OSError, KeyError, TypeError) as error:
            problems.append(path.name + ": " + str(error))
    return {"items": result[:128], "matched": matched, "files": files, "complete": not truncated and len(result) <= 128 and not problems,
            "message": "; ".join(problems)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--export", type=Path)
    group.add_argument("--dynamic", nargs=2, metavar=("FILE", "RULE"))
    args = parser.parse_args()
    if args.export:
        print(export(args.export), end="")
    else:
        path, index = args.dynamic
        for value in values(load(path)["rules"][int(index)], os.getcwd()):
            print(value["value"] + "\t" + value.get("description", ""))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        print("completion-definitions: " + str(error), file=sys.stderr)
        sys.exit(2)
