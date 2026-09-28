#!/usr/bin/env python3
"""O-slots: internal organs live only in keyed ledger slots (doc/rewrite/completion_plan.md 3.4).

An internal organ is a keyed entry (key: organ_tag) in its limb's SLOT_ID_PART_ORGANS
slot, or loose in a treeless mob's SLOT_ID_BODY slot. The mob-side caches
`internal_organs` / `internal_organs_by_name` and the limb's `internal_organs` are
deleted. Read with M.organ_in(tag) / INTERNAL_ORGANS(M) / limb.held_organs(), write
through the ledger. Ceiling: 0. A justified keep carries `// ALLOW(organ_slots): <reason>`.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
BANNED = re.compile(r'(?<![\w])internal_organs(_by_name)?\b')
ALLOW = 'ALLOW(organ_slots)'


def main():
    found = []
    for path in sorted((ROOT / 'code').rglob('*.dm')):
        rel = path.relative_to(ROOT).as_posix()
        for n, line in enumerate(path.read_text(encoding='utf-8', errors='ignore').splitlines(), 1):
            if ALLOW in line:
                continue
            if BANNED.search(line):
                found.append('%s:%d %s' % (rel, n, line.strip()))
    if found:
        print('%d uses of the deleted internal organ lists (ceiling 0). Use organ_in(tag), '
              'INTERNAL_ORGANS(M) or limb.held_organs() (code/modules/body/parts/queries.dm):' % len(found))
        for entry in found:
            print('  ' + entry)
        return 1
    print('organ slots lint: OK (0 uses of internal_organs / internal_organs_by_name)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
