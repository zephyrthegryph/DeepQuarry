#!/usr/bin/env python3
"""Lists procs that look unused. Report only: it never edits a file, and a listing is a lead to check, not a proof.

    python tools/ci/dead_code_scan.py [--root DIR] [DIR-PREFIX ...]   # candidates, optionally only under these code/ prefixes
    python tools/ci/dead_code_scan.py --selftest                      # proves the exclusions below (check_ratchets.sh runs it)

A name is a candidate when it occurs only at its definitions in every text file of the tree, comments and strings included.
That misses whatever reaches a proc without naming it, so these are never candidates:
  - DISPATCHED_PATHS: procs enumerated with typesof() rather than called. /hook runs through callHook() (a deleted startup hook
    once stopped bans from loading with every gate green); VV lists /mob procs; global_vars walks its own.
  - NATIVE_CALLBACKS: procs Rust invokes by name through call_id.
  - KEPT_NAME: built-name families (set_x, __setter_x), BYOND's own entry points (capitalised), logging and tracing (AGENTS.md 3e).
  - a name fitting a built string, "prefix[x]" or "[x]suffix", when the affix has at least 3 characters.
Add to these lists when a new dynamic path appears, and name it in the selftest.
"""
import collections
import os
import re
import sys
import tempfile

DISPATCHED_PATHS = re.compile(r"^/(hook|mob|datum/controller/global_vars)(/|$)")
NATIVE_CALLBACKS = {"consider_firelocks", "handle_decompression_floor_rip"}
KEPT_NAME = re.compile(r"^(set_|get_|on_|derive_|vg_|rustg_|_)|debug|trace|audit|log|dump|census|profile|metric|^[A-Z]")
SKIP_DIRS = {".git", "node_modules", "target", "data", "gen", "_generated"}
BINARY = (".png", ".ogg", ".dmi", ".wav", ".mp3", ".ttf", ".woff", ".woff2", ".jpg", ".gif", ".bin", ".lock", ".dll", ".so", ".exe", ".zip", ".ico", ".dmb", ".rsc")
WORD = re.compile(r"\b[A-Za-z_]\w*\b")
PROC_DEF = re.compile(r"^(/[\w/]+)?/proc/(\w+)\(", re.M)
BUILT = re.compile(r'"([A-Za-z_]*)\[[^\]"]+\]([A-Za-z_]*)"')


def scan(root, prefixes=()):
    words = collections.Counter()
    defs = collections.defaultdict(list)
    kept = set(NATIVE_CALLBACKS)
    affixes = set()
    for folder, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if name.endswith(BINARY):
                continue
            path = os.path.join(folder, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            try:
                text = open(path, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            words.update(WORD.findall(text))
            if name.endswith(".dm") and rel.startswith("code/"):
                for match in PROC_DEF.finditer(text):
                    defs[match[2]].append(rel)
                    if match[1] and DISPATCHED_PATHS.match(match[1]):
                        kept.add(match[2])
                for match in BUILT.finditer(text):
                    affixes.add((match[1], match[2]))
    out = []
    for name, where in defs.items():
        if name in kept or KEPT_NAME.search(name) or words[name] != len(where):
            continue
        if prefixes and not all(w.startswith(tuple(prefixes)) for w in where):
            continue
        if any(len(a + b) >= 3 and name.startswith(a) and name.endswith(b) for a, b in affixes):
            continue
        out.append((name, where[0]))
    return sorted(out)


def selftest():
    with tempfile.TemporaryDirectory() as root:
        os.makedirs(os.path.join(root, "code"))
        with open(os.path.join(root, "code", "a.dm"), "w", encoding="utf-8") as f:
            f.write(
                "/hook/startup/proc/loadBans()\n\treturn 1\n"
                "/mob/living/proc/vv_listed()\n\treturn\n"
                "/datum/controller/global_vars/proc/init_x()\n\treturn\n"
                "/turf/proc/handle_decompression_floor_rip(sum)\n\treturn\n"
                "/datum/x/proc/set_thing(v)\n\treturn\n"
                "/datum/x/proc/called()\n\treturn\n"
                "/datum/x/proc/caller_a()\n\tcalled()\n\tcaller_a()\n"
                '/datum/x/proc/bui_thing()\n\treturn\n/proc/z()\n\tcall(src, "bui_[z]")()\n\tz()\n'
                "/datum/x/proc/truly_unused()\n\treturn\n"
            )
        found = [name for name, _ in scan(root)]
    if found != ["truly_unused"]:
        print(f"dead_code_scan selftest: FAILED, listed {found}, wanted only truly_unused")
        return 1
    print("dead_code_scan selftest: ok")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    root = "."
    if "--root" in argv:
        at = argv.index("--root")
        root = argv[at + 1]
        del argv[at : at + 2]
    for name, where in scan(root, argv):
        print(f"{where}: {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
