#!/usr/bin/env python3
"""Stance and examine-text lint (roadmap I6b and I2b, doc/rewrite/interactions.md §8, §12).

I6b: the interaction choice carries the intent. Interactions declare the stance
they answer (`/datum/interaction/var/stance`, the INTERACT_*_AS shapes); the
resolver offers only the matching ones, effects read `interaction.stance`, and
code an interaction calls into takes a `stance` argument. This fails on:
  - the deleted stance-read macros IS_HELPING/IS_HARMING/IS_DISARMING/IS_GRABBING;
  - use_stance() (renamed input_stance(); set_use_stance() is the write and stays);
  - the deleted a_intent mirror;
  - input_stance() outside the input layer (INPUT_STANCE_READERS below): the
    resolver's stance clauses, the actor adapters and the mob-action entries
    that are not object interactions (click, bump, resist, an AI brain's choice).

I2b: examine help is generated from the declared interactions (the examine
Interactions section, screentips) and properties (get_mechanics_info()). This
fails on any description_info: the hand-written var is deleted.

Both ceilings are 0. Usage: python3 tools/ci/stance_examine_lint.py
"""

import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SCAN_DIRS = ["code", "maps"]

BANNED = [
    (re.compile(r"\bIS_(HELPING|HARMING|DISARMING|GRABBING)\b"), "stance-read macro; declare a stance on the interaction and read interaction.stance"),
    (re.compile(r"(?<![\w.])use_stance\s*\(|[.]use_stance\s*\("), "use_stance() is gone; the interaction that ran carries the stance"),
    (re.compile(r"\ba_intent\b"), "a_intent is gone; the interaction that ran carries the stance"),
    (re.compile(r"\bdescription_info\b"), "description_info is gone; examine text is generated from the interactions and properties"),
]

INPUT_STANCE = re.compile(r"\binput_stance\s*\(")
# Files (prefixes) that make up the input layer: the only readers of a mob's stance.
INPUT_STANCE_READERS = (
    "code/modules/mob/combat_mode.dm",          # defines it and the resolver's stance clauses
    "code/datums/interactions/",                # the resolver
    "code/datums/operations/actions.dm",        # the op router: the stance is a gesture modifier of the bind profile
    "code/datums/operations/req.dm",            # req_stance(): an op's stance, as the resolver's stance clauses
    "code/modules/keybindings/",                # the actor adapters: click entries pass it on
    "code/modules/mob/living/living_movement.dm",  # bump entry (a mob action)
    "code/modules/vore/eating/belly_obj_resist.dm",  # resist entry (a mob action)
    "code/modules/combat_ai/",                  # AI brains choose the stance their mob acts with
    "code/modules/unit_tests/",
)


def main():
    errors = []
    for scan in SCAN_DIRS:
        base = os.path.join(ROOT, scan)
        for dirpath, _, files in os.walk(base):
            for name in files:
                if not name.endswith(".dm"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
                with open(path, encoding="utf-8", errors="replace") as handle:
                    for number, line in enumerate(handle, 1):
                        for pattern, why in BANNED:
                            if pattern.search(line):
                                errors.append(f"{rel}:{number}: {why}")
                        code = line.split("//", 1)[0]
                        if INPUT_STANCE.search(code) and not rel.startswith(INPUT_STANCE_READERS):
                            errors.append(f"{rel}:{number}: input_stance() outside the input layer; take the stance from the interaction or a stance argument")
    for error in errors:
        print(error)
    if errors:
        print(f"stance_examine_lint: {len(errors)} violation(s) (ceiling 0)")
        return 1
    print("stance_examine_lint: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
