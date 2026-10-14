#!/usr/bin/env python3
r"""Initialize() overrides that only refresh a machine's default parts -> default_parts() (code/library/machine/parts.dm).

    python tools/codemods/default_parts.py [--apply] [--sites] [--others]

An override `/T/Initialize(mapload)` whose body is `. = ..()` (or `..()`) then `default_apply_parts()` and nothing else is deleted, and
`default_parts()` goes into T's CAPABILITIES block (made when it has none; the block may be in another file). The capability calls
default_apply_parts() in on_holder_init(), inside ..(), so it moves ahead of the code an ancestor's override runs after its ..(): a type
whose ancestors below /obj/machinery override Initialize() is left as it is (`ancestor_init`). Idempotent. Run `analyze gen` afterwards.
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmlib import File, dm_files, procs_in, statements, strip_code  # noqa: E402

PARENT = re.compile(r"^(\.\s*=\s*\.\.\(\s*\)|\.\.\(\s*\)|\.\s*=\s*\.\.\(\s*mapload\s*\)|\.\.\(\s*mapload\s*\))$")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--sites", action="store_true")
    ap.add_argument("--others", action="store_true")
    args = ap.parse_args()
    rels = dm_files(("code/",), others=args.others)
    files = {r: File(r) for r in rels}
    inits = {}  # type -> (rel, proc)
    caps = {}  # type -> (rel, header index)
    for r, f in files.items():
        for p in procs_in(f):
            if p.name == "Initialize":
                inits[p.type] = (r, p)
        for i, l in enumerate(f.lines):
            m = re.match(r"^CAPABILITIES\((/[\w/]+)\)", l)
            if m:
                caps[m.group(1)] = (r, i)
    todo = []
    codes = {}
    for t, (r, p) in sorted(inits.items()):
        if not t.startswith("/obj/machinery/"):
            continue
        f = files[r]
        if p.start > 0 and "ALLOW(" in f.lines[p.start - 1] and "init/" not in f.lines[p.start - 1]:
            continue
        sts = [s for s in statements(f, p.start + 1, p.end)]
        codes_ = [s.code for s in sts]
        if len(codes_) != 2 or not PARENT.match(codes_[0]) or codes_[1] != "default_apply_parts()":
            continue
        anc = t
        blocked = False
        while anc.count("/") > 3:  # below /obj/machinery
            anc = anc.rsplit("/", 1)[0]
            if anc in inits:
                blocked = True
                break
        if blocked:
            codes[t] = "ancestor_init"
            continue
        todo.append((t, r, p))
    print("default_parts: %d overrides %s; left %d (ancestor_init)" % (len(todo), "converted" if args.apply else "convertible", len(codes)))
    if args.sites:
        for t, r, p in todo:
            print("    %s %s:%d" % (t, r, p.start + 1))
        for t, c in sorted(codes.items()):
            print("    left %s: %s" % (t, c))
    if not args.apply:
        return 0
    edits = {}
    for t, r, p in todo:
        f = files[r]
        first = p.start - 1 if p.start > 0 and "ALLOW(init/" in f.lines[p.start - 1] else p.start
        edits.setdefault(r, []).append((first, p.end - 1, None))
        entry = "\tdefault_parts()"
        if t in caps:
            cr, h = caps[t]
            cf = files[cr]
            e = h + 1
            while e < len(cf.lines) and (not cf.lines[e].strip() or cf.lines[e][0] in " \t"):
                e += 1
            while not cf.lines[e - 1].strip():
                e -= 1
            edits.setdefault(cr, []).append((e, e - 1, [entry]))
        else:
            edits.setdefault(r, []).append((first, first - 1, ["CAPABILITIES(%s)" % t, entry, ""]))
    for r, es in edits.items():
        L = files[r].lines
        for a, b, new in sorted(es, key=lambda e: (e[0], e[1]), reverse=True):
            if new is None:
                del L[a:b + 1]
                if a < len(L) and a > 0 and not L[a].strip() and not L[a - 1].strip():
                    del L[a]
            elif b < a:
                L[a:a] = new
            else:
                L[a:b + 1] = new
        files[r].dirty = True
        files[r].save()
    return 0


if __name__ == "__main__":
    sys.exit(main())
