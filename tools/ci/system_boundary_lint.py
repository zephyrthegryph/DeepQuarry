r"""System boundary lint (doc/rewrite/kernel.md sec 2.5). A subsystem, a world service or a /datum/system is a
module: its folder is the boundary. Counts are ratcheted per (rule, file, owner) in
tools/ci/system_boundary_baseline.txt and only shrink; a justified keep takes
`// ALLOW(system_boundary): <reason>` (tools/ci/allow_annotations.py).

    B1  no `SSx.<var>` / `GLOB.<x>_service.<var>` / `system(/datum/system/X).<var>` outside the owner's folder
    B2  `system(/datum/system/X).proc()` outside X's folder must name a proc defined in X's api.dm
    B3  no `/datum/controller/subsystem/x/...`, `/datum/world_service/x/...` or `/datum/system/x/...`
        proc definitions outside the owner's folder
    B4  X calls Y's API only if Y is in X's `uses`
    B5  no cycle in `needs`, and every `needs` entry names a subsystem, world service or system
    B6  OM_EMIT* event types under X's folder are in X's `emits` (checked once X declares `emits`)
    B7  a /datum/system folder has an api.dm iff another folder calls the system

The owner of a subsystem or world service is the folder of the file that defines its SUBSYSTEM_DEF / SYSTEM_DEF /
GLOBAL_DATUM_INIT; of a /datum/system, the folder of the file that declares the type. Unit tests are outside the
boundary (they read private state through system_debug()).

Usage:
    python tools/ci/system_boundary_lint.py            # the CI check
    python tools/ci/system_boundary_lint.py --report   # every site
    python tools/ci/system_boundary_lint.py --update   # lower ceilings to the current counts (never adds)
    python tools/ci/system_boundary_lint.py --generate # write a fresh baseline from the current tree
"""
import os
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed, dm_files, read_baseline, write_baseline  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "system_boundary_baseline.txt")
LINT = "system_boundary"

SS_DEF = re.compile(r"^\s*(?:VERB_MANAGER_)?(?:SUBSYSTEM|SYSTEM)_DEF\((\w+)\)", re.M)
SERVICE_DEF = re.compile(r"^\s*GLOBAL_DATUM_INIT\((\w+_service),\s*(/datum/world_service[\w/]*)", re.M)
SYSTEM_TYPE = re.compile(r"^/datum/system/(\w+)\s*$", re.M)
TYPEDEF = re.compile(r"^(/[\w/]+)\s*$")
SS_ACCESS = re.compile(r"(?<![\w.])SS(\w+)\.(\w+)(\s*\()?")
SERVICE_ACCESS = re.compile(r"(?<![\w.])GLOB\.(\w+_service)\.(\w+)(\s*\()?")
SYSTEM_ACCESS = re.compile(r"(?<![\w.])system\(\s*(/datum/system/\w+)\s*\)\.(\w+)(\s*\()?")
PROC_DEF = re.compile(r"^/datum/(controller/subsystem|world_service|system)/(\w+)/(?:proc/)?(\w+)\s*\(")
EMIT = re.compile(r"OM_EMIT\w*\(\s*(/datum/om/event/[\w/]+)")
WRITE = re.compile(r"\s*(?:[-+*/|&^]|<<|>>)?=(?!=)")

SKIP_DIRS = ("code/modules/unit_tests/",)


def folder_of(rel):
    return os.path.dirname(rel)


def inside(rel, owner_dir):
    return rel == owner_dir or rel.startswith(owner_dir + "/")


def load_files():
    files = {}
    for path, rel in dm_files():
        if rel.startswith(SKIP_DIRS):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            raw = handle.read()
        files[rel] = (raw, raw.split("\n"), code_only(raw).split("\n"))
    return files


def list_arg(lines, start):
    """The typepaths of the `name = list(...)` whose first line is `start` (0-based), across lines."""
    text = ""
    depth = 0
    for line in lines[start:]:
        text += line + "\n"
        depth += line.count("(") - line.count(")")
        if depth <= 0:
            break
    return re.findall(r"/[\w/]+", text.split("list(", 1)[-1])


