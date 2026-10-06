#!/usr/bin/env python3
"""Generated handler procs (click_input, mousedrop_input, input_tooltip, input_hovered, roll_*): a subtype whose ancestor already declares the
proc overrides it instead of declaring it again (`/T/proc/x(` -> `/T/x(`). Run after the lifecycle codemods."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmlib import File, dm_files  # noqa: E402
DEF = re.compile(r"^(/[\w/]+)/proc/(click_input|mousedrop_input|input_tooltip|input_hovered|roll_\w+)\(")
files = dm_files(["code/", "maps/"], others=True)
decl = {}
for rel in files:
    f = File(rel)
    for k, l in enumerate(f.lines):
        m = DEF.match(l)
        if m:
            decl.setdefault(m.group(2), []).append((m.group(1), rel, k))
fixed = 0
for name, sites in decl.items():
    types = {t for t, _, _ in sites}
    for t, rel, k in sites:
        parts = t.split("/")
        if any("/".join(parts[:i]) in types for i in range(2, len(parts))):
            f = File(rel)
            f.lines[k] = f.lines[k].replace("%s/proc/%s(" % (t, name), "%s/%s(" % (t, name), 1)
            f.dirty = True
            f.save()
            fixed += 1
print("fix_proc_redefs: %d overrides" % fixed)
