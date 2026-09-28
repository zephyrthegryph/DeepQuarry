#!/usr/bin/env python3
"""Latent-contents lint (roadmap C5, doc/rewrite/containment.md section 4.4).

Holders with latent contents keep some of what they hold as ledger entries, so
a raw walk over their `contents` misses things. On those holders, code must go
through the ledger API (latent_materialize_all(), latent_entries(),
latent_count(), slot_contents()) instead.

A holder type opts in with `latent_contents = TRUE` in its type block. This
lint flags, in every .dm file under code/:
  - raw walks in procs of a latent holder type (or a subtype):
    `in contents`, `in src.contents`, `in src)`, `contents.len`, `length(contents)`;
  - raw walks through a variable typed as a latent holder:
    `X.contents`, `in X)`.
A line that already goes through the API, or walks what is materialized on
purpose, says so with `// ALLOW(latent): <reason>` (tools/ci/allow_annotations.py).

tools/ci/latent_baseline.txt holds the ceiling on the remaining sites; it may
fall, never rise. Run with --update to lower it after fixing sites. It also prints the number of legacy
`contents` loops over the whole tree, for the record.
"""
import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(__file__))
from allow_annotations import allowed, check_sites, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "latent_baseline.txt")
SKIP_DIRS = {"unit_tests"}

TYPE_HEADER = re.compile(r"^(/[\w/]+)\s*$")
PROC_HEADER = re.compile(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\(")
LATENT_DECL = re.compile(r"^\s+latent_contents\s*=\s*(TRUE|FALSE)")
OWN_WALK = re.compile(r"\bin\s+(?:src\.)?contents\b|\bin\s+src\s*\)|(?<![\w.])contents\.len\b|length\(\s*(?:src\.)?contents\s*\)")
TYPED_VAR = re.compile(r"var/([\w/]+)/(\w+)")
LEGACY_LOOP = re.compile(r"\bfor\s*\(.*\bin\s+(?:[\w.]+\.)?contents\b")


def dm_files():
    for root, dirs, files in os.walk(os.path.join(ROOT, "code")):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if name.endswith(".dm"):
                yield os.path.join(root, name)


def read(path):
    with open(path, encoding="utf-8", errors="ignore") as handle:
        return handle.read().splitlines()


def latent_holders(files):
    """Latent holder types, and the subtypes that opt back out."""
    holders = set()
    eager = set()
    for path in files:
        current = None
        for line in read(path):
            header = TYPE_HEADER.match(line)
            if header:
                current = header.group(1)
                continue
            if line and not line[0].isspace():
                current = None
            decl = LATENT_DECL.match(line) if current else None
            if decl:
                (holders if decl.group(1) == "TRUE" else eager).add(current)
    return holders, eager


def under(path, roots):
    best = None
    for root in roots:
        if path == root or path.startswith(root + "/"):
            if best is None or len(root) > len(best):
                best = root
    return best


def is_holder(path, holders):
    """Nearest declaration wins: a subtype set back to FALSE is not a holder."""
    holders, eager = holders
    latent = under(path, holders)
    opted_out = under(path, eager)
    return latent is not None and (opted_out is None or len(latent) > len(opted_out))


def scan(path, holders):
    sites = []
    owner = None
    typed = set()
    lines = read(path)
    for number, line in enumerate(lines, 1):
        if allowed(lines, number, "latent"):
            continue
        header = PROC_HEADER.match(line)
        if header:
            owner = header.group(1)
            typed = set()
        elif line and not line[0].isspace() and not line.startswith("//"):
            owner = None
            typed = set()
        code = line.split("//", 1)[0]
        for match in TYPED_VAR.finditer(code):
            var_type = "/" + match.group(1).lstrip("/")
            if is_holder(var_type, holders):
                typed.add(match.group(2))
        if owner and is_holder(owner, holders) and OWN_WALK.search(code):
            sites.append(number)
            continue
        for name in typed:
            if re.search(r"\b%s\.contents\b|\bin\s+%s\s*\)" % (name, name), code):
                sites.append(number)
                break
    return sites


def main():
    files = list(dm_files())
    holders = latent_holders(files)
    counts = Counter()
    where = {}
    legacy = 0
    for path in files:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        for line in read(path):
            if LEGACY_LOOP.search(line):
                legacy += 1
        sites = scan(path, holders)
        if sites:
            counts[rel] = len(sites)
            where[rel] = sites
    total = sum(counts.values())
    sites = {"raw_walks": [(rel, n) for rel in sorted(where) for n in where[rel]]}
    if "--update" in sys.argv or "--seed" in sys.argv:
        rows = write_sites(BASELINE, [
            "Raw contents walks on latent holders (tools/ci/latent_lint.py). rule<TAB>file<TAB>normalized line.",
            "Shrink-only: fix a site through the ledger API, then `python tools/ci/latent_lint.py --update`.",
        ], sites, shrink_only="--seed" not in sys.argv)
        print(f"latent lint: baseline {rows} sites")
        return 0
    if "--report" in sys.argv:
        for rel in sorted(where):
            for n in where[rel]:
                print(f"{rel}:{n}: raw contents walk on a latent holder")
    print(f"latent lint: {len(holders[0])} latent holder roots ({len(holders[1])} opted out), {total} sites in {len(counts)} files, {legacy} legacy contents loops tree-wide")
    failed = check_sites("latent", sites, BASELINE,
                         "go through latent_materialize_all()/latent_entries()/slot_contents()")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
