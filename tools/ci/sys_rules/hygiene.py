"""Hygiene rules (doc/rewrite/systems.md, "Hygiene"). See tools/ci/sys_lint.py.

annotation_boilerplate
    A justified-keep annotation (`// ALLOW(<lint>): <reason>`) whose reason is placeholder
    boilerplate rather than a reason: the CI-wiring placeholder ("baseline when CI was wired",
    "convert or give a real reason"), the pasted mob-count text ("15 mobs at boot", "see audit"),
    or a reason that names a kind of thing ("mob:", "obj:", "item:", "machine:", "turf:",
    "area:") the site's own type is not.

cached_var
    A hand-maintained `cached_*` instance var: its declaration, its writes and its manual
    invalidations (`cached_x = null`). Derive it (om_derived() / a DERIVE() row,
    code/datums/om/derived.dm), declare it (declared_cache_vars() with a CACHE_ON_* rule,
    then fill it and let the object-model core clear it; a manual `= null` on a declared cache
    is still flagged: raise the channel with om_changed()), use a shared cache
    (DECLARE_SHARED_CACHE), or, when it is not a cache at all, name it for what it holds.

deadline_poll
    A periodic body (process(), periodic_step(), machine_step(), service_step(), an OM
    behaviour's tick()) that compares world.time with a stored deadline to fire something,
    plus the writes that store that deadline (`next_x = world.time + ...`). Use om_after() /
    om_deadline() (code/datums/om/timer.dm, deadline.dm). The scan is
    tools/ci/check_deadline_polling.py's; an ALLOW on the poll keeps its deadline var too.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
# check_deadline_polling and allow_annotations are imported inside scan(): allow_annotations
# loads this module to learn the rule names, so importing them at load time would be circular.
deadline = None

RULES = {
    "annotation_boilerplate": "write the real reason for this site, or fix the site (doc/rewrite/systems.md, Hygiene)",
    "cached_var": "om_derived()/DERIVE(), declared_cache_vars() + om_changed(), a shared cache, or a name for what it holds (Hygiene)",
    "deadline_poll": "om_after()/om_deadline() at the moment the deadline is set, not a world.time check in periodic work (Hygiene)",
}

ALLOW = re.compile(r"(?://+|/\*)\s*ALLOW\(\s*([\w\s,]*?)\s*\)\s*:\s*(.*?)\s*(?:\*/.*)?$")
PLACEHOLDERS = ("baseline when ci was wired", "convert or give a real reason", "mobs at boot", "see audit")
KINDS = {"mob": "/mob", "obj": "/obj", "item": "/obj/item", "machine": "/obj/machinery",
         "turf": "/turf", "area": "/area"}
KIND_PREFIX = re.compile(r"^(mob|obj|item|machine|turf|area)s?:")

TYPE_BLOCK = re.compile(r"^(/(?!/)[\w/]+)\s*(?://.*)?$")
MACRO_TYPE = re.compile(r"^[A-Z][A-Z0-9_]*_DEF\(")
PROC_HEAD = re.compile(r"^/(?!/)[\w/]*\(")
NESTED_PROC = re.compile(r"^\t(?:proc/|verb/)?\w+\(")
TYPE_VAR = re.compile(r"^\tvar/((?:\w+/)*?)(cached_\w+)\b")
PATH_VAR = re.compile(r"^/(?!/)[\w/]*?/var/((?:\w+/)*?)(cached_\w+)\b")
SHARED_MODS = re.compile(r"(?:^|/)(static|global|const)/")
# Vendored upstream code kept verbatim (the tgstation-server DMAPI).
VENDORED = ("code/modules/tgs/",)
DECLARED = re.compile(r"\[\s*\"(cached_\w+)\"\s*\]\s*=\s*CACHE_ON_")


def code_of(line):
    return deadline.strip_comment(line)


def _imports():
    global deadline
    import check_deadline_polling
    deadline = check_deadline_polling
    from allow_annotations import allowed
    return allowed


def owner_type(lines, index):
    """The type path the line at 0-based `index` belongs to (nearest column-0 path above it)."""
    for j in range(index, -1, -1):
        m = re.match(r"^(/(?!/)[\w/]+)", lines[j])
        if m:
            path = m.group(1)
            if "/proc/" in path or "/verb/" in path:
                path = path.split("/proc/")[0].split("/verb/")[0]
            return path
    return ""


def scan_boilerplate(rel, lines, out):
    for number, line in enumerate(lines, 1):
        m = ALLOW.search(line)
        if not m:
            continue
        reason = m.group(2).strip().lower()
        if any(p in reason for p in PLACEHOLDERS):
            out.append((rel, number))
            continue
        kind = KIND_PREFIX.match(reason)
        if kind:
            owner = owner_type(lines, number - 1)
            if owner and not owner.startswith(KINDS[kind.group(1)]):
                out.append((rel, number))


def cached_decls(lines):
    """[(0-based index, name)] of cached_* instance var declarations."""
    found = []
    in_type = False
    in_nested_proc = False
    for i, line in enumerate(lines):
        if line and not line[0].isspace():
            in_type = bool(TYPE_BLOCK.match(line) or MACRO_TYPE.match(line))
            in_nested_proc = False
            m = PATH_VAR.match(line)
            if m and not SHARED_MODS.search(m.group(1)):
                found.append((i, m.group(2)))
            continue
        if not in_type:
            continue
        if NESTED_PROC.match(line):
            in_nested_proc = True
            continue
        if line.startswith("\t") and not line.startswith("\t\t") and line.strip():
            in_nested_proc = False
        m = TYPE_VAR.match(line)
        if m and not in_nested_proc and not SHARED_MODS.search(m.group(1)):
            found.append((i, m.group(2)))
    return found


def scan(files):
    allowed = _imports()
    out = {rule: [] for rule in RULES}
    declared = set()
    decls = []
    for rel, lines in files:
        scan_boilerplate(rel, lines, out["annotation_boilerplate"])
        for line in lines:
            for m in DECLARED.finditer(line):
                declared.add(m.group(1))
        if rel.startswith(VENDORED):
            continue
        for index, name in cached_decls(lines):
            decls.append((rel, index, name))
    # cached_var: undeclared caches (declaration and every write), and manual invalidation of
    # declared ones. Writes are looked for in the declaring file (these vars are type-private).
    by_file = {}
    for rel, index, name in decls:
        by_file.setdefault(rel, []).append((index, name))
    raw = dict(files)
    for rel, entries in by_file.items():
        lines = raw[rel]
        for index, name in entries:
            write = re.compile(r"(?<![\w.])(?:src\.)?" + name + r"\s*(?:=(?!=)|\+=|-=|\|=)\s*(.*)$")
            if name not in declared:
                out["cached_var"].append((rel, index + 1))
            for number, line in enumerate(lines, 1):
                if number == index + 1:
                    continue
                m = write.search(code_of(line))
                if not m:
                    continue
                if name not in declared or m.group(1).strip() == "null":
                    out["cached_var"].append((rel, number))
    # deadline_poll: the poll, and the writes that store its deadline.
    for rel, lines in files:
        hits = list(deadline.scan_lines(lines))
        if not hits:
            continue
        idents = set()
        for _proc, number, text in hits:
            if allowed(lines, number, "sys_deadline_poll"):
                continue
            out["deadline_poll"].append((rel, number))
            for m in deadline.DEADLINE.finditer(code_of(lines[number - 1])):
                ident = m.group(1) or m.group(2)
                if ident:
                    idents.add(ident.split(".")[-1].split("[")[0])
        for ident in idents:
            store = re.compile(r"(?<![\w])" + re.escape(ident) + r"\s*(?:=(?!=)|\+=)[^=]*world\.time")
            for number, line in enumerate(lines, 1):
                if store.search(code_of(line)):
                    out["deadline_poll"].append((rel, number))
    return out
