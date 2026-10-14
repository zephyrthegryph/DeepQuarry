#!/usr/bin/env python3
r"""Lists the caused-ending sites in content (spent/consumed/destroyed/dissolved calls) with their enclosing proc, for review.

    python tools/codemods/ending_sites.py [--verb spent] [--paths prefix ...]
    python tools/codemods/ending_sites.py --update | --check

Prints verb<TAB>file:line<TAB>proc<TAB>statement<TAB>the two lines before, one site per line, grouped by proc name.
--update writes the cause snapshot tools/ci/ending_causes_snapshot.txt (verb, file, proc, statement; no line numbers), the reviewed
record of which ending every content site uses; --check diffs the tree against it (a review aid, not a CI gate: other branches convert
qdel() sites by hand and re-run --update).
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmlib import File, dm_files, strip_code  # noqa: E402

VERB = re.compile(r"(?<![\w.])(spent|consumed|destroyed|dissolved|lapsed|replaced_by|ended_with|replace_with|consume)\s*\(")
SNAPSHOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ci", "ending_causes_snapshot.txt")
PROC = re.compile(r"^(/[\w/]+?)?/?(?:proc/|verb/)?(\w+)\((.*)$")
ENGINE = ("code/engine/", "code/library/", "code/datums/lifecycle/", "code/__defines/", "code/modules/unit_tests/")


def sites(paths):
    for rel in dm_files(paths or ("code/",)):
        if rel.startswith(ENGINE):
            continue
        f = File(rel)
        proc = "?"
        for i, line in enumerate(f.lines):
            if line and not line[0].isspace() and "(" in line and not line.startswith(("#", "//")):
                m = PROC.match(line.strip())
                if m:
                    proc = m.group(2)
            code = strip_code(line)
            m = VERB.search(code)
            if m:
                ctx = " | ".join(x.strip() for x in f.lines[max(0, i - 2):i])
                yield m.group(1), f"{rel}:{i + 1}", proc, line.strip(), ctx


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verb")
    ap.add_argument("--paths", nargs="*")
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if a.update or a.check:
        rows = sorted("\t".join((r[0], r[1].rsplit(":", 1)[0], r[2], r[3])) for r in sites(None))
        header = "# Caused endings in content: verb<TAB>file<TAB>proc<TAB>statement. Regenerate: python tools/codemods/ending_sites.py --update\n"
        text = header + "\n".join(rows) + "\n"
        if a.update:
            open(SNAPSHOT, "w", encoding="utf-8", newline="\n").write(text)
            print(f"{len(rows)} sites")
            return
        old = set(open(SNAPSHOT, encoding="utf-8").read().splitlines()[1:])
        new = set(rows)
        for r in sorted(old - new):
            print("- " + r)
        for r in sorted(new - old):
            print("+ " + r)
        sys.exit(1 if old != new else 0)
    rows = [r for r in sites(a.paths) if not a.verb or r[0] == a.verb]
    rows.sort(key=lambda r: (r[2].lower(), r[1]))
    for r in rows:
        print("\t".join(r))


if __name__ == "__main__":
    main()
