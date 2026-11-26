#!/usr/bin/env python3
"""Writes doc/env_vars.md: every DQ_* / DMB_* environment variable the tooling reads, where, its default and what it does.

    python3 tools/ci/gen_env_vars.py            # write doc/env_vars.md
    python3 tools/ci/gen_env_vars.py --check    # exit 1 when doc/env_vars.md is stale
    python3 tools/ci/gen_env_vars.py --unread   # list names that are set or mentioned but that nothing reads

Scanned: the tracked tool sources (bash, TypeScript/JavaScript, Python, Rust, cmd/bat, workflows) under tools/, bin/ and .github/, plus
dependencies.sh and verdigris/*.sh; tools/dmb (the compiler's own DMB_* knobs, documented in tools/dmb) and tools/dm-health are left out.
A read is `${NAME...}`, `$NAME`, `$env:NAME`, `env!("NAME")`, `process.env.NAME`, `os.environ...("NAME"`, `getenv("NAME")`, `env::var("NAME")`, `%NAME%` or a
workflow `env:` key. The default is the first `${NAME:-x}`, `process.env.NAME ?? x` / `|| x` or `.get("NAME", x)` found. The meaning is
the nearest comment on or above the first read that names the variable, else the first read's own line; improve a row by improving that
comment in the script.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = "doc/env_vars.md"
NAME = r"((?:DQ|DMB)_[A-Z0-9_]*[A-Z0-9])"
READS = [
    re.compile(r"\$\{" + NAME + r"(?=[:}\-+=?#%/\[])"),
    re.compile(r"\$" + NAME + r"\b"),
    re.compile(r"process\.env(?:\.|\[['\"])" + NAME),
    re.compile(r"(?:Bun\.env|env)\.(" + r"(?:DQ|DMB)_[A-Z0-9_]+" + r")"),
    re.compile(r"environ(?:\.get\(|\[)\s*['\"]" + NAME),
    re.compile(r"getenv\(\s*['\"]" + NAME),
    re.compile(r"env::var(?:_os)?\(\s*\"" + NAME),
    re.compile(r"%" + NAME + r"%"),
    re.compile(r"\$env:" + NAME),                     # PowerShell
    re.compile(r"env!\(\s*\"" + NAME),                # Rust, at compile time
    re.compile(r"env\(\s*['\"]" + NAME),              # small helpers: env('DQ_X'), envNum("DQ_Y")
    re.compile(r"[eE]nv[A-Z][A-Za-z]*\(\s*['\"]" + NAME),
]
DEFAULTS = [
    lambda n: re.compile(r"\$\{" + n + r":?-([^}]*)\}"),
    lambda n: re.compile(r"process\.env(?:\.|\[['\"])" + n + r"['\"]?\]?\s*(?:\?\?|\|\|)\s*([^;),]+)"),
    lambda n: re.compile(r"environ\.get\(\s*['\"]" + n + r"['\"]\s*,\s*([^)]+)\)"),
]
EXTS = (".sh", ".ts", ".js", ".mjs", ".py", ".rs", ".cmd", ".bat", ".yml", ".yaml")


def files() -> list[str]:
    out = subprocess.run(["git", "ls-files", "tools", "bin", ".github", "dependencies.sh", "verdigris"], cwd=ROOT, capture_output=True,
                         text=True, check=True).stdout.splitlines()
    keep = []
    for f in out:
        if f.startswith(("tools/dmb/", "tools/dm-health/", "tools/analyze/vendor/")) or "node_modules" in f or f == "tools/ci/gen_env_vars.py":
            continue
        if f.startswith("verdigris/") and not (f.endswith(".sh") and f.count("/") == 1):
            continue
        if f.endswith(EXTS) or f == "dependencies.sh":
            keep.append(f)
    return keep


def comment_of(line: str) -> str:
    for mark in (" # ", "\t# ", "// ", "rem ", "::"):
        if mark in line:
            return line.split(mark, 1)[1].strip()
    s = line.strip()
    if s.startswith(("#", "//", "*", "/*")):
        return s.lstrip("#/* ").strip()
    return ""


def scan() -> tuple[dict, set]:
    rows: dict[str, dict] = {}
    mentioned: set[str] = set()
    for f in files():
        try:
            with open(os.path.join(ROOT, f), encoding="utf-8", errors="replace") as fh:
                lines = fh.read().splitlines()
        except OSError:
            continue
        workflow = f.endswith((".yml", ".yaml"))
        for i, line in enumerate(lines):
            for n in re.findall(r"\b" + NAME + r"\b", line):
                mentioned.add(n)
            found = set()
            for r in READS:
                found.update(r.findall(line))
            if workflow:
                m = re.match(r"\s*" + NAME + r"\s*:", line)
                if m:
                    found.add(m.group(1))
            for n in found:
                row = rows.setdefault(n, {"files": [], "default": "", "meaning": ""})
                if f not in row["files"]:
                    row["files"].append(f)
                if not row["default"]:
                    for d in DEFAULTS:
                        m = d(re.escape(n)).search(line)
                        if m:
                            row["default"] = m.group(1).strip().strip("'\"`")[:40]
                            break
                if not row["meaning"]:
                    text = comment_of(line)
                    if n not in text:
                        for j in range(i - 1, max(i - 6, -1), -1):
                            c = comment_of(lines[j])
                            if not c:
                                break
                            if n in c:
                                text = c
                                break
                    row["meaning"] = text
                    row["at"] = f"{f}:{i + 1}"
                    row["line"] = line.strip()
    return rows, mentioned


def render(rows: dict) -> str:
    out = ["# Environment variables (DQ_*, DMB_*)", "",
           "GENERATED by `tools/ci/gen_env_vars.py` from the tool sources; regenerate it after adding or removing a variable, never edit by hand.",
           "Each row is a variable something reads: the scripts that read it, the default where the code spells one, and the comment at",
           "its first read (or that line itself). The compiler's own `DMB_*` knobs read only inside `tools/dmb` are documented there.", "",
           "| Variable | Read by | Default | Meaning |", "|---|---|---|---|"]
    for n in sorted(rows):
        r = rows[n]
        meaning = r["meaning"] or ("`" + r["line"][:110].replace("`", "'") + "`")
        meaning = meaning.replace("|", "\\|")[:220]
        readers = ", ".join(f"`{f}`" for f in sorted(r["files"])[:4]) + (f" (+{len(r['files']) - 4})" if len(r["files"]) > 4 else "")
        default = ("`" + r["default"].replace("|", "\\|") + "`") if r["default"] else ""
        out.append(f"| `{n}` | {readers} | {default} | {meaning} |")
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    rows, mentioned = scan()
    if "--unread" in argv:
        for n in sorted(mentioned - set(rows)):
            print(n)
        return 0
    text = render(rows)
    path = os.path.join(ROOT, OUT)
    try:
        with open(path, encoding="utf-8", newline="") as fh:
            current = fh.read()
    except FileNotFoundError:
        current = None
    if "--check" in argv:
        if current != text:
            print(f"gen_env_vars: {OUT} is stale (regenerate: python3 tools/ci/gen_env_vars.py)", file=sys.stderr)
            return 1
        return 0
    if current != text:
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        print(f"gen_env_vars: wrote {OUT} ({len(rows)} variables)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
