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
    handle               a text var holding om_handle(x) -- resolved on read, never cleaned
    tmp cache            `tmp` (or `static`/`global`/`const`) -- scrubbed or shared,
                         not a per-instance relationship at all

This finds every var declared directly on a type (not inherited -- each var is
only ever checked at the type that first declares it) whose declared type is
an object reference, that isn't `tmp`/`static`/`global`/`const`, and checks whether the *same file* declares that type's
declared_owned_vars() / declared_owned_list_vars() / declared_pair_vars() /
declared_backlist_vars() mentioning the var by name. A var that isn't
mentioned in any of those is undeclared.

NOTE: this can't see slot content (a slot holds a *thing*, not a *var* --
membership lives in the ledger, code/datums/containment/ledger.dm), so a
holder's contents never need a declared_*_vars() entry and are never flagged.

Medical, body, organs, surgery, protean and mind_body are included like
everything else (doc sec 7). tools/ci/scheduler_lints.py's LC-refs count is
the stricter successor (tmp vars count there too).

Legacy undeclared vars everywhere else are listed per file with a count in
tools/ci/declared_refs_allowlist.txt, the same ratchet C11/campaign lints
already use: a file may not gain vars above its count.

Object-keyed lists. An instance list var must not collect objects (as keys or
values: `L[obj] = ...`, `L[key] = obj`, `L += obj`, `L |= obj`, `L = list(obj = ...)`)
unless it is declared: an owned-children list (declared_owned_list_vars()), the
list side of a backlist (named as the list var by some declared_backlist_vars()),
or a declared cache (declared_cache_vars()). Relations and slots are not vars, and
registries are global. "An object" is recognised syntactically: `src`, `usr`, a
`new` expression, or a name the proc declares object-typed (an argument such as
`mob/M`, a `var/obj/item/I` local, a `for(var/atom/A in ...)` loop var). These are
ratcheted per file in tools/ci/object_keyed_lists_allowlist.txt.

Declared caches. Every declared_cache_vars() entry maps the var name to its
invalidation rule, CACHE_ON_CHANGE(bits), CACHE_ON_EVENT(path) or
CACHE_ON_RELATION(path) (code/__DEFINES/om.dm); the core nulls the cache when the
rule fires. An entry without a rule is an error (not ratcheted).

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
OBJLIST_ALLOWLIST = os.path.join(ROOT, "tools", "ci", "object_keyed_lists_allowlist.txt")

# Medical, body, organs, surgery and Life are no longer excluded
# (doc/rewrite/lifecycle.md sec 7): the sweeps include them.
EXCLUDED_DIRS = ()

UNSAVED_MODS = {"tmp", "static", "global", "const", "final"}
DECLARED_PROCS = (
    "declared_owned_vars",
    "declared_owned_list_vars",
    "declared_pair_vars",
    "declared_backlist_vars",
    "declared_cache_vars",
)
# Declarations that make an instance list var a legitimate holder of objects.
OBJLIST_PROCS = ("declared_owned_list_vars", "declared_cache_vars")
CACHE_ENTRY = re.compile(r'"(\w+)"\s*(=\s*(\S.*?))?\s*,?\s*$')
CACHE_RULE = re.compile(r"^CACHE_ON_(CHANGE|EVENT|RELATION)\(")

