"""Destroy()-override and qdel()-count lints (roadmap L4, doc/rewrite/lifecycle.md
section 1 and section 8's plan).

The destroy transaction (L1-L3) is meant to shrink both of these over time:

    Destroy() overrides   ~1,190 at the plan's baseline. Target: >= 85% removed;
                          the ~120-180 that remain are real domain consequences
                          and should say why with a `// LIFECYCLE:` comment on
                          the override line (or the line before it).
    qdel( call sites      ~3,070 at the plan's baseline (1,241 of them qdel(src)).
                          Target: about half replaced by the verbs in
                          code/datums/lifecycle/verbs.dm (consume(), replace_with(),
                          expire(), slot_clear()/ledger_empty(), delete_on_death).

Both counts are ratcheted per file the same way containment_lint.py/
declared_refs_lint.py already ratchet theirs: a file may not gain sites above
its count in tools/ci/lifecycle_counts_allowlist.txt. A Destroy() override
carrying a `// LIFECYCLE:` reason doesn't count against the ratchet at all --
it has already justified itself, which is the point.

This is a per-file count, not a global target: it stops new hand-rolled
Destroy()s and qdel() sites from accumulating while L4's conversion agents pay
down the existing total; it does not by itself prove the >= 85%/~50% targets
are met (that's `--report`'s totals, tracked over time).

Usage:
    python tools/ci/lifecycle_counts_lint.py            # the CI check
    python tools/ci/lifecycle_counts_lint.py --report   # totals for both counts
    python tools/ci/lifecycle_counts_lint.py --update   # rewrite the allowlist to today's counts
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "lifecycle_counts_allowlist.txt")

# A Destroy() override: `/type/path/Destroy(` at the start of a line (after
# whitespace), never `/datum/Destroy` or `/atom/movable/Destroy` etc. --
# those base definitions *are* the transaction's phase 7 call site, not an
# "override" in the sense this lint (and the plan's count) means.
DESTROY_OVERRIDE = re.compile(r"^/[\w/]+/Destroy\s*\(")
BASE_DESTROY_OWNERS = {
    "/datum", "/atom", "/atom/movable", "/obj", "/mob", "/turf", "/area",
}
LIFECYCLE_REASON = re.compile(r"//\s*LIFECYCLE:")
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
        lines = code_only(handle.read()).split("\n")
    destroys, qdels = [], []
    for no, raw in enumerate(lines, 1):
        text = raw.strip()
        m = DESTROY_OVERRIDE.match(text)
        if m and owner_of(text[: text.index("(")]) not in BASE_DESTROY_OWNERS:
            reason_here = LIFECYCLE_REASON.search(text)
            reason_before = no >= 2 and LIFECYCLE_REASON.search(lines[no - 2])
            if not (reason_here or reason_before):
                destroys.append((rel, no, text[: text.index("(") + 1]))
        if rel not in EXEMPT_FILES and not rel.startswith(EXEMPT_DIRS):
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


def read_allowlist():
    destroy_allowed, qdel_allowed = {}, {}
    if not os.path.exists(ALLOWLIST):
        return destroy_allowed, qdel_allowed
    section = None
    with open(ALLOWLIST, encoding="utf-8") as handle:
        for line in handle:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            if line == "[destroy]":
                section = destroy_allowed
                continue
            if line == "[qdel]":
                section = qdel_allowed
                continue
            if section is None:
                continue
            path, count = line.rsplit(None, 1)
            section[path] = int(count)
    return destroy_allowed, qdel_allowed


def write_allowlist(destroy_counts, qdel_counts):
    lines = [
        "# Destroy()-override and qdel()-count ratchets (roadmap L4,",
        "# doc/rewrite/lifecycle.md sec 1, sec 8). tools/ci/lifecycle_counts_lint.py",
        "# reads this file: a file may not exceed its count in either section, and",
        "# files not listed may have none. A Destroy() override with a same-line or",
        "# line-before `// LIFECYCLE: <reason>` comment doesn't count at all.",
        "# `python tools/ci/lifecycle_counts_lint.py --update` rewrites this.",
        "# Destroy total: %d in %d files. qdel total: %d in %d files."
        % (sum(destroy_counts.values()), len(destroy_counts), sum(qdel_counts.values()), len(qdel_counts)),
        "[destroy]",
    ]
    for path in sorted(destroy_counts):
        lines.append("%s %d" % (path, destroy_counts[path]))
    lines.append("[qdel]")
    for path in sorted(qdel_counts):
        lines.append("%s %d" % (path, qdel_counts[path]))
    with open(ALLOWLIST, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def check_section(label, counts, sites, allowed, hint):
    failures, lowered = [], []
    for rel in sorted(counts):
        limit = allowed.get(rel, 0)
        if counts[rel] > limit:
            where = ["%s:%d: %s" % s for s in sites if s[0] == rel]
            failures.append(
                "%s has %d %s, allowed %d. %s:\n    %s"
                % (rel, counts[rel], label, limit, hint, "\n    ".join(where))
            )
        elif counts[rel] < limit:
            lowered.append("%s: %d (allowlist says %d)" % (rel, counts[rel], limit))
    for rel in sorted(allowed):
        if rel not in counts:
            lowered.append("%s: 0 (allowlist says %d)" % (rel, allowed[rel]))
    return failures, lowered


def main(argv):
    destroy_counts, destroy_sites, qdel_counts, qdel_sites = scan()
    destroy_total, qdel_total = sum(destroy_counts.values()), sum(qdel_counts.values())
    if "--update" in argv:
        write_allowlist(destroy_counts, qdel_counts)
        print("lifecycle counts allowlist: %d Destroy() overrides, %d qdel( sites"
              % (destroy_total, qdel_total))
        return 0
    if "--report" in argv:
        for rel, number, what in destroy_sites:
            print("destroy %s:%d: %s" % (rel, number, what))
        for rel, number, what in qdel_sites:
            print("qdel %s:%d: %s" % (rel, number, what))
        print("total: %d unjustified Destroy() overrides in %d files, %d qdel( sites in %d files"
              % (destroy_total, len(destroy_counts), qdel_total, len(qdel_counts)))
        return 0
    destroy_allowed, qdel_allowed = read_allowlist()
    destroy_failures, destroy_lowered = check_section(
        "unjustified Destroy() override(s)", destroy_counts, destroy_sites, destroy_allowed,
        "Remove it, fold it into a declared relationship/policy (L1-L3), or justify it with "
        "a `// LIFECYCLE: <reason>` comment")
    qdel_failures, qdel_lowered = check_section(
        "qdel( site(s)", qdel_counts, qdel_sites, qdel_allowed,
        "Replace it with consume()/replace_with()/expire()/slot_clear()/ledger_empty()/"
        "delete_on_death (code/datums/lifecycle/verbs.dm) where it fits")
    print("lifecycle counts lint: %d Destroy() overrides (allowlisted %d), %d qdel( sites (allowlisted %d)"
          % (destroy_total, sum(destroy_allowed.values()), qdel_total, sum(qdel_allowed.values())))
    for label, lowered in (("Destroy()", destroy_lowered), ("qdel(", qdel_lowered)):
        if lowered:
            print("These files dropped below their allowlisted %s count; lower it with --update:" % label)
            for line in lowered:
                print("    " + line)
    failures = destroy_failures + qdel_failures
    if failures:
        for failure in failures:
            print("FAIL: " + failure)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
