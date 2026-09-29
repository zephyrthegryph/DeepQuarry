#!/usr/bin/env python3
"""Generic-systems lint (doc/rewrite/systems.md).

One ratchet per system of the "sys" wave. Each system lives in its own module
`tools/ci/sys_rules/<system>.py` (so workers on different systems never edit the same file)
exposing:

    RULES = {"rule_name": "fix hint", ...}
    def scan(files):  -> {"rule_name": [(rel, line_number), ...]}

`files` is a list of (rel, raw_lines) for every .dm under code/ and maps/ (unit tests and
benchmarks excluded). A site whose line (or the comment line above it) carries
`// ALLOW(sys_<rule>): <reason>` is not counted. Baselines are fingerprints in
`tools/ci/sys_baseline/<system>.txt`, shrink-only; the target for every rule is 0.

    python tools/ci/sys_lint.py              # the CI check
    python tools/ci/sys_lint.py --report     # every site, as file:line: rule
    python tools/ci/sys_lint.py --counts     # counts per rule
    python tools/ci/sys_lint.py --update     # drop fixed sites from the baselines (never adds)
    python tools/ci/sys_lint.py --seed SYSTEM  # create a baseline for a new system
    python tools/ci/sys_lint.py --only SYSTEM  # restrict to one system module
"""
import glob
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from allow_annotations import allowed, check_sites, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
RULES_DIR = os.path.join(os.path.dirname(__file__), "sys_rules")
BASE_DIR = os.path.join(os.path.dirname(__file__), "sys_baseline")
EXEMPT = ("code/modules/unit_tests/", "code/modules/benchmarks/")


def modules():
    for path in sorted(glob.glob(os.path.join(RULES_DIR, "*.py"))):
        name = os.path.splitext(os.path.basename(path))[0]
        if name.startswith("_"):
            continue
        spec = importlib.util.spec_from_file_location("sys_rules_" + name, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        yield name, mod


def rule_names():
    """Every sys rule, as the ALLOW name (`sys_<rule>`); read by allow_annotations.py."""
    out = {}
    for name, mod in modules():
        for rule in mod.RULES:
            out["sys_" + rule] = "tools/ci/sys_rules/%s.py" % name
    return out


def load_files():
    files = []
    for top in ("code", "maps"):
        for path in glob.glob(os.path.join(ROOT, top, "**", "*.dm"), recursive=True):
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            if rel.startswith(EXEMPT):
                continue
            with open(path, encoding="utf-8", errors="replace") as handle:
                files.append((rel, handle.read().split("\n")))
    return files


def run_module(mod, files, raw):
    found = mod.scan(files)
    out = {}
    for rule in mod.RULES:
        keep = []
        for site in found.get(rule, []):
            rel, number = site[0], site[1]
            if rule not in getattr(mod, "NO_ALLOW", ()) and allowed(raw[rel], number, "sys_" + rule):
                continue
            keep.append((rel, number))
        out[rule] = keep
    return out


def main(argv):
    only = None
    if "--only" in argv:
        only = argv[argv.index("--only") + 1]
    seed = None
    if "--seed" in argv:
        seed = argv[argv.index("--seed") + 1]
    files = load_files()
    raw = dict(files)
    failed = False
    for name, mod in modules():
        if only and name != only and name != seed:
            continue
        if seed and name != seed:
            continue
        sites = run_module(mod, files, raw)
        base = os.path.join(BASE_DIR, name + ".txt")
        header = ["sys_lint baseline for tools/ci/sys_rules/%s.py (doc/rewrite/systems.md); shrink-only, target 0" % name]
        if "--report" in argv:
            for rule, found in sites.items():
                for rel, number in found:
                    print("%s:%d: %s" % (rel, number, rule))
            continue
        if "--counts" in argv:
            for rule, found in sites.items():
                print("%-28s %6d" % (rule, len(found)))
            continue
        if seed:
            write_sites(base, header, sites, rules=list(mod.RULES), shrink_only=False)
            continue
        if "--update" in argv:
            write_sites(base, header, sites, rules=list(mod.RULES), shrink_only=True)
            continue
        if check_sites("sys/" + name, sites, base, mod.RULES):
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
