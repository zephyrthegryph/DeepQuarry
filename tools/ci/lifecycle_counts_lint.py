"""Destroy()-override and qdel()-count lints (roadmap L4, doc/rewrite/lifecycle.md
section 1 and section 8's plan).

The destroy transaction (L1-L3) is meant to shrink both of these over time:

    Destroy() overrides   ~1,190 at the plan's baseline. Target: >= 85% removed;
                          the ~120-180 that remain are real domain consequences
                          and say why with `// ALLOW(lifecycle): <reason>` on
                          the override line (or the comment line before it).
    qdel( call sites      ~3,070 at the plan's baseline (1,241 of them qdel(src)).
                          Target: about half replaced by the verbs in
                          code/datums/lifecycle/verbs.dm (consume(), replace_with(),
                          expire(), slot_clear()/ledger_empty(), delete_on_death).

Both counts are ratcheted: tools/ci/lifecycle_counts_baseline.txt holds the
ceilings, which may fall, never rise. A Destroy() override or qdel( site carrying
`// ALLOW(lifecycle): <reason>` (tools/ci/allow_annotations.py) doesn't count at
all -- it has already justified itself, which is the point.

The ceiling stops new hand-rolled Destroy()s and qdel() sites from accumulating
while L4's conversion agents pay down the existing total; it does not by itself
prove the >= 85%/~50% targets are met (that's `--report`'s totals, tracked over time).

Usage:
    python tools/ci/lifecycle_counts_lint.py            # the CI check
    python tools/ci/lifecycle_counts_lint.py --report   # every site, and the totals
    python tools/ci/lifecycle_counts_lint.py --update   # rewrite the ceilings to today's counts
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed, check_ceilings, read_baseline, write_baseline  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "lifecycle_counts_baseline.txt")

# A Destroy() override: `/type/path/Destroy(` at the start of a line (after
# whitespace), never `/datum/Destroy` or `/atom/movable/Destroy` etc. --
# those base definitions *are* the transaction's phase 7 call site, not an
# "override" in the sense this lint (and the plan's count) means.
DESTROY_OVERRIDE = re.compile(r"^/[\w/]+/Destroy\s*\(")
BASE_DESTROY_OWNERS = {
    "/datum", "/atom", "/atom/movable", "/obj", "/mob", "/turf", "/area",
}
QDEL_CALL = re.compile(r"(?<![\w.])qdel\s*\(")
EXEMPT_FILES = {
    # The engine itself: qdel() can't count its own call to Destroy(), and
    # the destroy-transaction/links/verbs files call qdel() as their
    # mechanism, not as a "should this become a verb" site.
    "code/controllers/subsystems/garbage.dm",
    "code/datums/lifecycle/transaction.dm",
    "code/datums/lifecycle/links.dm",
    "code/datums/lifecycle/verbs.dm",
    "code/datums/containment/lifecycle.dm",
}
# Macro *definitions* (QDEL_NULL(x), QDEL_LIST(L), ...) mention qdel( in their
# own body; that's the macro's plumbing, not a call site in game logic.
EXEMPT_DIRS = ("code/__defines/",)


def owner_of(header):
    """`/obj/item/foo/Destroy(` -> `/obj/item/foo`."""
    return header[: header.rindex("/Destroy")]


def scan_file(path):
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    if "/unit_tests/" in rel:
        return rel, [], []
    with open(path, encoding="utf-8", errors="replace") as handle:
        raw = handle.read()
    lines = code_only(raw).split("\n")
    # code_only() blanks comments, so the ALLOW(lifecycle) reason is read from the raw text.
    raw_lines = raw.split("\n")
    destroys, qdels = [], []
    for no, raw in enumerate(lines, 1):
        text = raw.strip()
        m = DESTROY_OVERRIDE.match(text)
        kept = allowed(raw_lines, no, "lifecycle")
        if m and owner_of(text[: text.index("(")]) not in BASE_DESTROY_OWNERS and not kept:
            destroys.append((rel, no, text[: text.index("(") + 1]))
        if rel not in EXEMPT_FILES and not rel.startswith(EXEMPT_DIRS) and not kept:
            for _ in QDEL_CALL.finditer(text):
                qdels.append((rel, no, "qdel("))
    return rel, destroys, qdels


def scan():
    destroy_counts, qdel_counts = {}, {}
    destroy_sites, qdel_sites = [], []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel, destroys, qdels = scan_file(path)
        if destroys:
            destroy_counts[rel] = len(destroys)
            destroy_sites.extend(destroys)
        if qdels:
            qdel_counts[rel] = len(qdels)
            qdel_sites.extend(qdels)
    return destroy_counts, destroy_sites, qdel_counts, qdel_sites


def main(argv):
    destroy_counts, destroy_sites, qdel_counts, qdel_sites = scan()
    destroy_total, qdel_total = sum(destroy_counts.values()), sum(qdel_counts.values())
    counts = {"destroy": destroy_total, "qdel": qdel_total}
    if "--update" in argv:
        write_baseline(BASELINE, [
            "Destroy()-override and qdel()-count ceilings (roadmap L4, doc/rewrite/lifecycle.md",
            "sec 1, sec 8). tools/ci/lifecycle_counts_lint.py fails when a count rises above its",
            "line. A site with `// ALLOW(lifecycle): <reason>` doesn't count at all.",
            "Lower after a sweep: `python tools/ci/lifecycle_counts_lint.py --update`.",
        ], counts)
        print("lifecycle counts baseline: %d Destroy() overrides, %d qdel( sites" % (destroy_total, qdel_total))
        return 0
    if "--report" in argv:
        for rel, number, what in destroy_sites:
            print("destroy %s:%d: %s" % (rel, number, what))
        for rel, number, what in qdel_sites:
            print("qdel %s:%d: %s" % (rel, number, what))
        print("total: %d unjustified Destroy() overrides in %d files, %d qdel( sites in %d files"
              % (destroy_total, len(destroy_counts), qdel_total, len(qdel_counts)))
        return 0
    failed = check_ceilings(
        "lifecycle", counts, read_baseline(BASELINE),
        "Remove a new Destroy() or fold it into a declared relationship/policy (L1-L3); replace a new "
        "qdel( with consume()/replace_with()/expire()/slot_clear()/ledger_empty()/delete_on_death "
        "(code/datums/lifecycle/verbs.dm).")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
