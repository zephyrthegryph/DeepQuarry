#!/usr/bin/env python3
r"""A searchable pile's `loot_decl = P` var -> the loot_search(table = P) entry of its CAPABILITIES block (code/library/loot/loot_entries.dm).

    python tools/codemods/loot_piles.py [--check] [--paths code/game/objects/structures ...]

    /obj/structure/loot_pile/maint/junk
        loot_decl = /loot/maint/junk                  ->   CAPABILITIES(/obj/structure/loot_pile/maint/junk)
                                                               loot_search(table = /loot/maint/junk)

A pile under another pile that already names a table changes it: configure(loot_search(table = P)). `wake_chance =` is not written here: a pile
that wakes a raccoon says so by hand (the trash pile). The block goes after the type's body, or into the type's existing block.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from capdecl import Blocks, File, all_files, type_ancestors  # noqa: E402

VAR = re.compile(r"^\tloot_decl = (?:LOOT_REF\()?(/loot/[\w/]+)\)?\s*(//.*)?$")
TYPE_LINE = re.compile(r"^(/[\w/]+)\s*(//.*)?$")


def main(argv):
    check = "--check" in argv
    paths = []
    if "--paths" in argv:
        for a in argv[argv.index("--paths") + 1:]:
            if a.startswith("--"):
                break
            paths.append(a.rstrip("/"))
    files = {r: File(r) for r in all_files()}
    sites = []  # (file, line index, type, table)
    for r, f in files.items():
        if paths and not any(r == p or r.startswith(p + "/") for p in paths):
            continue
        cur = None
        for i, line in enumerate(f.lines):
            m = TYPE_LINE.match(line)
            if m:
                cur = m.group(1)
                continue
            if line and line[0] not in "\t ":
                cur = None
                continue
            v = VAR.match(line)
            if v and cur:
                sites.append((f, i, cur, v.group(1)))
    by_type = {s[2]: s for s in sites}
    blocks = Blocks(files)
    ops = {}
    for f, i, ty, table in sites:
        configure = any(a in by_type for a in type_ancestors(ty))
        entry = ("\tconfigure(loot_search(table = %s))" if configure else "\tloot_search(table = %s)") % table
        existing = blocks.by_type.get(ty)
        ops.setdefault(f.rel, []).append((i, i + 1, []))
        if existing and existing[2] == "block":
            bf, bi, _ = existing
            ops.setdefault(bf.rel, []).append((blocks.block_end(bf, bi) + 1, blocks.block_end(bf, bi) + 1, [entry]))
        elif existing:
            print(f"residue: {ty}: legacy CAPABILITIES form")
        else:
            # after the type's body: the next column-0 line below the var, or the end of the file
            j = i + 1
            while j < len(f.lines) and (f.lines[j] == "" or f.lines[j][0] in "\t "):
                j += 1
            # keep trailing blank lines after the block, not before it
            k = j
            while k > i + 1 and f.lines[k - 1] == "":
                k -= 1
            ops[f.rel].append((k, k, ["", "CAPABILITIES(" + ty + ")", entry]))
            blocks.by_type[ty] = (f, -1, "block")
    for r, file_ops in ops.items():
        f = files[r]
        for start, end, new in sorted(file_ops, key=lambda o: (o[0], o[1]), reverse=True):
            f.lines[start:end] = new
        f.dirty = True
    if not check:
        for f in files.values():
            f.save()
    print(f"{'would convert' if check else 'converted'} {len(sites)} pile var(s) in {len(ops)} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
