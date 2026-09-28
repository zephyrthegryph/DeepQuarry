"""Declared-reference lint (roadmap L2, doc/rewrite/lifecycle.md section 4).

Every object-typed var on a datum is declared as exactly one kind, in one form:

    DECLARE_REF(/type, "var", KIND, OPT)      code/__defines/lifecycle.dm

KIND is OWNED, OWNED_LIST, OWNED_VALUES, SPILL, SPILL_LIST, HELD, PAIR, BACKLIST,
BACKLIST_HANDLE, BACK_HANDLE, BACK_VIA, LIST_BACK, DROP, QUEUE, BACK, KEEP, DEF,
STATIC, WEAK_LIST or TRANSIENT (ref_kinds.REF_KINDS). Also accepted:

    slot content        lives in a ledger slot -- not a var, never flagged
    DEF_TYPES           a var typed as a frozen definition is an implicit DEF
    handle              a text var holding om_handle(x)
    tmp cache           `tmp`/`static`/`global`/`const`
    declared cache      declared_cache_vars() (the OM's, with a CACHE_ON_* rule)

TRANSIENT on a type that isn't POOL_DECLAREd is an error, and so is an unknown KIND.

Suggestions. For each undeclared var the lint reads how the type's file writes it
and suggests a kind: created with `new` or qdel'd (OWNED / OWNED_LIST /
OWNED_VALUES), a partner written back (`var.x = src` -> PAIR, `var.list += src`
-> BACKLIST), a singleton type (STATIC), moved into src (HELD), a list only
appended to (WEAK_LIST), assigned from another type (`thing.var = ...` -> BACK),
else an OM handle. It prints the DECLARE_REF line to add and why.

This finds every var declared directly on a type (not inherited -- each var is
only ever checked at the type that first declares it) whose declared type is
an object reference, that isn't `tmp`/`static`/`global`/`const`, and checks whether the *same file* has a DECLARE_REF line for that type naming the
var. A var that isn't named is undeclared.

NOTE: this can't see slot content (a slot holds a *thing*, not a *var* --
membership lives in the ledger, code/datums/containment/ledger.dm), so a
holder's contents never need a DECLARE_REF and are never flagged.

Medical, body, organs, surgery, protean and mind_body are included like
everything else (doc sec 7). tools/ci/scheduler_lints.py's LC-refs count is
the stricter successor (tmp vars count there too).

Undeclared vars are banned outright (the ratchet reached 0 and was removed). A var that is justified as it is carries
`// ALLOW(declared_refs): <reason>` on its declaration (or the comment line above
it; tools/ci/allow_annotations.py) and doesn't count.

Object-keyed lists. An instance list var must not collect objects (as keys or
values: `L[obj] = ...`, `L[key] = obj`, `L += obj`, `L |= obj`, `L = list(obj = ...)`)
unless it is declared: a list kind (ref_kinds.OBJLIST_KINDS), the list side of a
backlist (named as OPT by some BACKLIST declaration), or a declared cache (declared_cache_vars()). Relations and slots are not vars, and
registries are global. "An object" is recognised syntactically: `src`, `usr`, a
`new` expression, or a name the proc declares object-typed (an argument such as
`mob/M`, a `var/obj/item/I` local, a `for(var/atom/A in ...)` loop var). These are
ratcheted by the `object_keyed` ceiling in the same baseline; a justified write
carries `// ALLOW(object_keyed_lists): <reason>`.
A list var declared with an object element type
(`var/list/datum/reagent/reagent_by_id`, tmp or not) counts once at its
declaration even when no write is recognised: an id -> datum index left set
after Destroy is a cycle among deleted objects.

Declared caches. Every declared_cache_vars() entry maps the var name to its
invalidation rule, CACHE_ON_CHANGE(bits), CACHE_ON_EVENT(path) or
CACHE_ON_RELATION(path) (code/__DEFINES/om.dm); the core nulls the cache when the
rule fires. An entry without a rule is an error (not ratcheted).

Usage:
    python tools/ci/declared_refs_lint.py            # the CI check
    python tools/ci/declared_refs_lint.py --report   # every var, and the total
    python tools/ci/declared_refs_lint.py --update   # rewrite the ceilings to today's counts
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import REF_ROOTS, code_only, under  # noqa: E402
from allow_annotations import allowed, check_ceilings  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Medical, body, organs, surgery and Life are no longer excluded
# (doc/rewrite/lifecycle.md sec 7): the sweeps include them.
EXCLUDED_DIRS = ()

UNSAVED_MODS = {"tmp", "static", "global", "const", "final"}
# DECLARE_REF parsing, kinds, pooled types and implicit DEF types (ref_kinds.py).
from ref_kinds import DECLARED_PROCS, OBJLIST_KINDS, ref_decl, is_def_type, is_pooled, is_static_type  # noqa: E402
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
BACKLIST_VALUE = re.compile(r'^DECLARE_REF\([^,]+,\s*"\w+"\s*,\s*BACKLIST\s*,\s*"(\w+)"', re.M)

OM_FIELD_TYPED = re.compile(r"^OM_FIELD_TYPED\(\s*(/[\w/]+)\s*,\s*([\w/]+)\s*,\s*(\w+)\s*,")
# The machinery the four kinds are made of holds references by construction; its vars are not
# relationships of their own. Kept in step with scheduler_lints.py's lc_refs.
STRUCTURAL_TYPES = {
    "/datum/om/task": "a task's vars are its state, held by the task_holds relation",
    "/datum/om/edge": "an edge is the relation itself: both ends hold it and it goes when either end does",
    "/datum/om/rec": "an entity's own record (its edges, timers, scheduler), torn down in its destroy transaction",
    "/datum/om/frame": "an entity's pipeline state, kept in its record (or a scratch frame for one run)",
    "/datum/om/event": "an event in delivery: the entity it is emitted on, for the length of the call",
    "/datum/om/scheduler": "the dispatch context: the record whose code is running",
    "/datum/ledger": "a holder's slot contents: the slot mechanism itself",
    "/datum/registry": "registry membership, left in phase 2 of the member's destroy transaction",
}


def structural(type_path):
    return any(type_path == t or type_path.startswith(t + "/") for t in STRUCTURAL_TYPES)


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
    declared_cache_vars() table)."""
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
    # reads the DECLARE_REF lines and cache bodies from the raw text instead.
    source_lines = text.split("\n")

    # Pass 1: every DECLARE_REF line and declared_cache_vars() body, by owner type.
    declared = {}  # owner type -> set of var names
    objlist_ok = set()  # list var names declared as holding objects (any type in the file)
    cache_errors = []
    cur_owner, cur_proc, capturing, cur_line = None, None, [], 0

    def close(owner, proc, body, line):
        """The declared_cache_vars() body of `owner` (the one hand-written table)."""
        declared.setdefault(owner, set()).update(declared_names(body))
        objlist_ok.update(declared_names(body))
        for b in body:
            m = CACHE_ENTRY.search(b.strip())
            if not m or b.strip().startswith("//"):
                continue
            rule = (m.group(3) or "").strip()
            if not CACHE_RULE.match(rule):
                cache_errors.append("%s:%d: %s declares cache \"%s\" with no invalidation rule "
                                    "(CACHE_ON_CHANGE/EVENT/RELATION)" % (rel, line, owner, m.group(1)))

    def declare(owner, var, kind, opt, line):
        if kind == "TRANSIENT" and not is_pooled(owner):
            cache_errors.append("%s:%d: %s declares %s TRANSIENT but is not a pooled type "
                                "(POOL_DECLARE); transient fields exist only on pooled objects" % (rel, line, owner, var))
            return
        declared.setdefault(owner, set()).add(var)
        if kind in OBJLIST_KINDS:
            objlist_ok.add(var)
        if kind == "BACKLIST":
            BACKLIST_TARGETS.update(STRING_LIT.findall(opt))

    for no, raw in enumerate(source_lines, 1):
        if not raw.strip():
            continue
        stripped = raw.lstrip("\t ")
        indent = len(raw) - len(stripped)
        if indent == 0:
            if cur_owner is not None:
                close(cur_owner, cur_proc, capturing, cur_line)
                cur_owner, capturing = None, []
            if stripped.startswith("DECLARE_REF("):
                try:
                    decl = ref_decl(stripped)
                except ValueError as err:
                    cache_errors.append("%s:%d: %s" % (rel, no, err))
                    continue
                if not decl:
                    cache_errors.append("%s:%d: unreadable DECLARE_REF (one line: DECLARE_REF(/type, \"var\", KIND, OPT))" % (rel, no))
                    continue
                declare(decl[0], decl[1], decl[2], decl[3], no)
                continue
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
            # OM_FIELD_TYPED(type, vartype, name, ...) declares `type/var/vartype/name` (om.dm).
            fm = OM_FIELD_TYPED.match(text)
            if fm:
                parsed = split_var((fm.group(2) + "/" + fm.group(3)).strip("/").split("/"))
                if parsed:
                    mods, vtype, name, _is_list = parsed
                    if not (mods & UNSAVED_MODS) and under(vtype, REF_ROOTS)                             and name not in declared.get(fm.group(1), ()):
                        sites.append((rel, no, "%s var/%s/%s" % (fm.group(1), vtype.strip("/"), name)))
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
        # A frozen definition or registry object (DEF_TYPES): an implicit DEF.
        if is_def_type(vtype):
            continue
        # Tasks, edges, records, ledgers and registries: see STRUCTURAL_TYPES.
        if structural(cur_type):
            continue
        # Typed prompts and flows (ask.dm, flow.dm) hold their state vars as handles while they
        # wait (park_state()), and a prompt's `flow` is the one strong ref keeping its flow alive.
        if cur_type in ("/datum/om/prompt", "/datum/om/flow") or cur_type.startswith(("/datum/om/prompt/", "/datum/om/flow/")):
            continue
        if allowed(source_lines, no, "declared_refs"):
            continue
        sites.append((rel, no, "%s var/%s/%s" % (cur_type, vtype.strip("/"), name)
                      + "\n    " + suggest(cur_type, name, vtype, _is_list, raw_lines)))
    objs = [o for o in objlist_candidates(rel, raw_lines, objlist_ok)
            if not allowed(source_lines, o[1], "object_keyed_lists")]
    return rel, sites, cache_errors, objs


