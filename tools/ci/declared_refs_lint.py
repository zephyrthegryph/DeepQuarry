"""Declared-reference lint (roadmap L2, doc/rewrite/lifecycle.md section 4).

Every object-typed var on a datum is declared as exactly one kind:

    slot content        lives in a ledger slot (containment.md sec 2) -- not a
                         var at all from this lint's point of view, so nothing
                         to declare; skipped automatically (see NOTE below)
    REF_OWNED            a non-contained child, deleted in phase 4 --
                         declared_owned_vars()
    REF_OWNED_LIST       a list of them -- declared_owned_list_vars()
    REF_PAIR             two-sided, kept in sync by link_set()/link_clear() --
                         declared_pair_vars()
    REF_BACKLIST         membership in another object's list -- declared_backlist_vars()
    weak                 var/datum/weakref/... -- resolved on read, never cleaned
    tmp cache            `tmp` (or `static`/`global`/`const`) -- scrubbed or shared,
                         not a per-instance relationship at all

This finds every var declared directly on a type (not inherited -- each var is
only ever checked at the type that first declares it) whose declared type is
an object reference, that isn't `tmp`/`static`/`global`/`const` and isn't a
`/datum/weakref`, and checks whether the *same file* declares that type's
declared_owned_vars() / declared_owned_list_vars() / declared_pair_vars() /
declared_backlist_vars() mentioning the var by name. A var that isn't
mentioned in any of those is undeclared.

NOTE: this can't see slot content (a slot holds a *thing*, not a *var* --
membership lives in the ledger, code/datums/containment/ledger.dm), so a
holder's contents never need a declared_*_vars() entry and are never flagged.

DQ Medical's areas (body, organs, surgery, medical, protean, mind_body) are
excluded outright, not ratcheted (doc sec 4, sec 7): they plug into the same
phases on their own schedule (O2 etc.), and this lint isn't theirs to pass yet.

Legacy undeclared vars everywhere else are listed per file with a count in
tools/ci/declared_refs_allowlist.txt, the same ratchet C11/campaign lints
already use: a file may not gain vars above its count.

Usage:
    python tools/ci/declared_refs_lint.py            # the CI check
    python tools/ci/declared_refs_lint.py --report   # every var, and the total
    python tools/ci/declared_refs_lint.py --update   # rewrite the allowlist to today's counts
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import REF_ROOTS, code_only, under  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "declared_refs_allowlist.txt")

# DQ Medical's own tracks (doc/rewrite/lifecycle.md sec 4, sec 7): excluded
# outright, not ratcheted. Path prefixes, relative to the repo root.
EXCLUDED_DIRS = (
    "code/modules/body/",
    "code/modules/organs/",
    "code/modules/surgery/",
    "code/modules/medical/",
    "code/modules/mind_body/",
    "code/modules/mob/living/carbon/human/species/station/protean/",
)

UNSAVED_MODS = {"tmp", "static", "global", "const", "final"}
DECLARED_PROCS = (
    "declared_owned_vars",
    "declared_owned_list_vars",
    "declared_pair_vars",
    "declared_backlist_vars",
)

TYPE_HEADER = re.compile(r"^(/[A-Za-z_][\w/]*)\s*$")
PROC_HEADER = re.compile(r"^(/[\w/]*?)/(proc/)?(" + "|".join(DECLARED_PROCS) + r")\s*\(")
VAR_LINE = re.compile(r"^var((?:/[A-Za-z_]\w*)+)\s*(?:=|$)")
STRING_LIT = re.compile(r'"([^"]*)"')


def is_excluded(rel):
    return any(rel.startswith(prefix) for prefix in EXCLUDED_DIRS)


def split_var(segs):
    """('tmp', 'obj', 'item', 'child') -> (mods, vtype, name, is_list), or None."""
    segs = list(segs)
    mods = set()
    while segs and segs[0] in UNSAVED_MODS:
        mods.add(segs.pop(0))
    if not segs:
        return None
    name = segs[-1]
    tsegs = segs[:-1]
    is_list = bool(tsegs) and tsegs[0] == "list"
    if is_list:
        tsegs = tsegs[1:]
    vtype = "/" + "/".join(tsegs) if tsegs else ""
    return mods, vtype, name, is_list


def declared_names(body_lines):
    """Every quoted string literal across a proc body's lines (its declared
    list of var names -- see the file header's declared_owned_vars() etc.)."""
    names = set()
    for line in body_lines:
        names.update(STRING_LIT.findall(line))
    return names