def scan_owners(files):
    """Owner folders and declarations. Returns (ss_owner, service_owner, system_owner, decls)."""
    ss_owner, service_owner, system_owner = {}, {}, {}
    for rel, (raw, _lines, _code) in files.items():
        for m in SS_DEF.finditer(raw):
            ss_owner.setdefault(m.group(1), folder_of(rel))
        for m in SERVICE_DEF.finditer(raw):
            service_owner.setdefault(m.group(1), (folder_of(rel), m.group(2)))
        for m in SYSTEM_TYPE.finditer(raw):
            system_owner.setdefault("/datum/system/" + m.group(1), folder_of(rel))
    return ss_owner, service_owner, system_owner


def declarations(files):
    """{type: {"needs": [...], "uses": [...], "emits": [...], "file": rel}} for every typedef with a list var."""
    decls = {}
    known = set()
    for rel, (_raw, _lines, code) in files.items():
        current = None
        for number, line in enumerate(code):
            m = TYPEDEF.match(line)
            if m:
                current = m.group(1)
                known.add(current)
                continue
            if current is None:
                continue
            for var in ("needs", "uses", "emits"):
                if re.match(r"\s+(?:var/list/)?%s\s*=\s*list\(" % var, line):
                    d = decls.setdefault(current, {"file": rel})
                    d[var] = list_arg(code, number)
    return decls, known


def strongly_connected(graph):
    """Tarjan's SCCs of size > 1 (or a self-loop), as sorted tuples."""
    index, low, on, stack, out, counter = {}, {}, set(), [], [], [0]

    def visit(v):
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on.add(v)
        for w in graph.get(v, ()):
            if w not in index:
                visit(w)
                low[v] = min(low[v], low[w])
            elif w in on:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop()
                on.discard(w)
                comp.append(w)
                if w == v:
                    break
            if len(comp) > 1 or v in graph.get(v, ()):
                out.append(tuple(sorted(comp)))

    sys.setrecursionlimit(10000)
    for v in list(graph):
        if v not in index:
            visit(v)
    return out