def _proc_owner(header):
    m = ANY_PROC_HEADER.match(header)
    return m.group(1) if m else None


def suggest(owner, name, vtype, is_list, raw_lines):
    """A DECLARE_REF line for undeclared var `name` of `owner`, from its write
    patterns in the same file (who assigns it, whether it is qdel'd), and why."""
    n = re.escape(name)
    own_lines, outside = [], []
    cur = None
    for raw in raw_lines:
        if not raw.strip():
            continue
        if not raw[0].isspace():
            cur = _proc_owner(raw.rstrip())
            continue
        text = raw.strip()
        if cur and (cur == owner or cur.startswith(owner + "/")):
            own_lines.append(text)
        elif re.search(r"\w\." + n + r"\s*(=(?!=)|\+=|\|=)", text):
            outside.append(text)
    body = "\n".join(own_lines)

    def line(kind, opt, why):
        return 'suggest: DECLARE_REF(%s, "%s", %s, %s) -- %s' % (owner, name, kind, opt, why)

    if re.search(r"QDEL_LIST_ASSOC_VAL\(\s*(src\.)?" + n + r"\s*\)", body):
        return line("OWNED_VALUES", "null", "its values are qdel'd with QDEL_LIST_ASSOC_VAL")
    if re.search(r"QDEL_(LAZY)?LIST\(\s*(src\.)?" + n + r"\s*\)", body) or (
            is_list and re.search(r"\b" + n + r"\s*(\+=|\|=)\s*new\b", body)):
        return line("OWNED_LIST", "null", "src fills it with new objects or qdels its members")
    created = re.search(r"(^|\W)(src\.)?" + n + r"\s*=\s*new\b", body)
    deleted = re.search(r"(QDEL_NULL|qdel)\(\s*(src\.)?" + n + r"\s*[,)]", body)
    if created or deleted:
        why = " and ".join(w for w, hit in (("src creates it with new", created), ("src qdels it", deleted)) if hit)
        return line("OWNED", "null", why + "; it is deleted in phase 4")
    m = re.search(r"\b" + n + r"\.(\w+)\s*=\s*src\b", body)
    if m:
        return line("PAIR", '"%s"' % m.group(1), "src sets %s.%s = src: both sides name each other" % (name, m.group(1)))
    m = re.search(r"\b" + n + r"\.(\w+)\s*(\+=|\|=)\s*src\b|LAZY(?:ADD|OR)\(\s*" + n + r"\.(\w+)\s*,\s*src\s*\)", body)
    if m:
        their = m.group(1) or m.group(3)
        return line("BACKLIST", '"%s"' % their, "src adds itself to %s.%s" % (name, their))
    if vtype and is_static_type(vtype):
        return line("STATIC", "null", "%s is a singleton/flyweight type (OM_STATIC_TYPE)" % vtype)
    if re.search(r"\b" + n + r"\.forceMove\(\s*src\s*\)|\b" + n + r"\.loc\s*=\s*src\b", body):
        return line("HELD", "null", "src moves it into its own contents")
    if is_list and re.search(r"\b" + n + r"\s*(\+=|\|=)|LAZY(ADD|OR)\(\s*" + n + r"\b", body):
        return line("WEAK_LIST", "null", "a list src appends others to but does not own; store om_handle()s")
    if outside:
        return line("BACK", "null", "another type assigns it (%s): a child naming its owner; "
                    "set OPT to the owner's var naming us" % outside[0][:60])
    return ("suggest: no ownership pattern found -- keep an om_handle() in a text var, make it tmp, "
            'or declare its kind: DECLARE_REF(%s, "%s", KIND, OPT)' % (owner, name))


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
    typed_lists = {}  # name -> (line, text): `var/list/datum/reagent/x`, a list typed as holding objects
    cur_type = None
    for decl_no, raw in enumerate(raw_lines, 1):
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
        if structural(cur_type):
            continue
        list_vars.add(segs[-1])
        # A list whose declared element type is an object type holds objects by
        # declaration, even where no write is recognisable (an index write of a
        # proc result, `x = other_list`): the reagent_by_id class, an assoc of id ->
        # datum that, left set after Destroy, closed a cycle between deleted objects.
        if len(segs) > 2 and is_object_type("/".join(segs[1:-1])):
            typed_lists[segs[-1]] = (decl_no, stripped.rstrip())
    list_vars -= objlist_ok
    list_vars -= BACKLIST_TARGETS
    if not list_vars:
        return []

    out = []
    for name in sorted(set(typed_lists) & list_vars):
        decl_no, text = typed_lists[name]
        out.append((rel, decl_no, "%s: typed object list, undeclared: %s" % (name, text)))
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


