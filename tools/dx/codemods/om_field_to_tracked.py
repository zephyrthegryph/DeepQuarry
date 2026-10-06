"""OM_FIELD / OM_FIELD_TYPED -> a plain var + TRACKED_BRIDGED(T, F, C) (same setter, same channel, no field_def).

A field whose name appears quoted anywhere else in code/ (a stage `reads`, a periodic gate, an OM_DERIVE_FIELD input,
om_set(E, "F")) is still read through the OM field registry and is left alone. Usage: om_field_to_tracked.py [--dry]
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', '..')
SKIP = ('code/datums/om/', 'code/datums/entity_state/', 'code/__defines/om.dm')
CALL = re.compile(r'^(\s*)OM_FIELD(_TYPED)?\((.*)\)\s*(//.*)?$')


def split_args(s):
    out, depth, cur, q = [], 0, '', False
    for ch in s:
        if ch == '"':
            q = not q
        if not q:
            if ch in '([':
                depth += 1
            elif ch in ')]':
                depth -= 1
            elif ch == ',' and depth == 0:
                out.append(cur.strip())
                cur = ''
                continue
        cur += ch
    out.append(cur.strip())
    return out


files = []
for d, _, fs in os.walk(os.path.join(ROOT, 'code')):
    for f in fs:
        if f.endswith('.dm'):
            p = os.path.relpath(os.path.join(d, f), ROOT).replace(os.sep, '/')
            files.append(p)
text = {p: open(os.path.join(ROOT, p), encoding='utf-8', errors='surrogateescape', newline='').read() for p in files}

sites = []
for p in files:
    if p.startswith(SKIP):
        continue
    for i, line in enumerate(text[p].split('\n')):
        m = CALL.match(line.rstrip('\r'))
        if m:
            a = split_args(m.group(3))
            sites.append((p, i, m, a))

converted = skipped = 0
edits = {}
for p, i, m, a in sites:
    typed = bool(m.group(2))
    if (typed and len(a) != 5) or (not typed and len(a) != 4):
        print('ARGS?', p, i + 1, a)
        skipped += 1
        continue
    T, F = a[0], (a[2] if typed else a[1])
    quoted = re.compile(r'"' + re.escape(F) + r'"')
    users = [q for q in files if quoted.search(text[q])]
    if users:
        print('KEEP', p, i + 1, F, users[:3])
        skipped += 1
        continue
    D, C = (a[3], a[4]) if typed else (a[2], a[3])
    vt = (a[1] + '/') if typed else ''
    ind = m.group(1)
    cr = '\r' if text[p].split('\n')[i].endswith('\r') else ''
    tail = (' ' + m.group(4)) if m.group(4) else ''
    new = f'{ind}{T}/var/{vt}{F} = {D}{tail}{cr}\n{ind}TRACKED_BRIDGED({T}, {F}, {C}){cr}'
    edits.setdefault(p, {})[i] = new
    converted += 1

if '--dry' not in sys.argv:
    for p, e in edits.items():
        lines = text[p].split('\n')
        for i, new in e.items():
            lines[i] = new
        open(os.path.join(ROOT, p), 'w', encoding='utf-8', errors='surrogateescape', newline='').write('\n'.join(lines))
print(f'converted {converted}, kept {skipped}, files {len(edits)}')
