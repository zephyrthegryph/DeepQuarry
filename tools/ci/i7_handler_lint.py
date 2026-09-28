#!/usr/bin/env python3
"""I7: no legacy input-handler overrides anywhere (doc/rewrite/interactions.md sec 13).

Every type declares what it does with an input as interactions (DECLARE_INTERACTIONS /
EXTEND_INTERACTIONS and the compact shapes in code/__defines/interactions.dm, including
the *_DEFAULT shapes for a type's default touch, hit or drag). The entry procs are thin
dispatchers into the resolver defined once in code/_onclick/: attackby, attack_hand,
attack_self, click_alt and MouseDrop_T. This lint fails on any other definition of them.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HANDLER = re.compile(r'^(/\w[\w/ ]*?)/(attackby|attack_hand|attack_self|click_alt|MouseDrop_T)\(', re.M)
# The dispatchers themselves, and the client's activate-held-item verb (which calls attack_self).
ALLOWED = {
    '/atom/proc/attackby',
    '/atom/proc/attack_hand',
    '/atom/proc/click_alt',
    '/atom/proc/MouseDrop_T',
    '/obj/item/proc/attack_self',
    '/client/verb/attack_self',
}


def main():
    found = []
    for path in sorted((ROOT / 'code').rglob('*.dm')):
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding='utf-8', errors='ignore')
        for m in HANDLER.finditer(text):
            name = '%s/%s' % (m.group(1), m.group(2))
            if name in ALLOWED:
                continue
            line = text.count('\n', 0, m.start()) + 1
            found.append('%s:%d %s' % (rel, line, name))
    if found:
        print('%d legacy handler overrides. Declare interactions instead '
              '(DECLARE_INTERACTIONS / EXTEND_INTERACTIONS, code/__defines/interactions.dm):' % len(found))
        for entry in found:
            print('  ' + entry)
        return 1
    print('i7 handler lint: OK (no legacy handler overrides)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
