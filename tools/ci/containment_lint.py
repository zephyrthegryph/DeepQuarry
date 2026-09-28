"""Containment lint (roadmap C1, doc/rewrite/containment.md section 2).

Every change of where a movable is goes through the ledger: forceMove() and
the slot API (code/datums/containment/api.dm) keep each holder's slots,
entry ids and aggregates current. A raw write skips all of that:

    X.loc = Y            (and bare `loc = Y` inside a proc)
    X.contents += Y      X.contents -= Y
    X.contents.Add(Y)    X.contents.Remove(Y)

The migration is gradual: tools/ci/containment_baseline.txt holds the ceiling
on legacy sites, which may fall, never rise. A site that must stay raw (doMove()'s
own commit point, ...) carries `// ALLOW(containment): <reason>` on its line or
the comment line above it (tools/ci/allow_annotations.py) and is not counted.

Usage:
    python tools/ci/containment_lint.py            # the CI check
    python tools/ci/containment_lint.py --report   # every site, and the total
    python tools/ci/containment_lint.py --update   # rewrite the ceiling to today's count
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed, check_ceilings, read_baseline, write_baseline  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "containment_baseline.txt")

# `loc =` not part of ==, !=, <=, >=, and not a longer name (oldloc, T.locs).
LOC_WRITE = re.compile(r"(?<![\w])loc\s*=(?!=)")
CONTENTS_WRITE = re.compile(r"(?<![\w])contents\s*(?:\+=|-=|\|=|&=)|(?<![\w])contents\s*\.\s*(?:Add|Remove|Cut|Insert|Swap)\s*\(")
# Declarations and named arguments are not writes: `var/turf/loc = ...`,
# `new /obj(loc = T)` is rare but legal.
DECLARATION = re.compile(r"var/(?:[\w/]+/)?loc\s*=")
# Files exempt outright. doMove()'s own loc writes (the ledger's commit point)
# are annotated like any other kept site, so none are exempt.
EXEMPT_FILES = set()


def scan_file(path):
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(path, encoding="utf-8", errors="replace") as handle:
        raw = handle.read()
    raw_lines = raw.split("\n")
    text = code_only(raw)
    sites = []
    for number, line in enumerate(text.split("\n"), 1):
        if allowed(raw_lines, number, "containment"):
            continue
        if DECLARATION.search(line):
            line = DECLARATION.sub("", line)
        for match in LOC_WRITE.finditer(line):
            before = line[: match.start()].rstrip()
            # A named argument inside a call: `(loc = x` or `, loc = x`.
            if before.endswith("(") or before.endswith(","):
                continue
            sites.append((rel, number, "loc ="))
        for match in CONTENTS_WRITE.finditer(line):
            sites.append((rel, number, match.group(0).strip()))
    return rel, sites


def scan():
    counts = {}
    all_sites = []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel, sites = scan_file(path)
        if rel in EXEMPT_FILES or not sites:
            continue
        counts[rel] = len(sites)
        all_sites.extend(sites)
    return counts, all_sites


def main(argv):
    counts, sites = scan()
    total = sum(counts.values())
    if "--update" in argv:
        write_baseline(BASELINE, [
            "Legacy raw `loc =` / `contents +=` / `contents -=` writes (roadmap C1).",
            "tools/ci/containment_lint.py fails when the count rises above this ceiling.",
            "Convert sites to forceMove() or the slot API (code/datums/containment/api.dm), then",
            "lower it: `python tools/ci/containment_lint.py --update`.",
        ], {"raw_writes": total})
        print("containment baseline: %d sites in %d files" % (total, len(counts)))
        return 0
    if "--report" in argv:
        for rel, number, what in sites:
            print("%s:%d: %s" % (rel, number, what))
        print("total: %d raw loc/contents writes in %d files" % (total, len(counts)))
        return 0
    failed = check_ceilings("containment", {"raw_writes": total}, read_baseline(BASELINE),
                            "Use forceMove() or the slot API (code/datums/containment/api.dm).")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