TYPE_HEADER = re.compile(r"^(/[A-Za-z_][\w/]*)\s*$")
PROC_HEADER = re.compile(r"^(/[\w/]*?)/(proc/)?(" + "|".join(DECLARED_PROCS) + r")\s*\(")
ANY_PROC_HEADER = re.compile(r"^(/[\w/]*?)/(?:proc/|verb/)?(\w+)\s*\(([^)]*)\)?")
OBJ_DECL = re.compile(r"\bvar/((?:\w+/)*\w+)")
PARAM = re.compile(r"^\s*(?:var/)?((?:\w+/)+)(\w+)")
LIST_INDEX_WRITE = re.compile(r"^(?:src\.)?(\w+)\[(.+?)\]\s*=(?!=)\s*(.+)$")
LIST_ADD = re.compile(r"^(?:src\.)?(\w+)\s*(?:\+=|\|=)\s*(.+)$")
LIST_ASSIGN = re.compile(r"^(?:src\.)?(\w+)\s*=(?!=)\s*list\((.*)\)\s*$")
BACKLIST_VALUE = re.compile(r'"\w+"\s*=\s*"(\w+)"')

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
        text = handle.read()
    raw_lines = code_only(text).split("\n")
    # Declared names are string literals, which code_only() blanks: pass 1
    # reads the declared_*_vars() bodies from the raw text instead.
    source_lines = text.split("\n")

    # Pass 1: every declared_*_vars() proc body, by owner type, as the union
    # of every quoted name across every such override for that type (a type
    # may split REF_OWNED/REF_PAIR/etc. across several small overrides).
    declared = {}  # owner type -> set of var names
    objlist_ok = set()  # list var names declared as holding objects (any type in the file)
    cache_errors = []
    cur_owner, cur_proc, capturing, cur_line = None, None, [], 0

    def close(owner, proc, body, line):
        declared.setdefault(owner, set()).update(declared_names(body))
        if proc in OBJLIST_PROCS:
            objlist_ok.update(declared_names(body))
        if proc == "declared_backlist_vars":
            for b in body:
                BACKLIST_TARGETS.update(BACKLIST_VALUE.findall(b))
        if proc == "declared_cache_vars":
            for b in body:
                m = CACHE_ENTRY.search(b.strip())
                if not m or b.strip().startswith("//"):
                    continue
                rule = (m.group(3) or "").strip()
                if not CACHE_RULE.match(rule):
                    cache_errors.append("%s:%d: %s declares cache \"%s\" with no invalidation rule "
                                        "(CACHE_ON_CHANGE/EVENT/RELATION)" % (rel, line, owner, m.group(1)))

    for no, raw in enumerate(source_lines, 1):
        if not raw.strip():
            continue
        stripped = raw.lstrip("\t ")
        indent = len(raw) - len(stripped)
        if indent == 0:
            if cur_owner is not None:
                close(cur_owner, cur_proc, capturing, cur_line)
                cur_owner, capturing = None, []
            m = PROC_HEADER.match(stripped.rstrip())
            if m:
                cur_owner, cur_proc, cur_line = m.group(1), m.group(3), no
        elif cur_owner is not None:
            capturing.append(stripped)
    if cur_owner is not None:
        close(cur_owner, cur_proc, capturing, cur_line)

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
        if not under(vtype, REF_ROOTS):
            continue
        if name in declared.get(cur_type, ()):
            continue
        # A task's vars are its state: every datum in them is held by the task_holds relation,
        # which clears the var and cancels the task when the datum is deleted (the same rule as
        # scheduler_lints.py's lc_refs).
        if cur_type == "/datum/om/task" or cur_type.startswith("/datum/om/task/"):
            continue
        sites.append((rel, no, "%s var/%s/%s" % (cur_type, vtype.strip("/"), name)))
    return rel, sites, cache_errors, objlist_candidates(rel, raw_lines, objlist_ok)


def is_object_type(path):
    return under("/" + path.strip("/"), REF_ROOTS)


def object_expr(expr, objs):
    """True if `expr` is syntactically an object: src/usr, a new expression, or a
    name this proc declared object-typed."""
    e = expr.strip().rstrip(",").strip()
    if e.startswith("(") and e.endswith(")"):
        e = e[1:-1].strip()
    if e in ("src", "usr") or e.startswith("new ") or e.startswith("new/"):
        return True
    return e in objs


