"""Finished sweeps stay finished (doc/rewrite/completion_plan.md: I-menu, G-traits, MED-4).

Each kind is at 0 and has no ceiling: any site in code/ fails.
    radial    show_radial_menu( / show_radial_menu_persistent( / new /datum/radial_menu
              outside the radial implementation (code/_onclick/hud/radial*.dm). Action
              pickers ask om_ask(user, /datum/om/prompt/choice/radial, ...) or are Menu
              interactions. Genuinely non-action UI is kept with `// ALLOW(radial): reason`.
    traits    ADD_TRAIT( / REMOVE_TRAIT( / HAS_TRAIT( and the other trait macros, or the
              _status_traits list. Traits are grants: add_trait()/remove_trait()/has_trait()
              (code/_helpers/traits.dm). No allow annotation.
    disease   /datum/disease. Harm over time is an affliction (/datum/affliction/contagion).
              No allow annotation.

Comments and strings are ignored.

Usage:
    python tools/ci/leftovers_lints.py                 # the CI check
    python tools/ci/leftovers_lints.py --report NAME   # every site of one kind
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

PATTERNS = {
    "radial": re.compile(
        r"(?<![\w/])show_radial_menu(?:_persistent)?\s*\(|\bnew\s*/datum/radial_menu\b"
    ),
    "traits": re.compile(
        r"(?<![\w/])(?:ADD_TRAIT|REMOVE_TRAIT|REMOVE_TRAITS_IN|REMOVE_TRAITS_NOT_IN|REMOVE_TRAIT_NOT_FROM"
        r"|HAS_TRAIT|HAS_TRAIT_FROM|HAS_TRAIT_FROM_ONLY|HAS_TRAIT_NOT_FROM|HAS_MIND_TRAIT"
        r"|GET_TRAIT_SOURCES|COUNT_TRAIT_SOURCES|TRAIT_CALLBACK_ADD|TRAIT_CALLBACK_REMOVE)\s*\("
        r"|\b_status_traits\b"
    ),
    "disease": re.compile(r"/datum/disease\b"),
}

# The radial implementation itself may build menus.
EXEMPT = {
    "radial": re.compile(r"^code/_onclick/hud/radial[^/]*\.dm$"),
}

# Kinds a `// ALLOW(<kind>): reason` keeps.
ANNOTATED = {"radial"}


def sites():
    found = {k: [] for k in PATTERNS}
    for path in sorted(glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)):
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        raw = open(path, encoding="utf-8", errors="replace").read()
        raw_lines = raw.split("\n")
        text = code_only(raw)
        for lineno, line in enumerate(text.split("\n"), 1):
            for name, pat in PATTERNS.items():
                if not pat.search(line):
                    continue
                exempt = EXEMPT.get(name)
                if exempt and exempt.match(rel):
                    continue
                if name in ANNOTATED and allowed(raw_lines, lineno, name):
                    continue
                found[name].append(f"{rel}:{lineno}")
    return found


def main():
    found = sites()
    if "--report" in sys.argv:
        for s in found[sys.argv[sys.argv.index("--report") + 1]]:
            print(s)
        return 0
    bad = False
    for k, v in found.items():
        print(f"{k}: {len(v)} {'OK' if not v else 'FAIL'}")
        for s in v[:20]:
            print(f"  {s}")
        if v:
            bad = True
    if bad:
        print("Radials ask a typed prompt; traits are grants; diseases are afflictions (tools/ci/leftovers_lints.py)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
