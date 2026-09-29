"""Converter report: typed OM relations (/datum/om/relation/*) -> relations() entries
(doc/rewrite/migration_guide.md B17, doc/rewrite/ownership.md §4.1).

Only --dry-run exists: it lists every concrete /datum/om/relation type with the rel_one()/rel_many()
line(s) it would become, the om_link() sites that create its edges, and the features a relations()
entry cannot express yet (contributions, grants, active_if/holds_while, list-undo, derived views,
on_link hooks, ...), which block an automatic conversion.

    python tools/dx/convert_relations.py --dry-run            # the report
    python tools/dx/convert_relations.py --dry-run --summary  # counts only
"""
import glob
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
REL_ROOT = "/datum/om/relation"
HEAD = re.compile(r"^(/datum/om/relation(?:/\w+)+)\s*$")
PROC = re.compile(r"^(/datum/om/relation(?:/\w+)+?)/(?:proc/)?(on_link|on_unlink|on_member_leave|on_end_changed)\(")
VAR = re.compile(r"^\t(?:var/)?(\w+)\s*=\s*(.+?)\s*(?://.*)?$")
LINK = re.compile(r"\bom_link\(\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*(/datum/om/relation(?:/\w+)+)")
PROC_DEF = re.compile(r"^(/[\w/]+?)/(?:(?:proc|verb)/)?\w+\(")

# Fields a relations() entry has no option for yet: any of these blocks the conversion.
BLOCKING = ("contributes", "source_contributes", "grants_target", "grants_occupant", "active_if",
            "holds_while", "undo_list", "derived_view", "clone_follows", "include")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read().split("\n")


def scan():
    types = {}
    hooks = defaultdict(set)
    links = defaultdict(list)
    for path in sorted(glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        lines = read(path)
        current = None
        proc_owner = None
        for no, line in enumerate(lines, 1):
            m = HEAD.match(line)
            if m:
                current = m.group(1)
                types.setdefault(current, {"vars": {}, "at": "%s:%d" % (rel, no)})
                continue
            m = PROC.match(line)
            if m:
                hooks[m.group(1)].add(m.group(2))
                current = None
            if line and not line[0].isspace():
                pm = PROC_DEF.match(line)
                proc_owner = pm.group(1) if pm else None
                if not HEAD.match(line):
                    current = None
            if current:
                vm = VAR.match(line)
                if vm:
                    types[current]["vars"][vm.group(1)] = vm.group(2)
            for lm in LINK.finditer(line.split("//", 1)[0]):
                links[lm.group(3)].append(("%s:%d" % (rel, no), lm.group(1), lm.group(2), proc_owner))
    return types, hooks, links


def resolved(types, path):
    """The type's vars with its ancestors' underneath (DM inheritance)."""
    parts = path.split("/")
    out = {}
    for i in range(len(REL_ROOT.split("/")), len(parts) + 1):
        out.update(types.get("/".join(parts[:i]), {}).get("vars", {}))
    return out


def resolved_hooks(hooks, path):
    parts = path.split("/")
    out = set()
    for i in range(len(REL_ROOT.split("/")), len(parts) + 1):
        out |= hooks.get("/".join(parts[:i]), set())
    return out


def proposal(path, v, hk, sites):
    shape = v.get("shape")
    source_single = v.get("source_single") == "TRUE" or shape in ("REL_ONE_TO_ONE",)
    target_single = v.get("target_single") == "TRUE" or shape in ("REL_ONE_TO_ONE", "REL_ONE_TO_MANY")
    if shape == "REL_ONE_TO_MANY":
        source_single = False
    symmetric = shape == "REL_SYMMETRIC"
    sview = (v.get("source_view") or "").strip('"')
    tview = (v.get("target_view") or "").strip('"')
    name = path.rsplit("/", 1)[1]
    srcs = sorted({s[3] for s in sites if s[1] == "src" and s[3]})
    source_type = srcs[0] if len(srcs) == 1 else ("/SOURCE_TYPE" if not srcs else "/(" + "|".join(srcs) + ")")
    target_type = "/TARGET_TYPE"
    svar = sview or ("%s_target" % name)
    tvar = tview or ("%s_source" % name)
    opts = []
    if symmetric:
        opts.append("back = nameof(%s::%s)" % (source_type, svar))
    else:
        opts.append("back = nameof(%s::%s)" % (target_type, tvar))
    if v.get("on_target_delete") == "OM_END_DELETE_OTHER":
        opts.append("other_deleted = DELETE_ME")
    if "on_unlink" in hk:
        opts.append("on_unlink = PROC_REF(%s_ended)" % name)
    lines = ["%s/relations(): . += %s(nameof(%s), %s)" % (
        source_type, "rel_one" if source_single else "rel_many", svar, ", ".join(opts))]
    if not symmetric:
        back_opts = ["back = nameof(%s::%s)" % (source_type, svar)]
        if v.get("on_source_delete") == "OM_END_DELETE_OTHER":
            back_opts.append("other_deleted = DELETE_ME")
        lines.append("%s/relations(): . += %s(nameof(%s), %s)" % (
            target_type, "rel_one" if target_single else "rel_many", tvar, ", ".join(back_opts)))
    blockers = [f for f in BLOCKING if f in v and v[f] not in ("null", "FALSE", "list()")]
    if v.get("conflict") == "OM_REL_REFUSE":
        blockers.append("conflict = OM_REL_REFUSE")
    for h in ("on_link", "on_member_leave", "on_end_changed"):
        if h in hk:
            blockers.append(h + " hook")
    notes = []
    if not sview:
        notes.append("no source_view: a new var %s is proposed" % svar)
    if not tview and not symmetric:
        notes.append("no target_view: a new var %s is proposed" % tvar)
    return lines, blockers, notes


def main(argv):
    if "--dry-run" not in argv:
        print(__doc__)
        return 2
    types, hooks, links = scan()
    concrete = [t for t in sorted(types) if t != REL_ROOT and not any(o.startswith(t + "/") for o in types)]
    convertible = 0
    summary = "--summary" in argv
    for path in concrete:
        v = resolved(types, path)
        hk = resolved_hooks(hooks, path)
        sites = links.get(path, [])
        lines, blockers, notes = proposal(path, v, hk, sites)
        if not blockers:
            convertible += 1
        if summary:
            continue
        print("%s  (%s)%s" % (path, types[path]["at"], "" if not blockers else "  BLOCKED: " + ", ".join(blockers)))
        for line in lines:
            print("    " + line)
        for note in notes:
            print("    note: " + note)
        for site, a, b, owner in sites:
            print("    om_link: %s  om_link(%s, %s, ...)%s" % (site, a, b, " in " + owner if owner else ""))
    print("relation types: %d concrete, %d convertible now, %d blocked; om_link sites: %d" % (
        len(concrete), convertible, len(concrete) - convertible, sum(len(links.get(p, [])) for p in concrete)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
