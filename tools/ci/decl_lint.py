#!/usr/bin/env python3
"""Declarative-lifecycle lint (doc/rewrite/declarative_lifecycle.md).

Counts Initialize() / on_materialize() / on_destroy() body lines doing work that a lifecycle
declaration (code/__defines/lifecycle_decl.dm) now does. Each rule is a conversion backlog,
ratcheted shrink-only by site fingerprint in tools/ci/decl_baseline.txt.

Initialize() (and on_materialize() where noted):
    init_reagents      create_reagents( / reagents.add_reagent(        -> DECLARE_REAGENTS
    init_new_child     `var = new ...` into a var the type (or an ancestor) declares OWNED,
                       OWNED_LIST, HELD, SPILL or SPILL_LIST             -> DECLARE_DEFAULT_CHILD
    init_gas           `air_contents = new` / .adjust_gas(              -> DECLARE_GAS
    init_registry      registry_join( with src / GLOB.x[...] = src      -> DECLARE_REGISTRY
    init_service       GLOB.<x>_service.<proc>(src ...)                  -> DECLARE_SERVICE_MEMBER
    init_bind          connect_to_network() (redundant: power machines autoconnect at
                       materialize) and heat/vg binds                    -> DECLARE_BIND
    init_scheduling    om_task_periodic(src, / om_attach(src, / om_after(src, ...) in
                       Initialize() or on_materialize()                  -> DECLARE_PERIODIC /
                                                                            DECLARE_BEHAVIOUR /
                                                                            DECLARE_START_TIMER
    init_visuals       add_overlay( / cut_overlays( / icon_state = in Initialize()
                                                                         -> DECLARE_APPEARANCE
on_destroy():
    destroy_qdel_owned qdel / QDEL_NULL / QDEL_LIST of a declared OWNED*, HELD or SPILL* var
                       (phase 3/4 resolve it by its kind)
    destroy_drop       a contents loop that forceMove()s things out, or dump_contents()
                                                                         -> drop_contents
    destroy_registry   registry_leave( / GLOB.x -= src (dematerialize does it)
    destroy_scheduling om_task_periodic_stop( / STOP_PROCESSING( (teardown does it)
    destroy_unbind     disconnect_from_network() / vg_*unbind (phase 1 does it)
    destroy_effects    visible_message( / playsound( / `new /obj/...(loc|get_turf(...))`
                                                                         -> DESTROY_EFFECTS

A line (or the comment line above it) carrying `// ALLOW(decl): <reason>` is not counted.
Unit tests and benchmarks are skipped.

    python tools/ci/decl_lint.py            # the CI check
    python tools/ci/decl_lint.py --report   # every site, as file:line: rule
    python tools/ci/decl_lint.py --counts   # counts per rule and per top-level directory
    python tools/ci/decl_lint.py --update   # drop fixed sites from the baseline (never adds)
"""
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from allow_annotations import allowed, check_sites, write_sites  # noqa: E402
from ref_kinds import ref_decl  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "decl_baseline.txt")
EXEMPT = ("code/modules/unit_tests/", "code/modules/benchmarks/")

HEADER = re.compile(r"^(/[\w/]+)/(Initialize|on_materialize|on_destroy)\s*\(")
CHILD_KINDS = ("OWNED", "OWNED_LIST", "HELD", "SPILL", "SPILL_LIST")
OWNED_KINDS = ("OWNED", "OWNED_LIST", "OWNED_VALUES", "HELD", "SPILL", "SPILL_LIST")

INIT_RULES = [
    ("init_reagents", re.compile(r"\bcreate_reagents\s*\(|\breagents\.add_reagent\s*\(")),
    ("init_gas", re.compile(r"\bair_contents\s*=\s*new\b|\.adjust_gas\s*\(")),
    ("init_registry", re.compile(r"\bregistry_join\s*\([^)]*\bsrc\b|\bGLOB\.\w+\[[^\]]*\]\s*=\s*src\b")),
    ("init_service", re.compile(r"\bGLOB\.\w+_service\.\w+\(\s*src\b")),
    ("init_bind", re.compile(r"\bconnect_to_network\s*\(\s*\)|\bvg_\w*bind\w*\s*\(|\bheat_body_create\s*\(")),
    ("init_scheduling", re.compile(r"\bom_task_periodic\s*\(\s*src\s*,|\bom_attach\s*\(\s*src\s*,|\bom_after\s*\(\s*src\s*,")),
    ("init_visuals", re.compile(r"\badd_overlay\s*\(|\bcut_overlays\s*\(|^\s*(?:src\.)?icon_state\s*=")),
]
MATERIALIZE_RULES = [r for r in INIT_RULES if r[0] in ("init_scheduling", "init_service", "init_registry")]
NEW_INTO = re.compile(r"^\s*(?:src\.)?(\w+)\s*=\s*new\b")
DESTROY_RULES = [
    ("destroy_drop", re.compile(r"\bdump_contents\s*\(|\bfor\s*\(\s*var/[\w/]+\s+in\s+(?:src\.)?contents\b.*|\bfor\s*\(\s*var/[\w/]+\s+in\s+contents_of\(\s*src\s*\)")),
    ("destroy_registry", re.compile(r"\bregistry_leave\s*\(|\bGLOB\.\w+\s*-=\s*src\b")),
    ("destroy_scheduling", re.compile(r"\bom_task_periodic_stop\s*\(|\bSTOP_PROCESSING\s*\(")),
    ("destroy_unbind", re.compile(r"\bdisconnect_from_network\s*\(|\bvg_\w*unbind\w*\s*\(")),
    ("destroy_effects", re.compile(r"\bvisible_message\s*\(|\bplaysound\s*\(|\bnew\s+/obj/[\w/]+\s*\(\s*(?:loc|src\.loc|get_turf\([^)]*\)|T)\s*\)")),
]
QDEL_VAR = re.compile(r"\b(?:qdel|QDEL_NULL|QDEL_LIST|QDEL_LIST_ASSOC_VAL|QDEL_LAZYLIST)\s*\(\s*(?:src\.)?(\w+)\s*\)")
RULES = [r for r, _ in INIT_RULES] + ["init_new_child", "destroy_qdel_owned"] + [r for r, _ in DESTROY_RULES]