def objlist_candidates(rel, raw_lines, objlist_ok):
    """(rel, line, text) for every write of an object into an undeclared instance list var."""
    # Instance list vars declared in this file (any type block, indent 1).
    list_vars = set()
    cur_type = None
    for raw in raw_lines:
        if not raw.strip():
            continue
        stripped = raw.lstrip("\t ")
        indent = len(raw) - len(stripped)
        if indent == 0:
            m = TYPE_HEADER.match(stripped.rstrip())
            cur_type = m.group(1) if m else None
            continue
        if indent != 1 or cur_type is None:
            continue
        m = VAR_LINE.match(stripped.rstrip())
        if not m:
            continue
        segs = m.group(1).strip("/").split("/")
        mods = set()
        while segs and segs[0] in UNSAVED_MODS:
            mods.add(segs.pop(0))
        if mods & {"static", "global", "const"} or len(segs) < 2 or segs[0] != "list":
            continue
        list_vars.add(segs[-1])
    list_vars -= objlist_ok
    list_vars -= BACKLIST_TARGETS
    if not list_vars:
        return []

    out = []
    objs, locals_ = set(), set()
    for no, raw in enumerate(raw_lines, 1):
        if not raw.strip():
            continue
        stripped = raw.lstrip("\t ")
        indent = len(raw) - len(stripped)
        text = stripped.rstrip()
        if indent == 0:
            objs, locals_ = set(), set()
            m = ANY_PROC_HEADER.match(text)
            if m and m.group(3) is not None:
                for p in m.group(3).split(","):
                    pm = PARAM.match(p.split("=")[0].split(" as ")[0])
                    if pm:
                        locals_.add(pm.group(2))
                        if is_object_type(pm.group(1)):
                            objs.add(pm.group(2))
                    else:
                        locals_.add(p.split("=")[0].strip())
            continue
        for dm in OBJ_DECL.finditer(text):
            segs = dm.group(1).split("/")
            name = segs[-1]
            locals_.add(name)
            tsegs = [s for s in segs[:-1] if s not in UNSAVED_MODS]
            if tsegs and tsegs[0] != "list" and is_object_type("/".join(tsegs)):
                objs.add(name)
        if not objs and "new" not in text and "src" not in text and "usr" not in text:
            continue
        hit = None
        m = LIST_INDEX_WRITE.match(text)
        if m and m.group(1) in list_vars and m.group(1) not in locals_:
            if object_expr(m.group(2), objs) or object_expr(m.group(3), objs):
                hit = m.group(1)
        m = LIST_ADD.match(text)
        if not hit and m and m.group(1) in list_vars and m.group(1) not in locals_:
            if object_expr(m.group(2), objs):
                hit = m.group(1)
        m = LIST_ASSIGN.match(text)
        if not hit and m and m.group(1) in list_vars and m.group(1) not in locals_:
            for part in m.group(2).split(","):
                if any(object_expr(side, objs) for side in part.split("=", 1)):
                    hit = m.group(1)
                    break
        if hit:
            out.append((rel, no, "%s: %s" % (hit, text)))
    return out


# List var names that some declared_backlist_vars() names as the owner's list
# (filled by scan_file() pass 1; scan() runs pass 1 over every file first).
BACKLIST_TARGETS = set()


def scan():
    counts, all_sites = {}, []
    obj_counts, obj_sites, cache_errors = {}, [], []
    paths = []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if is_excluded(rel) or "/unit_tests/" in rel:
            continue
        paths.append(path)
    # Backlist targets are declared on the member's side, often in another file.
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        if "declared_backlist_vars" in text:
            BACKLIST_TARGETS.update(BACKLIST_VALUE.findall(text))
    for path in paths:
        rel, sites, errors, objs = scan_file(path)
        cache_errors.extend(errors)
        if objs:
            obj_counts[rel] = len(objs)
            obj_sites.extend(objs)
        if not sites:
            continue
        counts[rel] = len(sites)
        all_sites.extend(sites)
    return counts, all_sites, obj_counts, obj_sites, cache_errors


