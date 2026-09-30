#!/usr/bin/env python3
"""Verb category lint (doc/rewrite unified plan 2.12).

A verb's tab is a VERB_CAT_* define (code/__defines/verb_categories.dm), never a raw string:

    set category = VERB_CAT_ABILITIES_VORE      // ok
    set category = "Abilities.Vore"             // counted
    ADMIN_VERB(x, R_ADMIN, "X", "Desc", "Admin.Game")   // counted (use ADMIN_CATEGORY_* / VERB_CAT_*)

Also counted: a define in verb_categories.dm that repeats another define's string (two names
for one tab), so a spelling variant cannot come back as a second define.

Skipped: #define lines outside the check above, code/modules/unit_tests, and every line
carrying `// ALLOW(verb_category): <reason>` (tools/ci/allow_annotations.py).

tools/ci/verb_category_baseline.txt holds the legacy sites; it only shrinks (it is empty now).

    python tools/ci/verb_category_lint.py            # the CI check
    python tools/ci/verb_category_lint.py --report   # every counted site
    python tools/ci/verb_category_lint.py --update   # drop fixed sites from the baseline (never adds)
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed, check_sites, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "verb_category_baseline.txt")
DEFINES = "code/__defines/verb_categories.dm"

SET_CATEGORY = re.compile(r'\bset\s+category\s*=\s*"')
MACRO_CATEGORY = re.compile(r'\b(?:DEBUG_VERB|ADMIN_VERB|ADMIN_VERB_AND_CONTEXT_MENU)\s*\((?:[^,()]*,){4}\s*"')
DEFINE = re.compile(r'^#define\s+(VERB_CAT_\w+)\s+"([^"]*)"')


def norm(text):
    return " ".join(text.split())


def scan():
    sites = {"raw_category": [], "duplicate_define": []}
    seen = {}
    files = glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)
    files += glob.glob(os.path.join(ROOT, "interface", "**", "*.dm"), recursive=True)
    for path in sorted(files):
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        if rel.startswith("code/modules/unit_tests/"):
            continue
        with open(path, encoding="utf-8", errors="ignore") as f:
            raw = f.read()
        raw_lines = raw.split("\n")
        if rel == DEFINES:
            for number, line in enumerate(raw_lines, 1):
                m = DEFINE.match(line)
                if not m:
                    continue
                key = m.group(2).lower()
                if key in seen:
                    sites["duplicate_define"].append((rel, number, norm(line)))
                seen[key] = m.group(1)
            continue
        if "category" not in raw:
            continue
        for number, line in enumerate(code_only(raw).split("\n"), 1):
            if line.lstrip().startswith("#") and "ADMIN_VERB" not in line and "DEBUG_VERB" not in line:
                continue
            if (SET_CATEGORY.search(line) or MACRO_CATEGORY.search(line)) \
                    and not allowed(raw_lines, number, "verb_category"):
                sites["raw_category"].append((rel, number, norm(raw_lines[number - 1])))
    return sites


def main(argv):
    sites = scan()
    if "--report" in argv:
        for rule, found in sites.items():
            for rel, number, text in found:
                print("%s:%d: [%s] %s" % (rel, number, rule, text))
    if "--update" in argv or "--seed" in argv:
        rows = write_sites(BASELINE, [
            "Raw verb category strings (tools/ci/verb_category_lint.py). rule<TAB>file<TAB>normalized line.",
            "Shrink-only: after a sweep, `python tools/ci/verb_category_lint.py --update`.",
        ], sites, shrink_only="--seed" not in argv)
        print("verb category lint baseline: %d sites" % rows)
        return 0
    failed = check_sites("verb_category", sites, BASELINE,
                         "use a VERB_CAT_* define from code/__defines/verb_categories.dm")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
