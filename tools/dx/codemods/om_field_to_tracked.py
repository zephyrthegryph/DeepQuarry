"""OM_FIELD / OM_FIELD_TYPED -> a plain var + TRACKED(T, F), or TRACKED_BRIDGED(T, F, C) for a machine channel;
OM_FIELD_VIEW -> the plain var; OM_FIELD_VIEW_OF -> deleted (the var is declared on an ancestor).

A field whose name appears quoted in a code line (a stage `reads`, a periodic gate, an OM_DERIVE_FIELD input,
om_set(E, "F")) is still read through the OM field registry and is left alone; comment lines do not count. A field on a
machine channel (CHANGE_MACHINE_*) is left alone unless --machine is given: the machine pipeline wakes on it.

Usage: om_field_to_tracked.py [--dry] [--machine] [--skip=PREFIX ...]   (PREFIX is a code/ path prefix to leave untouched)
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', '..')
SKIP = ('code/datums/om/', 'code/datums/entity_state/', 'code/__defines/om.dm')
CALL = re.compile(r'^(\s*)OM_FIELD(_TYPED|_VIEW_OF|_VIEW)?\((.*)\)\s*(//.*)?$')
SKIP_EXTRA = tuple(a[7:] for a in sys.argv if a.startswith('--skip='))
MACHINE = '--machine' in sys.argv


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

# Lines that still read fields through the OM field registry (a periodic or repeat gate, a derived field's inputs, a stage's field list, an
# om_set/om_get by name), or write one through an ownership accessor, which raises the registered channel.
CONSUMER = re.compile(r'^\s*(DECLARE_PERIODIC\w*|DECLARE_REPEAT|OM_DERIVE_FIELD)\('
                      r'|\b(reads|wake_fields|fields|inputs)\s*=\s*list\('
                      r'|\bom_(set|get|read|value_of|field\w*)\(')
OWN_CALL = re.compile(r'\b(rel_set|rel_clear|rel_add|rel_remove|own_take|own_clear|own_set|shared_set|proto_set)\(')
CONSUMER_LINES = []
for p in files:
    if '_generated' in p or p.startswith('code/datums/om/'):
        continue
    for line in text[p].split('\n'):
        if line.lstrip().startswith('//'):
            continue
        if CONSUMER.search(line) or OWN_CALL.search(line):
            CONSUMER_LINES.append((p, line))

sites = []
for p in files:
    if p.startswith(SKIP + SKIP_EXTRA):
        continue
    for i, line in enumerate(text[p].split('\n')):
        m = CALL.match(line.rstrip('\r'))
        if m:
            sites.append((p, i, m, split_args(m.group(3))))

converted = skipped = 0
edits = {}
for p, i, m, a in sites:
    kind = m.group(2) or ''
    if p.startswith('code/modules/unit_tests/'):
        skipped += 1
        continue
    if kind == '_TYPED':
        ok = len(a) == 5
        T, F, C = a[0], a[2:3] and a[2], a[-1]
    elif kind == '_VIEW':
        ok = len(a) == 4
        T, F, C = a[0], a[2:3] and a[2], a[-1]
    elif kind == '_VIEW_OF':
        ok = len(a) == 3
        T, F, C = a[0], a[1:2] and a[1], a[-1]
    else:
        ok = len(a) == 4
        T, F, C = a[0], a[1:2] and a[1], a[-1]
    if not ok:
        print('ARGS?', p, i + 1, a)
        skipped += 1
        continue
    # Still read through the OM field registry, or written by an ownership accessor (own_field_changed() raises the channel).
    machine = C.startswith('CHANGE_MACHINE')
    # An ownership write raises the field's channel; only a machine channel has listeners (the machine pipeline wakes on it).
    users = [u for u, line in CONSUMER_LINES if ('"' + F + '"') in line or ('"!' + F + '"') in line or machine and re.search(r'' + re.escape(F) + r'', line) and OWN_CALL.search(line)]
    if users:
        print('KEEP', p, i + 1, F, users[:3])
        skipped += 1
        continue
    if machine and not MACHINE:
        print('KEEP(machine channel)', p, i + 1, F)
        skipped += 1
        continue
    ind = m.group(1)
    cr = '\r' if text[p].split('\n')[i].endswith('\r') else ''
    tail = (' ' + m.group(4)) if m.group(4) else ''
    if kind == '_VIEW_OF':
        new = None
    elif kind == '_VIEW':
        new = f'{ind}{T}/var/{a[1]}/{F}{tail}{cr}'
    else:
        D = a[3] if kind == '_TYPED' else a[2]
        vt = (a[1] + '/') if kind == '_TYPED' else ''
        track = f'TRACKED_BRIDGED({T}, {F}, {C})' if machine else f'TRACKED({T}, {F})'
        new = f'{ind}{T}/var/{vt}{F} = {D}{tail}{cr}\n{ind}{track}{cr}'
    edits.setdefault(p, {})[i] = new
    converted += 1

if '--dry' not in sys.argv:
    for p, e in edits.items():
        lines = text[p].split('\n')
        for i in sorted(e, reverse=True):
            if e[i] is None:
                del lines[i]
            else:
                lines[i] = e[i]
        open(os.path.join(ROOT, p), 'w', encoding='utf-8', errors='surrogateescape', newline='').write('\n'.join(lines))
print(f'converted {converted}, kept {skipped}, files {len(edits)}')
