"""Containment lint (roadmap C1, doc/rewrite/containment.md section 2).

Every change of where a movable is goes through the ledger: forceMove() and
the slot API (code/datums/containment/api.dm) keep each holder's slots,
entry ids and aggregates current. A raw write skips all of that:

    X.loc = Y            (and bare `loc = Y` inside a proc)
    X.contents += Y      X.contents -= Y
    X.contents.Add(Y)    X.contents.Remove(Y)

The migration is gradual, so legacy sites are listed per file with a count
in tools/ci/containment_allowlist.txt. A file may not gain sites: a new file
with any, or a listed file above its count, fails. A file below its count
is reported so the allowlist can be lowered (run with --update).

Usage:
    python tools/ci/containment_lint.py            # the CI check
    python tools/ci/containment_lint.py --report   # every site, and the total
    python tools/ci/containment_lint.py --update   # rewrite the allowlist to today's counts
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "containment_allowlist.txt")

# `loc =` not part of ==, !=, <=, >=, and not a longer name (oldloc, T.locs).
LOC_WRITE = re.compile(r"(?<![\w])loc\s*=(?!=)")
CONTENTS_WRITE = re.compile(r"(?<![\w])contents\s*(?:\+=|-=|\|=|&=)|(?<![\w])contents\s*\.\s*(?:Add|Remove|Cut|Insert|Swap)\s*\(")
# Declarations and named arguments are not writes: `var/turf/loc = ...`,
# `new /obj(loc = T)` is rare but legal.
DECLARATION = re.compile(r"var/(?:[\w/]+/)?loc\s*=")
# Files exempt outright. doMove()'s own loc writes (the ledger's commit point)
# are allowlisted by count like any other site, so none are exempt.
EXEMPT_FILES = set()


def scan_file(path):
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = code_only(handle.read())
    sites = []
    for number, line in enumerate(text.split("\n"), 1):
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


def read_allowlist():
    allowed = {}
    if not os.path.exists(ALLOWLIST):
        return allowed
    with open(ALLOWLIST, encoding="utf-8") as handle:
        for line in handle:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            path, count = line.rsplit(None, 1)
            allowed[path] = int(count)
    return allowed


def write_allowlist(counts):
    lines = [
        "# Legacy raw `loc =` / `contents +=` / `contents -=` writes (roadmap C1).",
        "# tools/ci/containment_lint.py reads this file: a file may not exceed its",
        "# count, and files not listed may have none. Convert sites to forceMove()",
        "# or the slot API (code/datums/containment/api.dm) and lower the count;",
        "# `python tools/ci/containment_lint.py --update` rewrites it.",
        "# Total: %d sites in %d files." % (sum(counts.values()), len(counts)),
    ]
    for path in sorted(counts):
        lines.append("%s %d" % (path, counts[path]))
    with open(ALLOWLIST, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def main(argv):
    counts, sites = scan()
    total = sum(counts.values())
    if "--update" in argv:
        write_allowlist(counts)
        print("containment allowlist: %d sites in %d files" % (total, len(counts)))
        return 0
    if "--report" in argv:
        for rel, number, what in sites:
            print("%s:%d: %s" % (rel, number, what))
        print("total: %d raw loc/contents writes in %d files" % (total, len(counts)))
        return 0
    allowed = read_allowlist()
    failures = []
    lowered = []
    for rel in sorted(counts):
        limit = allowed.get(rel, 0)
        if counts[rel] > limit:
            where = [("%s:%d: %s" % s) for s in sites if s[0] == rel]
            failures.append(
                "%s has %d raw loc/contents writes, allowed %d. Use forceMove() or the slot API "
                "(code/datums/containment/api.dm):\n    %s" % (rel, counts[rel], limit, "\n    ".join(where))
            )
        elif counts[rel] < limit:
            lowered.append("%s: %d (allowlist says %d)" % (rel, counts[rel], limit))
    for rel in sorted(allowed):
        if rel not in counts:
            lowered.append("%s: 0 (allowlist says %d)" % (rel, allowed[rel]))
    print("containment lint: %d raw loc/contents writes in %d files (allowlisted: %d)"
          % (total, len(counts), sum(allowed.values())))
    if lowered:
        print("These files dropped below their allowlisted count; lower it with --update:")
        for line in lowered:
            print("    " + line)
    if failures:
        for failure in failures:
            print("FAIL: " + failure)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