def scan_file(path):
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(path, encoding="utf-8", errors="replace") as handle:
        raw_lines = code_only(handle.read()).split("\n")

    # Pass 1: every declared_*_vars() proc body, by owner type, as the union
    # of every quoted name across every such override for that type (a type
    # may split REF_OWNED/REF_PAIR/etc. across several small overrides).
    declared = {}  # owner type -> set of var names
    cur_owner, cur_proc_indent, capturing = None, None, []
    for raw in raw_lines:
        if not raw.strip():
            continue
        stripped = raw.lstrip("\t ")
        indent = len(raw) - len(stripped)
        if indent == 0:
            if cur_owner is not None:
                declared.setdefault(cur_owner, set()).update(declared_names(capturing))
                cur_owner, capturing = None, []
            m = PROC_HEADER.match(stripped.rstrip())
            if m:
                cur_owner = m.group(1)
        elif cur_owner is not None:
            capturing.append(stripped)
    if cur_owner is not None:
        declared.setdefault(cur_owner, set()).update(declared_names(capturing))

    # Pass 2: every var declared directly in a type block (indent 0 header,
    # indent 1 `var/...` lines -- the common declaration style throughout
    # this codebase; a `var\n\tfoo = ...` block form is rare enough for this
    # ratcheted, best-effort lint to simply miss, same tradeoff
    # containment_lint.py/lifecycle_lint.py already accept).
    sites = []
    cur_type = None
    for no, raw in enumerate(raw_lines, 1):
        if not raw.strip():
            continue
        stripped = raw.lstrip("\t ")
        indent = len(raw) - len(stripped)
        text = stripped.rstrip()
        if indent == 0:
            m = TYPE_HEADER.match(text)
            cur_type = m.group(1) if m else None
            continue
        if indent != 1 or cur_type is None:
            continue
        m = VAR_LINE.match(text)
        if not m:
            continue
        parsed = split_var(m.group(1).strip("/").split("/"))
        if not parsed:
            continue
        mods, vtype, name, _is_list = parsed
        if mods & UNSAVED_MODS:
            continue
        if not under(vtype, REF_ROOTS) or under(vtype, ("/datum/weakref",)):
            continue
        if name in declared.get(cur_type, ()):
            continue
        sites.append((rel, no, "%s var/%s/%s" % (cur_type, vtype.strip("/"), name)))
    return rel, sites


def scan():
    counts, all_sites = {}, []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if is_excluded(rel) or "/unit_tests/" in rel:
            continue
        rel, sites = scan_file(path)
        if not sites:
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
        "# Undeclared object-typed vars (roadmap L2, doc/rewrite/lifecycle.md sec 4).",
        "# tools/ci/declared_refs_lint.py reads this file: a file may not exceed its",
        "# count, and files not listed may have none. Declare the var as REF_OWNED/",
        "# REF_OWNED_LIST/REF_PAIR/REF_BACKLIST (or make it tmp, or a weakref) and",
        "# lower the count; `python tools/ci/declared_refs_lint.py --update` rewrites it.",
        "# DQ Medical's areas are excluded outright, not listed here.",
        "# Total: %d vars in %d files." % (sum(counts.values()), len(counts)),
    ]
    for path in sorted(counts):
        lines.append("%s %d" % (path, counts[path]))
    with open(ALLOWLIST, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def main(argv):
    counts, sites = scan()
    total = sum(counts.values())
    if "--update" in argv:
        write_allowlist(counts)
        print("declared-refs allowlist: %d vars in %d files" % (total, len(counts)))
        return 0
    if "--report" in argv:
        for rel, number, what in sites:
            print("%s:%d: %s" % (rel, number, what))
        print("total: %d undeclared object-typed vars in %d files" % (total, len(counts)))
        return 0
    allowed = read_allowlist()
    failures, lowered = [], []
    for rel in sorted(counts):
        limit = allowed.get(rel, 0)
        if counts[rel] > limit:
            where = ["%s:%d: %s" % s for s in sites if s[0] == rel]
            failures.append(
                "%s has %d undeclared object-typed var(s), allowed %d. Declare each as "
                "REF_OWNED/REF_OWNED_LIST/REF_PAIR/REF_BACKLIST (code/datums/lifecycle/links.dm), "
                "tmp, or a weakref:\n    %s" % (rel, counts[rel], limit, "\n    ".join(where))
            )
        elif counts[rel] < limit:
            lowered.append("%s: %d (allowlist says %d)" % (rel, counts[rel], limit))
    for rel in sorted(allowed):
        if rel not in counts:
            lowered.append("%s: 0 (allowlist says %d)" % (rel, allowed[rel]))
    print("declared-refs lint: %d undeclared object-typed vars in %d files (allowlisted: %d)"
          % (total, len(counts), sum(allowed.values())))
    if lowered:
        print("These files dropped below their allowlisted count; lower it with --update:")
        for line in lowered:
            print("    " + line)
    if failures:
        for failure in failures:
            print("FAIL: " + failure)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
