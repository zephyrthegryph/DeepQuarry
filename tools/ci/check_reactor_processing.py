#!/usr/bin/env python3
"""Processing lint (doc/rewrite/reactor.md §2 and §10, roadmap S4).

SSreactor is the one scheduler. Two rules:

1. No START_PROCESSING / STOP_PROCESSING outside the reactor. SSobj, SSprocessing,
   SSfastprocess and friends are retired: deadlines are REACT_AT, linear quantities are rate
   models, state changes are keys, and only work that really is continuous stays, declared.
   The few dedicated processors left (and H3's SSburning) are listed in
   tools/ci/processing_allowlist.txt, one `path` per line with a reason after `#`. A stale
   entry (the file no longer uses the macros) is an error, so the list only shrinks.

2. Every remaining continuous user is declared: each REACT_EVERY(...) and REACT_PROCESS(...)
   call passes a non-empty string literal as its justification (the third argument).

    python3 tools/ci/check_reactor_processing.py          # the CI check
    python3 tools/ci/check_reactor_processing.py --list   # also print every declaration
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "processing_allowlist.txt")

# The macro definitions themselves and the retired subsystems' shared base.
EXEMPT = {
    "code/__defines/MC.dm",
    "code/__defines/reactor.dm",
    "code/controllers/subsystems/processing/processing.dm",
}
PROCESSING = re.compile(r"(?<![\w])(START|STOP)_PROCESSING\s*\(")
DECLARE = re.compile(r"(?<![\w])(REACT_EVERY|REACT_PROCESS)\s*\(")


def strip_comment(line):
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


def split_args(text, start):
    """Splits the call arguments starting after the '(' at `start`. None if unbalanced."""
    depth = 0
    args = []
    cur = []
    in_str = False
    i = start
    while i < len(text):
        c = text[i]
        if in_str:
            cur.append(c)
            if c == "\\" and i + 1 < len(text):
                cur.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            cur.append(c)
        elif c in "([{":
            depth += 1
            cur.append(c)
        elif c in ")]}":
            if depth == 0:
                args.append("".join(cur).strip())
                return args
            depth -= 1
            cur.append(c)
        elif c == "," and depth == 0:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    return None


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
    allow = load_allowlist()
    users = set()
    bad = []
    declarations = []
    for path in sorted(glob.glob("code/**/*.dm", recursive=True) + glob.glob("maps/**/*.dm", recursive=True)):
        rel = path.replace("\\", "/")
        if rel in EXEMPT:
            continue
        with open(path, encoding="utf-8", errors="ignore") as f:
            lines = f.read().split("\n")
        for number, raw in enumerate(lines, 1):
            text = strip_comment(raw)
            if text.lstrip().startswith("#define"):
                continue
            if PROCESSING.search(text):
                users.add(rel)
                if rel not in allow:
                    bad.append(f"{rel}:{number}: START_PROCESSING/STOP_PROCESSING outside the reactor: {raw.strip()}")
            for m in DECLARE.finditer(text):
                # Join continuation lines for a call split across lines.
                joined = text + " " + " ".join(strip_comment(l) for l in lines[number:number + 4])
                args = split_args(joined, m.end())
                why = args[2] if args and len(args) >= 3 else ""
                if "/unit_tests/" in rel:
                    continue
                if not (why.startswith('"') and why.endswith('"') and len(why) > 2):
                    bad.append(f"{rel}:{number}: {m.group(1)} without a string justification: {raw.strip()}")
                else:
                    declarations.append((rel, number, m.group(1), args[1], why))
    stale = [key for key in allow if key not in users]
    for line in bad:
        print(line)
    for key in stale:
        print(f"{ALLOWLIST}:{allow[key]}: stale entry (the file no longer uses START/STOP_PROCESSING): {key}")
    if list_all:
        for rel, number, macro, period, why in declarations:
            print(f"{rel}:{number}: {macro} every {period}: {why}")
    print(f"Processing: {len(users)} file(s) use START/STOP_PROCESSING ({len(allow)} allowlisted), {len(declarations)} declared continuous user(s), {len(bad)} finding(s), {len(stale)} stale entr{'y' if len(stale) == 1 else 'ies'}.")
    if bad or stale:
        print("Use REACT_AT / rate models / keys, or REACT_EVERY / REACT_PROCESS with a justification (doc/rewrite/reactor.md §2).")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
