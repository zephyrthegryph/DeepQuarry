"""Destroy()-override ban and qdel()-count lint (roadmap L4 and completion plan
section 3.5, doc/rewrite/lifecycle.md).

    Destroy() overrides   banned outright outside CORE_DESTROY_OWNERS (the core
                          chain /datum, /atom, /atom/movable, /client, and the
                          MC's /datum/controller tree). A type's teardown is a
                          declaration (DECLARE_REF), a phase hook (lifecycle_unbind(),
                          lifecycle_dematerialize(), lifecycle_prerelease(),
                          destroy_effects()), its destroy hook on_destroy(), a
                          behaviour's on_entity_destroy(E), destroy_hint for the GC
                          hint, or lifecycle_keep() / LIFECYCLE_KEEP_UNLESS_FORCED
                          to refuse deletion. No ALLOW escape; unit tests included.
    qdel( call sites      ~3,070 at the plan's baseline (1,241 of them qdel(src)).
                          Target: about half replaced by the verbs in
                          code/datums/lifecycle/verbs.dm (consume(), replace_with(),
                          expire(), slot_clear()/ledger_empty(), delete_on_death).

The qdel( count is ratcheted: tools/ci/lifecycle_counts_baseline.txt holds each
baselined site (file + line text) and only shrinks. A qdel( site carrying
`// ALLOW(lifecycle): <reason>` (tools/ci/allow_annotations.py) doesn't count.

The ceiling stops new hand-rolled Destroy()s and qdel() sites from accumulating
while L4's conversion agents pay down the existing total; it does not by itself
prove the >= 85%/~50% targets are met (that's `--report`'s totals, tracked over time).

Usage:
    python tools/ci/lifecycle_counts_lint.py            # the CI check
    python tools/ci/lifecycle_counts_lint.py --report   # every site, and the totals
    python tools/ci/lifecycle_counts_lint.py --update   # drop fixed sites from the baseline (never adds)
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed, check_sites, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "lifecycle_counts_baseline.txt")

# A Destroy() override: `/type/path/Destroy(` at the start of a line.
DESTROY_OVERRIDE = re.compile(r"^/[\w/]+/Destroy\s*\(")
# The core Destroy() chain phase 7 calls after on_destroy(). Nothing else may
# override Destroy(). `/datum/proc` is /datum's own definition.
CORE_DESTROY_OWNERS = {"/datum/proc", "/datum", "/atom", "/atom/movable", "/client"}
CORE_DESTROY_PREFIXES = ("/datum/controller",)


def core_destroy_owner(owner):
    return owner in CORE_DESTROY_OWNERS or owner.startswith(CORE_DESTROY_PREFIXES)
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
    tests = "/unit_tests/" in rel
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
        if m and not core_destroy_owner(owner_of(text[: text.index("(")])):
            destroys.append((rel, no, text[: text.index("(") + 1]))
        if not tests and rel not in EXEMPT_FILES and not rel.startswith(EXEMPT_DIRS) and not kept:
            for _ in QDEL_CALL.finditer(text):
                qdels.append((rel, no, "qdel("))
    return rel, destroys, qdels


def scan():
    destroy_counts, qdel_counts = {}, {}
    destroy_sites, qdel_sites = [], []
    paths = glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)
    paths += glob.glob(os.path.join(ROOT, "maps", "**", "*.dm"), recursive=True)
    for path in paths:
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
    if "--update" in argv or "--seed" in argv:
        write_sites(BASELINE, [
            "qdel( sites (roadmap L4, doc/rewrite/lifecycle.md sec 1, sec 8). rule<TAB>file<TAB>normalized line.",
            "tools/ci/lifecycle_counts_lint.py fails on a site not listed here (Destroy() overrides are",
            "banned outright). A site with `// ALLOW(lifecycle): <reason>` doesn't count.",
            "Shrink-only: after a sweep, `python tools/ci/lifecycle_counts_lint.py --update`.",
        ], {"qdel": qdel_sites}, shrink_only="--seed" not in argv)
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
    for rel, number, what in destroy_sites:
        print("%s:%d: %s -- Destroy() overrides are banned outside the core chain; use DECLARE_REF "
              "declarations, a phase hook, on_destroy(), destroy_hint or lifecycle_keep() "
              "(code/datums/lifecycle/transaction.dm)" % (rel, number, what))
    failed = check_sites(
        "lifecycle", {"qdel": qdel_sites}, BASELINE,
        "use consume()/replace_with()/expire()/slot_clear()/ledger_empty()/delete_on_death "
        "(code/datums/lifecycle/verbs.dm)")
    return 1 if failed or destroy_sites else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
