#!/usr/bin/env python3
"""Deadline-polling lint (doc/rewrite/reactor.md §10, roadmap S3).

A process() that compares world.time with a stored deadline is polling a timer: it runs
every tick only to find out that the deadline has not passed yet. Such work belongs in a
REACT_AT timer, which wakes the datum once, at the deadline.

This flags every process() body (and react_every() is exempt: it is declared continuous
work) with a comparison between world.time and a variable, such as
`world.time >= next_fire` or `close_at <= world.time`. Arithmetic like
`world.time - last_run` is not a comparison against a deadline and is not flagged.

What is left is listed in tools/ci/deadline_polling_allowlist.txt, one `path:proc_path`
per line with a reason after `#`. An entry that no longer matches anything is an error too,
so the list only shrinks.

    python3 tools/ci/check_deadline_polling.py            # the CI check
    python3 tools/ci/check_deadline_polling.py --list     # print every finding, allowlisted or not
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "deadline_polling_allowlist.txt")

# `/type/path/process(` at column 0, or `process(` / `proc/process(` indented one level under a type block.
TOP_LEVEL = re.compile(r"^(/[\w/]+?)/(?:proc/)?process\(")
TYPE_BLOCK = re.compile(r"^(/[\w/]+)\s*(?://.*)?$")
NESTED = re.compile(r"^\t(?:proc/)?process\(")

IDENT = r"[A-Za-z_][\w.\[\]?]*"
TIME = r"(?:world\.time|REALTIMEOFDAY)"
CMP = r"(?:>=|<=|>|<)"
# world.time <cmp> ident, or ident <cmp> world.time. The identifier must not be followed
# by arithmetic (world.time > a + b still reads a stored deadline, so allow +/- after it).
DEADLINE = re.compile(
    rf"(?<![\w.]){TIME}\s*{CMP}\s*(?!\d)({IDENT})|(?<![\w.])({IDENT})\s*{CMP}\s*{TIME}(?![\w])"
)


def strip_comment(line):
    # Good enough for DM: drop // comments outside strings.
    out = []
    in_str = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"' and (i == 0 or line[i - 1] != "\\"):
            in_str = not in_str
        if not in_str and line.startswith("//", i):
            break
        out.append(c)
        i += 1
    return "".join(out)


def indent_of(line):
    return len(line) - len(line.lstrip("\t"))


def scan_file(path):
    """Yields (proc_path, line_number, text) for each deadline comparison in a process() body."""
    with open(path, encoding="utf-8", errors="ignore") as f:
        lines = f.read().split("\n")
    current_type = None
    i = 0
    while i < len(lines):
        line = lines[i]
        proc_path = None
        body_indent = None
        m = TOP_LEVEL.match(line)
        if m:
            proc_path = m.group(1) + "/process"
            body_indent = 1
        else:
            tb = TYPE_BLOCK.match(line)
            if tb:
                current_type = tb.group(1)
            elif line and not line.startswith(("\t", " ", "#", "//")):
                current_type = None
            if current_type and NESTED.match(line):
                proc_path = current_type + "/process"
                body_indent = 2
        if not proc_path:
            i += 1
            continue
        j = i + 1
        while j < len(lines):
            body = lines[j]
            if body.strip() and indent_of(body) < body_indent:
                break
            text = strip_comment(body)
            if DEADLINE.search(text):
                yield proc_path, j + 1, body.strip()
            j += 1
        i = j


def load_allowlist():
    entries = {}
    if not os.path.exists(ALLOWLIST):
        return entries
    with open(ALLOWLIST, encoding="utf-8") as f:
        for number, raw in enumerate(f, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            if "#" not in raw:
                print(f"{ALLOWLIST}:{number}: entry has no reason: {line}")
                sys.exit(1)
            entries[line] = number
    return entries


def main():
    list_all = "--list" in sys.argv
    os.chdir(ROOT)
    findings = {}
    for path in sorted(glob.glob("code/**/*.dm", recursive=True)):
        rel = path.replace("\\", "/")
        if "/unit_tests/" in rel:
            continue
        for proc_path, number, text in scan_file(path):
            findings.setdefault(f"{rel}:{proc_path}", []).append((number, text))
    allow = load_allowlist()
    bad = []
    for key, hits in sorted(findings.items()):
        rel = key.split(":", 1)[0]
        if list_all:
            for number, text in hits:
                print(f"{rel}:{number}: {key.split(':', 1)[1]}: {text}{'  (allowlisted)' if key in allow else ''}")
        if key not in allow:
            bad.extend((rel, number, key.split(":", 1)[1], text) for number, text in hits)
    stale = [key for key in allow if key not in findings]
    for rel, number, proc_path, text in bad:
        print(f"{rel}:{number}: {proc_path} compares world.time with a stored deadline: {text}")
    for key in stale:
        print(f"{ALLOWLIST}:{allow[key]}: stale entry (nothing matches it any more): {key}")
    print(f"Deadline polling: {len(findings)} process() bodies found, {len(allow)} allowlisted, {len(bad)} new finding(s), {len(stale)} stale entr{'y' if len(stale) == 1 else 'ies'}.")
    if bad or stale:
        print("Use REACT_AT(src, deadline) instead (doc/rewrite/reactor.md §3), or allowlist with a reason.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
