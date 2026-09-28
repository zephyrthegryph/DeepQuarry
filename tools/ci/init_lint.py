"""Initialize() ratchet (Phase 4 track 4c, doc/rewrite/init_and_turfs.md sec 3.6).

Initialize() should only set the instance's own state: what differs between two
instances of a type. Type-level facts belong in the type table
(code/game/atom/atom_type_table.dm), world registration in on_materialize()
(code/game/atom/atom_materialize.dm), and interaction-only setup behind a
first-use accessor. This lint ratchets four counts:

    initialize          `/type/Initialize(` overrides
    late_initialize     `/type/LateInitialize(` overrides
    unreasoned          overrides with no `// INIT: <reason>` naming the
                        per-instance state they set, on the header line or the
                        comment line directly above it
    world_reads         lines inside an Initialize() body that reach outside
                        the instance: range(, orange(, view(, GetAbove,
                        GetBelow, GLOB., START_PROCESSING
    turf_on_materialize `/turf/.../on_materialize(` overrides. Ceiling 0:
                        SSatoms.InitAtom() flags a turf whose type table
                        needs no work as materialized without calling
                        on_materialize(), so a turf override would be skipped.
    table_init_overrides
                        Initialize()/LateInitialize() overrides on a type that
                        inherits `init_from_table = TRUE` (atom_type_table.dm).
                        Ceiling 0: InitAtom() skips Initialize() for such a
                        type, so the override must set it back to FALSE.

A line or override carrying `// ALLOW(init): <reason>` does not count
(tools/ci/allow_annotations.py). The counts live in
tools/ci/init_baseline.txt and may fall, never rise.

Usage:
    python tools/ci/init_lint.py            # the CI check
    python tools/ci/init_lint.py --report   # every site
    python tools/ci/init_lint.py --update   # rewrite the ceilings to today's counts
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from allow_annotations import allowed, check_ceilings, read_baseline, write_baseline  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "init_baseline.txt")

INIT_HEADER = re.compile(r"^(/[\w/]+)/Initialize\s*\(")
LATE_HEADER = re.compile(r"^(/[\w/]+)/LateInitialize\s*\(")
TURF_MATERIALIZE = re.compile(r"^/turf(/[\w/]*)?/on_materialize\s*\(")
REASON = re.compile(r"//\s*INIT:\s*\S")
WORLD_READ = re.compile(r"(?<![\w.])(?:o?range|view)\s*\(|\bGetAbove\s*\(|\bGetBelow\s*\(|\bGLOB\.|\bSTART_PROCESSING\s*\(")
# Unit tests and benchmarks build worlds on purpose.
EXEMPT_PREFIXES = ("code/modules/unit_tests/", "code/modules/benchmarks/")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read().splitlines()


def dm_files():
    for top in ("code", "maps"):
        for base, _dirs, files in os.walk(os.path.join(ROOT, top)):
            for name in files:
                if name.endswith(".dm"):
                    yield os.path.join(base, name)


TYPE_BLOCK = re.compile(r"^(/[\w/]+)\s*(//.*)?$")
TABLE_FLAG = re.compile(r"^\s+init_from_table\s*=\s*(TRUE|FALSE|1|0)\b")


def table_init_violations(files):
    """Overrides whose type inherits init_from_table = TRUE, as (rel, line) pairs."""
    flags = {}
    headers = []
    for rel, lines in files:
        block = None
        for number, line in enumerate(lines, 1):
            head = TYPE_BLOCK.match(line)
            if head and "(" not in line:
                block = head.group(1)
                continue
            if line and not line[0].isspace():
                block = None
            flag = TABLE_FLAG.match(line)
            if flag and block:
                flags[block] = flag.group(1) in ("TRUE", "1")
            header = INIT_HEADER.match(line) or LATE_HEADER.match(line)
            if header and not allowed(lines, number, "init"):
                headers.append((rel, number, header.group(1)))
    found = []
    for rel, number, path in headers:
        parts = path.split("/")
        for cut in range(len(parts), 1, -1):
            ancestor = "/".join(parts[:cut])
            if ancestor in flags:
                # The type that turns the flag on keeps its Initialize() as the fallback
                # (a colour or extra New() args) and mirrors it in table_initialize().
                if flags[ancestor] and cut != len(parts):
                    found.append((rel, number))
                break
    return found


def scan(lines):
    sites = {"initialize": [], "late_initialize": [], "unreasoned": [], "world_reads": [], "turf_on_materialize": []}
    in_init = False
    for number, line in enumerate(lines, 1):
        if TURF_MATERIALIZE.match(line):
            sites["turf_on_materialize"].append(number)
        init = INIT_HEADER.match(line)
        late = LATE_HEADER.match(line)
        if init or late:
            in_init = bool(init)
            if allowed(lines, number, "init"):
                continue
            sites["initialize" if init else "late_initialize"].append(number)
            above = lines[number - 2] if number > 1 else ""
            if not REASON.search(line) and not (above.lstrip().startswith("//") and REASON.search(above)):
                sites["unreasoned"].append(number)
            continue
        if line and not line[0].isspace() and not line.startswith("//"):
            in_init = False
            continue
        if in_init:
            code = line.split("//", 1)[0]
            if WORLD_READ.search(code) and not allowed(lines, number, "init"):
                sites["world_reads"].append(number)
    return sites


def main():
    totals = {"initialize": 0, "late_initialize": 0, "unreasoned": 0, "world_reads": 0, "turf_on_materialize": 0}
    where = []
    files = []
    for path in dm_files():
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        lines = read(path)
        files.append((rel, lines))
        if rel.startswith(EXEMPT_PREFIXES):
            continue
        for kind, numbers in scan(lines).items():
            totals[kind] += len(numbers)
            where.extend((rel, n, kind) for n in numbers)
    violations = table_init_violations(files)
    totals["table_init_overrides"] = len(violations)
    where.extend((rel, n, "table_init_overrides") for rel, n in violations)
    if "--update" in sys.argv:
        write_baseline(BASELINE, [
            "Initialize() ratchet (tools/ci/init_lint.py, doc/rewrite/init_and_turfs.md sec 3.6).",
            "May fall, never rise. Move type facts to the type table and registration to on_materialize(),",
            "then `python tools/ci/init_lint.py --update`.",
        ], totals)
        print("init lint: baseline written: %s" % totals)
        return 0
    if "--report" in sys.argv:
        for rel, n, kind in sorted(where):
            print("%s:%d: %s" % (rel, n, kind))
    failed = check_ceilings("init", totals, read_baseline(BASELINE),
                            "Give a new override `// INIT: <reason>`, or move the work to the type table / on_materialize().")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
