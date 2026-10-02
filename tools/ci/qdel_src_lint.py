"""Raw `qdel(src)` ratchet (unified plan sec 2.18, doc/rewrite/lifecycle.md sec 5).

A thing that deletes itself is saying *why* through a verb, not through the engine call:

    consume(item, actor)   an item used up by an action
    replace_with(path)     a successor takes its place
    expire(after)          an effect or projectile ends its life
    slot_clear / ledger_empty   a held or stored thing leaves its holder
    (an owned child needs no call at all: the destroy sequence disposes of it)

`qdel(src)` stays only where the reason is genuinely "destroy this now"; such a site
carries `// ALLOW(lifecycle): <reason>` (tools/ci/allow_annotations.py) and doesn't count.
This lint is the `qdel(src)` slice of the qdel( ratchet: tools/ci/lifecycle_counts_lint.py counts
every other `qdel(` site and leaves `qdel(src)` to this lint, so a site is in one baseline and the
slice's size is visible on its own; a self-deleting site can't be added while the old ones are
still being converted.

The baseline holds each site as (file, line text); a file's count can only fall.

Usage:
    python tools/ci/qdel_src_lint.py            # the CI check
    python tools/ci/qdel_src_lint.py --report   # every site, and the totals per folder
    python tools/ci/qdel_src_lint.py --update   # drop fixed sites from the baseline (never adds)
    python tools/ci/qdel_src_lint.py --seed     # create the baseline from the current sites
"""
import glob
import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed, check_sites, exempt_path, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "qdel_src_baseline.txt")

# `qdel(src)` and `qdel(src, force = TRUE)`, but not `qdel(src.thing)` or `foo.qdel(src)`.
QDEL_SRC = re.compile(r"(?<![\w.])qdel\s*\(\s*src\s*[,)]")
EXEMPT_FILES = {
    # The engine and the verbs call qdel(src) as their mechanism.
    "code/controllers/subsystems/garbage.dm",
    "code/datums/lifecycle/transaction.dm",
    "code/datums/lifecycle/links.dm",
    "code/datums/lifecycle/verbs.dm",
    "code/datums/containment/lifecycle.dm",
}
EXEMPT_DIRS = ("code/__defines/",)


def scan_file(path):
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    if exempt_path(rel) or rel in EXEMPT_FILES or rel.startswith(EXEMPT_DIRS):
        return rel, []
    with open(path, encoding="utf-8", errors="replace") as handle:
        raw = handle.read()
    raw_lines = raw.split("\n")
    sites = []
    for no, line in enumerate(code_only(raw).split("\n"), 1):
        if QDEL_SRC.search(line) and not allowed(raw_lines, no, "lifecycle"):
            sites.append((rel, no, "qdel(src)"))
    return rel, sites


def scan():
    sites = []
    paths = glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)
    paths += glob.glob(os.path.join(ROOT, "maps", "**", "*.dm"), recursive=True)
    for path in paths:
        sites.extend(scan_file(path)[1])
    return sites


def main(argv):
    sites = scan()
    if "--update" in argv or "--seed" in argv:
        write_sites(BASELINE, [
            "Raw qdel(src) sites (unified plan sec 2.18). rule<TAB>file<TAB>normalized line.",
            "tools/ci/qdel_src_lint.py fails on a site not listed here. A site with",
            "`// ALLOW(lifecycle): <reason>` doesn't count.",
            "Shrink-only: after a sweep, `python tools/ci/qdel_src_lint.py --update`.",
        ], {"qdel_src": sites}, shrink_only="--seed" not in argv)
        print("qdel(src) baseline: %d sites" % len(sites))
        return 0
    if "--report" in argv:
        per_folder = Counter()
        for rel, number, what in sites:
            print("%s:%d: %s" % (rel, number, what))
            per_folder["/".join(rel.split("/")[:3])] += 1
        for folder, count in per_folder.most_common(15):
            print("  %5d  %s" % (count, folder))
        print("total: %d qdel(src) sites in %d files" % (len(sites), len({s[0] for s in sites})))
        return 0
    failed = check_sites(
        "qdel_src", {"qdel_src": sites}, BASELINE,
        "say why the thing ends: consume() / replace_with() / expire() / slot_clear() / "
        "ledger_empty() (code/datums/lifecycle/verbs.dm); a real destroy-now keeps qdel(src) "
        "with `// ALLOW(lifecycle): <reason>`")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
