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

This is an outright ban (C11): any unannotated site fails CI. A read that is right as it is carries
`// ALLOW(spatial): <reason>` on its line or the comment line above it
(tools/ci/allow_annotations.py) and is not counted.

Usage:
    python tools/ci/spatial_lint.py            # the CI check
    python tools/ci/spatial_lint.py --report   # every site, and totals per pattern
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed, exempt_path  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

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
        r"turf_contents_of_type|area_contents_of_type|contents_property|contents_of)\s*\()"
    )),
]


def is_api_file(rel):
    if rel in API_FILES:
        return True
    return any(rel.startswith(d) for d in API_DIRS)


def scan_file(path):
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(path, encoding="utf-8", errors="replace") as handle:
        raw = handle.read()
    raw_lines = raw.split("\n")
    text = code_only(raw)
    sites = []
    for number, line in enumerate(text.split("\n"), 1):
        found = [(kind, match.group(0).strip()) for kind, pattern in PATTERNS for match in pattern.finditer(line)]
        # Asked only about a line that would otherwise count.
        if not found or allowed(raw_lines, number, "spatial"):
            continue
        sites.extend((rel, number, kind, snippet) for kind, snippet in found)
    return rel, sites


def scan():
    counts = {}
    all_sites = []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        if exempt_path(os.path.relpath(path, ROOT).replace(os.sep, "/")):
            continue
        rel, sites = scan_file(path)
        if is_api_file(rel) or not sites:
            continue
        counts[rel] = len(sites)
        all_sites.extend(sites)
    return counts, all_sites


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

    total = sum(counts.values())
    if total:
        for rel, number, kind, text in all_sites:
            print("%s:%d: %s: %s" % (rel, number, kind, text))
        print("spatial: %d raw contents reads. Use contents_of()/FOR_CONTENTS/is_inside()/locate_within()/"
              "contents_count()/locate_in_list() or the ledger read API (doc/rewrite/containment.md section 2a); "
              "a justified keep takes `// ALLOW(spatial): <reason>`." % total)
        return 1
    print("spatial raw_reads 0  ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
