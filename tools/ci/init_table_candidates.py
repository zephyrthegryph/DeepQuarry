"""Finds obj types whose whole Initialize() chain is table-expressible (sec 3.1 of
doc/rewrite/init_and_turfs.md, Phase 4 track 4c).

A type qualifies when neither it nor any subtype overrides Initialize() or
LateInitialize(), and every Initialize() override on its ancestors is one that
table_initialize() mirrors (MIRRORED below). SSatoms.InitAtom() can then run
table_initialize() in place of the proc chain and its arglist.

The tool reports the maximal qualifying types (those whose parent does not
qualify) and, with --write, regenerates code/game/atom/init_from_table_types.dm,
which turns init_from_table on for them. A type that later gains an override is
caught by tools/ci/init_lint.py (`table_init_overrides`, ceiling 0); rerun
--write to drop it from the list.

Usage:
    python tools/ci/init_table_candidates.py           # summary by root
    python tools/ci/init_table_candidates.py --list    # every maximal type
    python tools/ci/init_table_candidates.py --write   # regenerate the list file
    python tools/ci/init_table_candidates.py --check   # fail if the file is stale
"""
import collections
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "code", "game", "atom", "init_from_table_types.dm")
OUT_REL = "code/game/atom/init_from_table_types.dm"

# Types whose Initialize() override has a table_initialize() mirror running the same setup.
MIRRORED = {"/atom", "/atom/movable", "/obj", "/obj/effect", "/obj/structure"}
# Roots the tool may flag. Machinery, items and mobs carry per-instance setup in their bases.
ROOTS = ("/obj/effect", "/obj/structure")

TYPE_BLOCK = re.compile(r"^(/[\w/]+?)\s*(//.*)?$")
PROC_DEF = re.compile(r"^(/[\w/]+?)/(?:(?:proc|verb)/)?(\w+)\s*\(")
VAR_DEF = re.compile(r"^(/[\w/]+?)/var/")
TABLE_FLAG = re.compile(r"^\s+init_from_table\s*=\s*(TRUE|FALSE|1|0)\b")
INIT_PROCS = ("Initialize", "LateInitialize")


def dm_files():
    for top in ("code", "maps"):
        for base, _dirs, files in os.walk(os.path.join(ROOT, top)):
            for name in files:
                if name.endswith(".dm"):
                    path = os.path.join(base, name)
                    yield os.path.relpath(path, ROOT).replace(os.sep, "/"), path


def built_code_files():
    """code/ files the build includes; types defined only elsewhere are never flagged."""
    built = set()
    with open(os.path.join(ROOT, "deepquarry.dme"), encoding="utf-8", errors="replace") as handle:
        for line in handle:
            found = re.match(r'\s*#include\s+"(code\\[^"]+\.dm)"', line)
            if found:
                built.add(found.group(1).replace("\\", "/"))
    return built


def scan():
    built = built_code_files()
    types = set()
    overrides = set()
    explicit = {}
    for rel, path in dm_files():
        if rel == OUT_REL:
            continue
        # Overrides count from every file (conservative); types only from built code files.
        eligible = rel in built
        with open(path, encoding="utf-8", errors="replace") as handle:
            block = None
            for line in handle:
                line = line.rstrip("\n")
                proc = PROC_DEF.match(line)
                if proc:
                    block = None
                    owner = proc.group(1)
                    if eligible:
                        types.add(owner)
                    if proc.group(2) in INIT_PROCS:
                        overrides.add(owner)
                    continue
                var = VAR_DEF.match(line)
                if var:
                    if eligible:
                        types.add(var.group(1))
                    continue
                head = TYPE_BLOCK.match(line)
                if head:
                    block = head.group(1)
                    if eligible:
                        types.add(block)
                    continue
                if line and not line[0].isspace():
                    block = None
                flag = TABLE_FLAG.match(line)
                if flag and block:
                    explicit[block] = flag.group(1) in ("TRUE", "1")
    return types, overrides, explicit


def parent(path):
    return path.rsplit("/", 1)[0] if path.count("/") > 1 else None


def candidates():
    types, overrides, explicit = scan()
    # Every ancestor path exists as a type.
    for path in list(types):
        node = parent(path)
        while node:
            types.add(node)
            node = parent(node)
    dirty_subtree = set()
    for path in overrides:
        node = path
        while node:
            dirty_subtree.add(node)
            node = parent(node)
    def chain_ok(path):
        node = parent(path)
        while node:
            if node in overrides and node not in MIRRORED:
                return False
            node = parent(node)
        return True
    def qualifies(path):
        return path.startswith(ROOTS) and path not in ROOTS and path not in dirty_subtree \
            and explicit.get(path) is not False and chain_ok(path)
    good = {p for p in types if qualifies(p)}
    maximal = sorted(p for p in good if parent(p) not in good)
    covered = collections.Counter()
    for p in good:
        covered["/".join(p.split("/")[:3])] += 1
    return maximal, covered, len(good)


def render(maximal):
    lines = [
        "// GENERATED by tools/ci/init_table_candidates.py --write. Do not edit by hand.",
        "// Types whose whole Initialize() chain is table-expressible (doc/rewrite/init_and_turfs.md",
        "// sec 3.1): SSatoms.InitAtom() runs table_initialize() instead of the proc chain.",
        "// A type that gains an Initialize() override fails the init lint",
        "// (`table_init_overrides`); rerun the tool to drop it from this list.",
        "",
    ]
    for path in maximal:
        lines.append(path)
        lines.append("\tinit_from_table = TRUE")
        lines.append("")
    return "\n".join(lines)


def main():
    maximal, covered, total = candidates()
    text = render(maximal)
    if "--write" in sys.argv:
        with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print("init_table_candidates: wrote %d types (%d covered with subtypes)" % (len(maximal), total))
        return 0
    if "--check" in sys.argv:
        current = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if current != text:
            print("init_table_candidates: %s is stale; run python tools/ci/init_table_candidates.py --write" % OUT_REL)
            return 1
        return 0
    if "--list" in sys.argv:
        print("\n".join(maximal))
    for root, count in sorted(covered.items()):
        print("%6d  %s" % (count, root))
    print("maximal: %d, covered: %d" % (len(maximal), total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
