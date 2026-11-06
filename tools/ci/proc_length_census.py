#!/usr/bin/env python3
"""Report-only census of the longest DM procs (no gating, always exits 0).

A proc is a column-0 definition `/path/to/name(args)` or `/path/to/proc/name(args)`; its body is every
following line until the next column-0 line that is not blank, a comment or a continuation of a
column-0 block comment. Length counts code lines (blank lines and whole-line comments excluded);
`total` counts every line.

    python3 tools/ci/proc_length_census.py [--top N] [--min N] [--root DIR]... [--csv]
"""
import argparse
import os
import re
import sys

DEF = re.compile(r"^(/[A-Za-z0-9_/]*?)([A-Za-z_][A-Za-z0-9_]*)\(")
SKIP_DIRS = {"code/tests", "code/_generated", "code/engine/_generated", "code/world/tgs"}


def census(path, rel):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().split("\n")
    except OSError:
        return []
    out = []
    cur = None  # [name, start, code_lines]
    in_block = False
    for i, raw in enumerate(lines, 1):
        stripped = raw.strip()
        if in_block:
            if "*/" in raw:
                in_block = False
            if cur:
                cur[3] = i
            continue
        if stripped.startswith("/*") and "*/" not in stripped:
            in_block = True
            continue
        if raw[:1] == "/" and not raw.startswith("//") and not raw.startswith("/*"):
            if cur:
                out.append(cur)
                cur = None
            m = DEF.match(raw)
            if m and "/proc/" in raw.split("(")[0] + "/" or (m and m.group(1).count("/") >= 2):
                cur = [m.group(1) + m.group(2), i, 0, i]
            continue
        if cur is None:
            continue
        if raw[:1] not in ("\t", " ", "") and stripped and not stripped.startswith(("//", "#")):
            out.append(cur)
            cur = None
            continue
        if stripped:
            cur[3] = i
            if not stripped.startswith("//") and not stripped.startswith("#"):
                cur[2] += 1
    if cur:
        out.append(cur)
    return [(n, rel, s, c, e - s + 1) for n, s, c, e in out]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--min", type=int, default=0)
    ap.add_argument("--root", action="append", default=None)
    ap.add_argument("--csv", action="store_true")
    a = ap.parse_args()
    roots = a.root or ["code", "interface", "maps/common"]
    base = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    rows = []
    for root in roots:
        for d, dirs, files in os.walk(os.path.join(base, root)):
            reld = os.path.relpath(d, base).replace(os.sep, "/")
            if any(reld == s or reld.startswith(s + "/") for s in SKIP_DIRS):
                dirs[:] = []
                continue
            for f in files:
                if f.endswith(".dm"):
                    rows += census(os.path.join(d, f), (reld + "/" + f).replace("./", ""))
    rows = [r for r in rows if r[3] >= a.min]
    rows.sort(key=lambda r: -r[3])
    if a.csv:
        print("code_lines,total_lines,proc,file,line")
    else:
        print("Longest DM procs (report only; code lines, total lines):")
    for name, rel, start, code, total in rows[: a.top]:
        if a.csv:
            print(f"{code},{total},{name},{rel},{start}")
        else:
            print(f"{code:5d} {total:5d}  {name}  {rel}:{start}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