def read_allowlist(path=ALLOWLIST):
    allowed = {}
    if not os.path.exists(path):
        return allowed
    with open(path, encoding="utf-8") as handle:
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
        "# REF_OWNED_LIST/REF_PAIR/REF_BACKLIST (or make it tmp, or an OM handle) and",
        "# lower the count; `python tools/ci/declared_refs_lint.py --update` rewrites it.",
        "# Total: %d vars in %d files." % (sum(counts.values()), len(counts)),
    ]
    for path in sorted(counts):
        lines.append("%s %d" % (path, counts[path]))
    with open(ALLOWLIST, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def write_objlist_allowlist(counts):
    lines = [
        "# Instance list vars written with objects as keys or values, undeclared",
        "# (doc/rewrite/lifecycle.md sec 4, LC-refs). tools/ci/declared_refs_lint.py reads",
        "# this file: a file may not exceed its count. Make the list an owned-children",
        "# list, a backlist, a declared cache with an invalidation rule, a relation or",
        "# a registry, or key it by OM handle, and lower the count with --update.",
        "# Total: %d writes in %d files." % (sum(counts.values()), len(counts)),
    ]
    for path in sorted(counts):
        lines.append("%s %d" % (path, counts[path]))
    with open(OBJLIST_ALLOWLIST, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def main(argv):
    counts, sites, obj_counts, obj_sites, cache_errors = scan()
    total = sum(counts.values())
    if "--update" in argv:
        write_allowlist(counts)
        write_objlist_allowlist(obj_counts)
        print("declared-refs allowlist: %d vars in %d files; object-keyed lists: %d writes in %d files"
              % (total, len(counts), sum(obj_counts.values()), len(obj_counts)))
        for error in cache_errors:
            print("FAIL: " + error)
        return 1 if cache_errors else 0
    if "--report" in argv:
        for rel, number, what in sites:
            print("%s:%d: %s" % (rel, number, what))
        for rel, number, what in obj_sites:
            print("%s:%d: object-keyed list %s" % (rel, number, what))
        print("total: %d undeclared object-typed vars in %d files, %d object-keyed list writes"
              % (total, len(counts), sum(obj_counts.values())))
        return 0
    allowed = read_allowlist()
    failures, lowered = [], []
    failures.extend(cache_errors)
    obj_allowed = read_allowlist(OBJLIST_ALLOWLIST)
    for rel in sorted(obj_counts):
        limit = obj_allowed.get(rel, 0)
        if obj_counts[rel] > limit:
            where = ["%s:%d: %s" % s for s in obj_sites if s[0] == rel]
            failures.append(
                "%s writes objects into %d undeclared instance list(s), allowed %d. Declare the list "
                "(declared_owned_list_vars/backlist/declared_cache_vars), make it a relation or registry, "
                "or key it by om_handle():\n    %s" % (rel, obj_counts[rel], limit, "\n    ".join(where)))
        elif obj_counts[rel] < limit:
            lowered.append("%s: %d object-keyed list writes (allowlist says %d)" % (rel, obj_counts[rel], limit))
    for rel in sorted(obj_allowed):
        if rel not in obj_counts:
            lowered.append("%s: 0 object-keyed list writes (allowlist says %d)" % (rel, obj_allowed[rel]))
    for rel in sorted(counts):
        limit = allowed.get(rel, 0)
        if counts[rel] > limit:
            where = ["%s:%d: %s" % s for s in sites if s[0] == rel]
            failures.append(
                "%s has %d undeclared object-typed var(s), allowed %d. Declare each as "
                "REF_OWNED/REF_OWNED_LIST/REF_PAIR/REF_BACKLIST (code/datums/lifecycle/links.dm), "
                "tmp, or an OM handle:\n    %s" % (rel, counts[rel], limit, "\n    ".join(where))
            )
        elif counts[rel] < limit:
            lowered.append("%s: %d (allowlist says %d)" % (rel, counts[rel], limit))
    for rel in sorted(allowed):
        if rel not in counts:
            lowered.append("%s: 0 (allowlist says %d)" % (rel, allowed[rel]))
    print("declared-refs lint: %d undeclared object-typed vars in %d files (allowlisted: %d); "
          "%d object-keyed list writes (allowlisted: %d)"
          % (total, len(counts), sum(allowed.values()), sum(obj_counts.values()), sum(obj_allowed.values())))
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