# List var names that some BACKLIST declaration names as the owner's list
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
        if "BACKLIST" in text:
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


def main(argv):
    counts, sites, obj_counts, obj_sites, cache_errors = scan()
    total, obj_total = sum(counts.values()), sum(obj_counts.values())
    totals = {"undeclared": total, "object_keyed": obj_total}
    if "--report" in argv:
        for rel, number, what in sites:
            print("%s:%d: %s" % (rel, number, what))
        for rel, number, what in obj_sites:
            print("%s:%d: object-keyed list %s" % (rel, number, what))
        print("total: %d undeclared object-typed vars in %d files, %d object-keyed list writes"
              % (total, len(counts), obj_total))
        return 0
    failed = check_ceilings(
        "declared-refs", totals, {"undeclared": 0, "object_keyed": 0},
        "Declare each new object var with DECLARE_REF(/type, \"var\", KIND, OPT) "
        "(code/__defines/lifecycle.dm; each site below carries a suggested kind), make it tmp, or "
        "hold an OM handle; declare a new object-keyed list with a list kind or key it by om_handle().")
    if failed:
        for rel, number, what in sites:
            print("%s:%d: undeclared %s" % (rel, number, what))
    for error in cache_errors:
        print("FAIL: " + error)
    return 1 if failed or cache_errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
