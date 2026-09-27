"""Spatial/contents-read lint (roadmap C11, doc/rewrite/containment.md section 2a).

C1's containment_lint.py caught raw *writes* to `loc`/`contents` -- moves that
skip the ledger. This lint catches raw *reads*: code that walks a holder's or
a turf's contents directly instead of going through the ledger read API
(`slot_contents()`, `latent_entries()`, `latent_count()`, `get_all_contents()`,
...) or the spatial API (`turf_contents_of_type()`, `locate_on()`, ...). Both
are named in doc/rewrite/containment.md section 2a.

Four patterns, each counted separately per file:
  - `in X.contents`          -- explicit contents loop (`for(var/a/A in X.contents)`)
  - `in src` / `in loc` / `in T` -- implicit contents loop: DM iterates an atom's
    contents when you write `for(var/a/A in loc)`, without spelling `.contents`.
    Restricted to the handful of identifiers holder code actually loops over
    (`src`, `loc`, `T`, `H`, `M`, `A`, `AM`, `holder`, `container`) to avoid
    matching `in list(...)`/`in GLOB.foo`/other iterables.
  - `contents.len` / `length(contents)` -- raw content counts.
  - `locate(...) in` -- a locate search over a raw list/contents/loc instead of
    the spatial API's typed helper.

The migration is gradual, so sites are listed per file with a count in
tools/ci/spatial_allowlist.txt. A file may not exceed its count, and an
unlisted file may have none. A file below its count is reported so the
allowlist can be lowered (run with --update).

Usage:
    python tools/ci/spatial_lint.py            # the CI check
    python tools/ci/spatial_lint.py --report   # every site, and totals per pattern
    python tools/ci/spatial_lint.py --update   # rewrite the allowlist to today's counts
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "spatial_allowlist.txt")

# Files that implement the ledger/spatial API itself: they're allowed to
# touch raw contents/loc/locate freely since they're what the lint is
# steering everyone else towards.
API_DIRS = (
    "code/datums/containment/",
)
API_FILES = (
    "code/__defines/containment.dm",
)

IMPLICIT_IDENTS = r"(?:src|loc|T|H|M|A|AM|holder|container)"

PATTERNS = [
    ("contents_loop", re.compile(r"\bin\s+[\w.:]*\.contents\b")),
    ("implicit_loop", re.compile(r"\bin\s+" + IMPLICIT_IDENTS + r"\s*\)")),
    ("contents_len", re.compile(r"\bcontents\s*\.\s*len\b|\blength\s*\(\s*contents\s*\)")),
    # A negative lookahead excludes the correct idiom: `locate(X) in
    # slot_contents(...)` (or any other ledger/spatial read call) is not a
    # raw contents/turf/area read -- it's a locate over a list the approved
    # API already returned. Without this, the count could never reach zero
    # even for fully-converted code, since every ledger-holder locate still
    # needs some `in <list>` clause.
    ("locate_in", re.compile(
        r"\blocate\s*\([^()]*\)\s*in\s+"
        r"(?!(?:[\w.]+\.)?(?:slot_contents|latent_entries|latent_materialize_all|get_all_contents|"
        r"turf_contents_of_type|area_contents_of_type|contents_property)\s*\()"
    )),
]


def is_api_file(rel):
    if rel in API_FILES:
        return True
    return any(rel.startswith(d) for d in API_DIRS)


def scan_file(path):
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = code_only(handle.read())
    sites = []
    for number, line in enumerate(text.split("\n"), 1):
        for kind, pattern in PATTERNS:
            for match in pattern.finditer(line):
                sites.append((rel, number, kind, match.group(0).strip()))
    return rel, sites


def scan():
    counts = {}
    all_sites = []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel, sites = scan_file(path)
        if is_api_file(rel) or not sites:
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
        "# Legacy raw contents/loc reads: `in X.contents`, implicit `in src`/`in",
        "# loc`/`in T` loops, `contents.len`/`length(contents)`, `locate() in`",
        "# (roadmap C11). tools/ci/spatial_lint.py reads this file: a file may not",
        "# exceed its count, and files not listed may have none. Convert sites to",
        "# the ledger read API or the spatial API (doc/rewrite/containment.md",
        "# section 2a) and lower the count; `python tools/ci/spatial_lint.py",
        "# --update` rewrites it.",
        "# Total: %d sites in %d files." % (sum(counts.values()), len(counts)),
    ]
    for path in sorted(counts):
        lines.append("%s %d" % (path, counts[path]))
    with open(ALLOWLIST, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def main():
    args = sys.argv[1:]
    counts, all_sites = scan()

    if "--report" in args:
        by_kind = {}
        for rel, number, kind, text in all_sites:
            by_kind.setdefault(kind, 0)
            by_kind[kind] += 1
            print("%s:%d: %s: %s" % (rel, number, kind, text))
        print("---")
        for kind, _pattern in PATTERNS:
            print("%s: %d" % (kind, by_kind.get(kind, 0)))
        print("Total: %d sites in %d files" % (sum(counts.values()), len(counts)))
        return 0

    if "--update" in args:
        write_allowlist(counts)
        print("Wrote %s: %d sites in %d files" % (ALLOWLIST, sum(counts.values()), len(counts)))
        return 0

    allowed = read_allowlist()
    failed = False
    for rel, count in sorted(counts.items()):
        limit = allowed.get(rel, 0)
        if count > limit:
            failed = True
            print("FAIL: %s has %d raw contents/locate sites, allowlist caps it at %d" % (rel, count, limit))
    for rel, limit in sorted(allowed.items()):
        actual = counts.get(rel, 0)
        if actual < limit:
            print("INFO: %s dropped to %d sites (allowlist says %d) -- run --update to lower it" % (rel, actual, limit))
    if failed:
        print("\nContainment reads must go through the ledger/spatial API (doc/rewrite/containment.md section 2a).")
        print("Run 'python tools/ci/spatial_lint.py --update' only after actually converting sites, not to paper over new ones.")
        return 1
    print("spatial_lint: OK (%d sites in %d files, capped by allowlist)" % (sum(counts.values()), len(counts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
