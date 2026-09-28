#!/usr/bin/env python3
"""Actor adapters (I3, doc/rewrite/interactions.md section 4).

The AI, cyborgs, ghosts and telekinesis reach an atom through their capability
adapter (code/modules/keybindings/adapters.dm): the atom's interactions the
adapter allows (INTERACT_SILICON / INTERACT_ROBOT / INTERACT_OBSERVER /
INTERACT_TK, code/__defines/interactions.dm), then the adapter's default
(`silicon_use` for silicons, the view UI or examine for ghosts, a telekinetic
grab). There are no attack_ai / attack_robot / attack_ghost / attack_tk procs;
this lint rejects any definition of them, and any call.

Usage:
    python tools/ci/actor_forwarding_lint.py
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
PATTERN = re.compile(r"\battack_(ai|robot|ghost|tk)\(")


def main():
    bad = []
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "code")):
        for name in files:
            if not name.endswith(".dm"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            with open(path, encoding="utf-8", errors="ignore") as handle:
                for number, line in enumerate(handle, 1):
                    code = line.split("//", 1)[0]
                    if PATTERN.search(code):
                        bad.append("%s:%d: %s" % (rel, number, line.strip()))
    if bad:
        print("actor forwarding lint: attack_ai/attack_robot/attack_ghost/attack_tk are gone. Declare an")
        print("INTERACT_SILICON / INTERACT_ROBOT / INTERACT_OBSERVER / INTERACT_TK interaction, or set silicon_use:")
        for entry in bad:
            print("  " + entry)
        return 1
    print("actor forwarding lint: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