def dm_files():
    for base, _dirs, files in os.walk(os.path.join(ROOT, "code")):
        for name in files:
            if name.endswith(".dm"):
                full = os.path.join(base, name)
                yield full, os.path.relpath(full, ROOT).replace("\\", "/")


def read(full):
    with open(full, encoding="utf-8", errors="replace") as f:
        return f.read().replace("\r", "").split("\n")


def declared_refs(files):
    """{type: {var: kind}} from every DECLARE_REF line."""
    refs = collections.defaultdict(dict)
    for _rel, lines in files:
        for line in lines:
            if not line.startswith("DECLARE_REF("):
                continue
            try:
                got = ref_decl(line)
            except ValueError:
                continue
            if got:
                owner, var, kind, _opt = got
                refs[owner][var] = kind
    return refs


def kind_of(refs, type_path, var):
    parts = type_path.split("/")
    for cut in range(len(parts), 1, -1):
        kind = refs.get("/".join(parts[:cut]), {}).get(var)
        if kind:
            return kind
    return None


def scan(files, refs):
    sites = {rule: [] for rule in RULES}
    for rel, lines in files:
        if rel.startswith(EXEMPT):
            continue
        proc = type_path = None
        for number, line in enumerate(lines, 1):
            m = HEADER.match(line)
            if m:
                type_path, proc = m.group(1), m.group(2)
                continue
            if line and not line[0].isspace():
                proc = None
                continue
            if not proc or not line.strip():
                continue
            code = line.split("//", 1)[0]
            if not code.strip() or allowed(lines, number, "decl"):
                continue
            if proc == "Initialize":
                for rule, rx in INIT_RULES:
                    if rx.search(code):
                        sites[rule].append((rel, number))
                nm = NEW_INTO.match(code)
                if nm and kind_of(refs, type_path, nm.group(1)) in CHILD_KINDS:
                    sites["init_new_child"].append((rel, number))
            elif proc == "on_materialize":
                for rule, rx in MATERIALIZE_RULES:
                    if rx.search(code):
                        sites[rule].append((rel, number))
            else:
                for rule, rx in DESTROY_RULES:
                    if rx.search(code):
                        sites[rule].append((rel, number))
                for qm in QDEL_VAR.finditer(code):
                    if kind_of(refs, type_path, qm.group(1)) in OWNED_KINDS:
                        sites["destroy_qdel_owned"].append((rel, number))
                        break
    return sites


def main(argv):
    files = [(rel, read(full)) for full, rel in dm_files()]
    refs = declared_refs(files)
    sites = scan(files, refs)
    if "--report" in argv:
        for rule in RULES:
            for rel, number in sites[rule]:
                print("%s:%d: %s" % (rel, number, rule))
    if "--counts" in argv:
        by_dir = collections.defaultdict(collections.Counter)
        for rule in RULES:
            for rel, _n in sites[rule]:
                parts = rel.split("/")
                by_dir[rule]["/".join(parts[:3]) if len(parts) > 3 else rel] += 1
            print("%-20s %5d" % (rule, len(sites[rule])))
        total = collections.Counter()
        for rule in RULES:
            total.update(by_dir[rule])
        print("\nby directory (all rules):")
        for d, n in total.most_common():
            print("%5d  %s" % (n, d))
        return 0
    if "--update" in argv or "--seed" in argv:
        rows = write_sites(BASELINE, [
            "Declarative-lifecycle backlog (tools/ci/decl_lint.py, doc/rewrite/declarative_lifecycle.md).",
            "rule<TAB>file<TAB>normalized line. Shrink-only: convert sites, then `python tools/ci/decl_lint.py --update`.",
        ], sites, RULES, shrink_only="--seed" not in argv)
        print("decl lint: baseline written: %d sites" % rows)
        return 0
    hint = "declare it (doc/rewrite/declarative_lifecycle.md) instead of doing it by hand"
    failed = check_sites("decl", sites, BASELINE, {rule: hint for rule in RULES})
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
