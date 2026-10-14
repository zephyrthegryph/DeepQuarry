#!/usr/bin/env python3
"""om_after() to after() (doc/rewrite/om_retirement.md F3).

    om_after(E, delay, P)            -> after(E, delay, P)
    om_after(E, delay, P, a, b)      -> after(E, delay, P, with = list(a, b))
    om_after_realtime(E, delay, P..) -> after(E, delay, P, clock = CLOCK_WORLD, with = ...)

om_after(E, ...) is rx_after(E, delay, P, null, CLOCK_OWN, args, TRUE), which is after(); the realtime form is the same
on CLOCK_WORLD. Calls the script cannot parse (a call split over lines) are printed as HAND.

Usage: om_after_to_after.py [--write]
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import re
import subprocess
import sys

WRITE = '--write' in sys.argv
FORMS = {'om_after': None, 'om_after_realtime': 'CLOCK_WORLD'}


def split_args(s):
    out, depth, cur, i = [], 0, '', 0
    while i < len(s):
        ch = s[i]
        if ch == '"':
            j = i + 1
            while j < len(s) and s[j] != '"':
                if s[j] == '\\':
                    j += 1
                j += 1
            cur += s[i:j + 1]
            i = j + 1
            continue
        if ch in '([':
            depth += 1
        elif ch in ')]':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
        else:
            cur += ch
        i += 1
    out.append(cur.strip())
    return out


def call_end(s, start):
    depth = 0
    i = start
    while i < len(s):
        ch = s[i]
        if ch == '"':
            i += 1
            while i < len(s) and s[i] != '"':
                if s[i] == '\\':
                    i += 1
                i += 1
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def rewrite_line(line, where):
    rx = re.compile(r'(?<![\w.])(om_after_realtime|om_after)\(')
    out = ''
    pos = 0
    for m in rx.finditer(line):
        if m.start() < pos:
            continue
        end = call_end(line, m.end() - 1)
        if end < 0:
            print(f'HAND {where}: {line.strip()}')
            return line
        args = split_args(line[m.end():end])
        if len(args) < 3:
            print(f'HAND {where}: {line.strip()}')
            return line
        new = [args[0], args[1], args[2]]
        clock = FORMS[m.group(1)]
        if clock:
            new.append(f'clock = {clock}')
        if len(args) > 3:
            new.append('with = list(' + ', '.join(args[3:]) + ')')
        out += line[pos:m.start()] + 'after(' + ', '.join(new) + ')'
        pos = end + 1
    return out + line[pos:]


def main():
    files = [f for f in subprocess.run(['git', 'grep', '-z', '-l', '-E', r'\bom_after(_realtime)?\(', '--', '*.dm'],
                                       capture_output=True, text=True).stdout.split('\0') if f]
    changed = 0
    for f in files:
        if f.startswith('code/datums/om/') or f.startswith('code/__defines/'):
            continue
        text = open(f, encoding='utf-8', newline='').read()
        lines = text.split('\n')
        new = [rewrite_line(l, f'{f}:{i + 1}') if re.search(r'\bom_after(_realtime)?\(', l) else l for i, l in enumerate(lines)]
        if new != lines:
            changed += 1
            if WRITE:
                open(f, 'w', encoding='utf-8', newline='').write('\n'.join(new))
    print(f'files changed: {changed}')


if __name__ == '__main__':
    main()