def check(files):
    """Returns (counts, sites): counts {baseline name: n}, sites {baseline name: [text]}."""
    counts, sites = Counter(), defaultdict(list)

    def hit(name, text):
        name = name.replace(" ", "%20")
        counts[name] += 1
        sites[name].append(text)

    ss_owner, service_owner, system_owner = scan_owners(files)
    decls, known = declarations(files)
    # SUBSYSTEM_DEF(x) declares /datum/controller/subsystem/x through a macro.
    known |= {"/datum/controller/subsystem/" + name for name in ss_owner}
    known |= {"/datum/system/" + name for name in ss_owner}

    api_procs = {}
    for typ, owner_dir in system_owner.items():
        api = files.get(owner_dir + "/api.dm")
        procs = set()
        if api:
            procs = set(re.findall(r"^/[\w/]+/(?:proc/)?(\w+)\s*\(", api[2] and "\n".join(api[2]), re.M))
        api_procs[typ] = procs

    system_called_from = defaultdict(set)

    for rel, (_raw, raw_lines, code) in files.items():
        for number, line in enumerate(code, 1):
            if allowed(raw_lines, number, LINT):
                continue
            where = "%s:%d: %s" % (rel, number, raw_lines[number - 1].strip())
            for m in SS_ACCESS.finditer(line):
                owner = ss_owner.get(m.group(1))
                if owner is None or inside(rel, owner):
                    continue
                if not m.group(3):
                    hit("B1:%s:SS%s" % (rel, m.group(1)), where)
            for m in SERVICE_ACCESS.finditer(line):
                own = service_owner.get(m.group(1))
                if own is None or inside(rel, own[0]):
                    continue
                if not m.group(3):
                    hit("B1:%s:GLOB.%s" % (rel, m.group(1)), where)
            for m in SYSTEM_ACCESS.finditer(line):
                typ, member, is_call = m.group(1), m.group(2), m.group(3)
                owner = system_owner.get(typ)
                if owner is None or inside(rel, owner):
                    continue
                system_called_from[typ].add(rel)
                if not is_call:
                    hit("B1:%s:%s" % (rel, typ), where)
                elif member not in api_procs.get(typ, ()):
                    hit("B2:%s:%s" % (rel, typ), where)
                else:
                    caller = next((t for t, d in system_owner.items() if inside(rel, d)), None)
                    if caller and typ not in decls.get(caller, {}).get("uses", ()):
                        hit("B4:%s:%s" % (rel, typ), where)
            m = PROC_DEF.match(line)
            if m:
                kind, name = m.group(1), m.group(2)
                if kind == "controller/subsystem":
                    owner = ss_owner.get(name)
                elif kind == "world_service":
                    owner = next((o[0] for o in service_owner.values() if o[1].endswith("/" + name)), None)
                else:
                    # SYSTEM_DEF(x) declares /datum/system/x through a macro, like SUBSYSTEM_DEF(x).
                    owner = ss_owner.get(name) or system_owner.get("/datum/system/" + name)
                if owner is not None and not inside(rel, owner):
                    hit("B3:%s:%s" % (rel, name), where)

    # B5: cycles in needs, and needs that name nothing.
    graph = {t: d["needs"] for t, d in decls.items() if d.get("needs")}
    for comp in strongly_connected(graph):
        hit("B5:cycle:" + "+".join(comp).replace(" ", ""), "needs cycle: " + " -> ".join(comp))
    for typ, d in decls.items():
        for need in d.get("needs", ()):
            if need not in known:
                hit("B5:unknown:%s->%s" % (typ, need), "%s needs %s, which no file declares" % (typ, need))

    # B6: emitted events are declared (once the system declares `emits`).
    for typ, owner_dir in system_owner.items():
        emits = decls.get(typ, {}).get("emits")
        if emits is None:
            continue
        for rel, (_raw, raw_lines, code) in files.items():
            if not inside(rel, owner_dir):
                continue
            for number, line in enumerate(code, 1):
                for m in EMIT.finditer(line):
                    if m.group(1) not in emits and not allowed(raw_lines, number, LINT):
                        hit("B6:%s:%s" % (rel, typ), "%s:%d emits %s" % (rel, number, m.group(1)))

    # B7: api.dm iff other folders call the system.
    for typ, owner_dir in system_owner.items():
        has_api = (owner_dir + "/api.dm") in files
        called = bool(system_called_from.get(typ))
        if called != has_api:
            hit("B7:%s" % typ, "%s: api.dm %s but %s" % (
                typ, "present" if has_api else "missing", "called from outside" if called else "never called from outside"))
    return counts, sites


def main(argv):
    files = load_files()
    counts, sites = check(files)
    if "--report" in argv:
        for name in sorted(counts):
            for text in sites[name]:
                print("%s  %s" % (name.split(":")[0], text))
    totals = Counter(name.split(":")[0] for name in counts.elements())
    header = [
        "System boundary ratchet (tools/ci/system_boundary_lint.py). `<rule>:<file>:<owner> <count>`; only shrinks.",
        "Regenerate the file with --generate only when the rules change; otherwise --update lowers ceilings.",
    ]
    if "--generate" in argv:
        write_baseline(BASELINE, header, dict(sorted(counts.items())))
        print("system_boundary: wrote %d entries" % len(counts))
        return 0
    base = read_baseline(BASELINE)
    if "--update" in argv:
        kept = {name: min(base[name], counts.get(name, 0)) for name in base if counts.get(name, 0) > 0}
        write_baseline(BASELINE, header, dict(sorted(kept.items())))
        print("system_boundary: baseline lowered to %d entries" % len(kept))
        return 0
    failed = False
    for name, count in sorted(counts.items()):
        ceiling = base.get(name)
        if ceiling is None or count > ceiling:
            print("system_boundary: FAIL %s: %d (ceiling %s)" % (name, count, "none" if ceiling is None else ceiling))
            for text in sites[name][:5]:
                print("    " + text)
            failed = True
    lowered = sum(1 for name in base if counts.get(name, 0) < base[name])
    print("system_boundary: %s; %s; %d entries below their ceiling (--update lowers them)" % (
        ", ".join("%s=%d" % (rule, totals[rule]) for rule in ("B1", "B2", "B3", "B4", "B5", "B6", "B7")),
        "FAILED" if failed else "ok", lowered))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
