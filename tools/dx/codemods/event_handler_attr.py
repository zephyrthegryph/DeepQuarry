#!/usr/bin/env python3
"""EVENT_HANDLER to SHOULD_NOT_SLEEP(TRUE) (doc/rewrite/om_retirement.md F2).

The marker expanded to exactly that attribute. A proc that already says SHOULD_NOT_SLEEP drops the marker line.

Usage: event_handler_attr.py [files...]   (no files: every .dm the marker is in)
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import re
import subprocess
import sys

ATTR = re.compile(r'\s*(SHOULD_|PRIVATE_PROC|PROTECTED_PROC|RETURN_TYPE|set )')


def convert(f):
    lines = open(f, encoding='utf-8', newline='').read().split('\n')
    out = []
    changed = 0
    for i, l in enumerate(lines):
        if l.strip() != 'EVENT_HANDLER':
            out.append(l)
            continue
        has = False
        for rng in (range(i + 1, len(lines)), range(i - 1, -1, -1)):
            for j in rng:
                if not (lines[j].startswith('\t') and ATTR.match(lines[j])):
                    break
                if 'SHOULD_NOT_SLEEP' in lines[j]:
                    has = True
        changed += 1
        if not has:
            out.append(l.replace('EVENT_HANDLER', 'SHOULD_NOT_SLEEP(TRUE)'))
    if changed:
        open(f, 'w', encoding='utf-8', newline='').write('\n'.join(out))
    return changed


def main():
    files = sys.argv[1:] or [f for f in subprocess.run(['git', 'grep', '-z', '-l', '-w', 'EVENT_HANDLER', '--', '*.dm'],
                                                        capture_output=True, text=True).stdout.split('\0') if f]
    n = sum(convert(f) for f in files if f != 'code/__defines/om.dm')
    print(f'{n} markers')


if __name__ == '__main__':
    main()
