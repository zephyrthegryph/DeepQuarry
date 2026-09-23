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
A line that already goes through the API may say so with `// latent-ok`.

Existing sites are counted per file in tools/ci/latent_allowlist.txt; a file
may not gain sites. Run with --update to rewrite the allowlist (only ever to
lower counts or add files you have fixed). It also prints the number of legacy
`contents` loops over the whole tree, for the record.
"""
import os
import re
import sys
from collections import Counter

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "latent_allowlist.txt")
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
    for number, line in enumerate(read(path), 1):
        if "latent-ok" in line:
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
    if "--update" in sys.argv:
        with open(ALLOWLIST, "w", encoding="utf-8", newline="\n") as handle:
            handle.write("# Raw contents walks on latent holders, per file (tools/ci/latent_lint.py).\n")
            handle.write("# Counts may only go down. Fix a site by going through the ledger API.\n")
            for rel in sorted(counts):
                handle.write(f"{rel} {counts[rel]}\n")
        print(f"latent lint: wrote {len(counts)} files, {sum(counts.values())} sites")
        return 0
    allowed = {}
    if os.path.exists(ALLOWLIST):
        for line in read(ALLOWLIST):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            rel, count = line.rsplit(" ", 1)
            allowed[rel] = int(count)
    failed = False
    for rel in sorted(counts):
        if counts[rel] > allowed.get(rel, 0):
            failed = True
            lines = ", ".join(str(n) for n in where[rel])
            print(f"{rel}: {counts[rel]} raw contents walk(s) on latent holders (allowed {allowed.get(rel, 0)}), lines {lines}")
    for rel in sorted(allowed):
        if counts.get(rel, 0) < allowed[rel]:
            print(f"note: {rel} is down to {counts.get(rel, 0)} (allowlist says {allowed[rel]}); lower it")
    print(f"latent lint: {len(holders[0])} latent holder roots ({len(holders[1])} opted out), {sum(counts.values())} allowlisted sites in {len(counts)} files, {legacy} legacy contents loops tree-wide")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
