"""Codemod: turf `air` reads -> the lazy accessor `turf_air()`.

A read `X.air` whose X is declared as a turf (a `var/turf/...` local, a proc argument typed `turf/...`, a `for(var/turf/...` loop
var, or `src` in a turf proc), and a bare `air` inside a proc defined on a `/turf` path, becomes `X.turf_air()` / `turf_air()`.
`nameof(air)` on a turf becomes `nameof(_air)`. Writes (`X.air =`, `air =`) are reported, not rewritten.

Usage: python air_codemod.py [--apply] [--only FILE:LINE ...]
"""
import os
import re
import sys

ROOT = 'code'
SKIP = ('code/engine/_generated', 'code/_generated')
SKIP_FILES = ('code/domains/atmos/environmental/linda_turf_tile.dm',)

apply = '--apply' in sys.argv
only = set()
if '--only' in sys.argv:
    only = set(sys.argv[sys.argv.index('--only') + 1:])

PROC_HEADER = re.compile(r'^(/[\w/]+)/(?:proc/|verb/)?(\w+)\((.*)\)\s*$')
TYPE_DEF = re.compile(r'^(/[\w/]+)\s*$')
DOT_AIR = re.compile(r'(?<![\w.])((?:src|[A-Za-z_]\w*))(\??)\.air\b(?![\w(])')
NAMEOF_DOT_AIR = re.compile(r'nameof\(((?:src|[A-Za-z_]\w*))\.air\)')
BARE_AIR = re.compile(r'(?<![\w.])air\b(?![\w(])')
NAMEOF_AIR = re.compile(r'nameof\(air\)')


def strip_strings_comments(line):
    """The line with string text and // comments blanked (same length): a match there is not a site. An embedded
    expression inside a string ("[T.air]") stays code."""
    out = []
    i = 0
    in_str = None
    depth = 0  # [ ] nesting inside a string: code
    while i < len(line):
        c = line[i]
        if in_str and depth == 0:
            if c == '\\' and i + 1 < len(line):
                out.append('  ')
                i += 2
                continue
            if c == in_str:
                in_str = None
                out.append(' ')
            elif c == '[' and in_str == '"':
                depth = 1
                out.append(' ')
            else:
                out.append(' ')
            i += 1
            continue
        if in_str and depth:
            if c == '[':
                depth += 1
            elif c == ']':
                depth -= 1
                if depth == 0:
                    out.append(' ')
                    i += 1
                    continue
            out.append(c)
            i += 1
            continue
        if c in '"\'':
            in_str = c
            out.append(' ')
            i += 1
            continue
        if line.startswith('//', i):
            out.append(' ' * (len(line) - i))
            break
        out.append(c)
        i += 1
    return ''.join(out)


FILE_LINES = []


def declared_turf(name, proc_lines, header_args, owner):
    if name == 'src':
        return owner.startswith('/turf')
    decl = re.compile(r'var/((?:\w+/)*)' + re.escape(name) + r'\b(?!/)')
    found = None
    for l in proc_lines:
        for m in decl.finditer(l):
            found = m.group(1)
    if found is None:
        for a in header_args.split(','):
            m = re.match(r'\s*(?:var/)?((?:\w+/)*)' + re.escape(name) + r'\b', a)
            if m:
                found = m.group(1)
    if found is None:
        # a var of the proc's datum, declared in this file
        for l in FILE_LINES:
            if not l.startswith('\t') or l.startswith('\t\t'):
                continue
            m = re.match(r'\tvar/((?:\w+/)*)' + re.escape(name) + r'\b(?!/)', l)
            if m:
                found = m.group(1)
    return bool(found) and found.startswith('turf/')


report = []
changed_files = 0
sites = 0
for dirpath, _, files in os.walk(ROOT):
    rel_dir = dirpath.replace('\\', '/')
    if rel_dir.startswith(SKIP):
        continue
    for f in files:
        if not f.endswith('.dm'):
            continue
        path = os.path.join(dirpath, f).replace('\\', '/')
        if path in SKIP_FILES:
            continue
        text = open(path, encoding='utf-8', errors='surrogateescape', newline='').read()
        if 'air' not in text:
            continue
        lines = text.split('\n')
        FILE_LINES[:] = lines
        owner = ''
        header_args = ''
        proc_start = 0
        out = list(lines)
        touched = False
        for i, line in enumerate(lines):
            if line and not line[0].isspace():
                m = PROC_HEADER.match(line)
                if m:
                    owner = m.group(1)
                    header_args = m.group(3)
                    proc_start = i
                    continue
                m = TYPE_DEF.match(line)
                if m:
                    owner = m.group(1)
                    header_args = ''
                    proc_start = i
                    continue
            key = f'{path}:{i + 1}'
            if only and key not in only:
                continue
            code = strip_strings_comments(line)
            new = line
            # rewrite right to left so spans stay valid
            edits = []
            for m in NAMEOF_DOT_AIR.finditer(code):
                if declared_turf(m.group(1), lines[proc_start:i + 1], header_args, owner):
                    edits.append((m.start(), m.end(), f'nameof({m.group(1)}._air)'))
            for m in DOT_AIR.finditer(code):
                if any(s <= m.start() < e for s, e, _ in edits):
                    continue
                name = m.group(1)
                if not declared_turf(name, lines[proc_start:i + 1], header_args, owner):
                    continue
                rest = code[m.end():].lstrip()
                if rest.startswith('=') and not rest.startswith('=='):
                    report.append(f'{key}: write {line.strip()}')
                    continue
                edits.append((m.start(), m.end(), f'{name}{m.group(2)}.turf_air()'))
            local_air = any(re.search(r'var/(?:\w+/)*air\b(?!/)', l) for l in lines[proc_start + 1:i]) or re.search(r'(?:^|,|\()\s*(?:var/)?(?:\w+/)*air\s*(?:,|$|=)', header_args)
            if owner.startswith('/turf') and line.startswith('\t') and not local_air:
                for m in BARE_AIR.finditer(code):
                    if any(s <= m.start() < e for s, e, _ in edits):
                        continue
                    before = code[:m.start()]
                    if re.search(r'var/[\w/]*\s*$', before) or before.rstrip().endswith('nameof('):
                        continue
                    rest = code[m.end():].lstrip()
                    if rest.startswith('=') and not rest.startswith('=='):
                        report.append(f'{key}: write {line.strip()}')
                        continue
                    if re.search(r'(QDEL_NULL|rel_clear|rel_take)\(\s*$', before):
                        edits.append((m.start(), m.end(), '_air'))
                        continue
                    edits.append((m.start(), m.end(), 'turf_air()'))
            if owner.startswith('/turf'):
                for m in NAMEOF_AIR.finditer(code):
                    edits.append((m.start(), m.end(), 'nameof(_air)'))
            if not edits:
                continue
            for s, e, rep in sorted(edits, reverse=True):
                new = new[:s] + rep + new[e:]
                sites += 1
            out[i] = new
            touched = True
            report.append(f'{key}: {line.strip()}  ->  {new.strip()}')
        if touched:
            changed_files += 1
            if apply:
                open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write('\n'.join(out))

print('\n'.join(report))
print(f'# {sites} site(s) in {changed_files} file(s)' + ('' if apply else ' (dry run)'))
