#!/usr/bin/env python3
r"""Re-causes reviewed ending sites from an edits list (the audit of the endings.py conversion).

    python tools/codemods/ending_fix.py EDITS [--apply]

EDITS has one `path/under/code.dm:line => new_call(...)` per line: the caused-ending call on that line (spent/consumed/destroyed/dissolved/...)
is replaced by new_call. A line whose call is gone or ambiguous is reported and skipped.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmlib import File  # noqa: E402

VERB = re.compile(r"(?<![\w.])(spent|consumed|destroyed|dissolved|lapsed|replaced_by|ended_with)\s*\(")


def span(line, start):
    i = line.index("(", start)
    depth = 0
    for j in range(i, len(line)):
        if line[j] == "(":
            depth += 1
        elif line[j] == ")":
            depth -= 1
            if depth == 0:
                return j + 1
    return None


def main():
    apply = "--apply" in sys.argv
    path = [a for a in sys.argv[1:] if not a.startswith("--")][0]
    files = {}
    bad = 0
    for raw in open(path, encoding="utf-8"):
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        loc, new = [x.strip() for x in raw.split("=>", 1)]
        rel, ln = loc.rsplit(":", 1)
        rel = "code/" + rel
        f = files.get(rel) or files.setdefault(rel, File(rel))
        line = f.lines[int(ln) - 1]
        ms = list(VERB.finditer(line))
        if len(ms) != 1:
            print(f"SKIP {loc}: {len(ms)} calls: {line.strip()}")
            bad += 1
            continue
        end = span(line, ms[0].start())
        old = line[ms[0].start():end]
        f.lines[int(ln) - 1] = line[:ms[0].start()] + new + line[end:]
        f.dirty = True
        print(f"{loc}: {old}  ->  {new}")
    if apply:
        for f in files.values():
            f.save()
    print(f"{'applied' if apply else 'dry run'}; {bad} skipped")


if __name__ == "__main__":
    main()
