"""Survey own_set/own_add/own_put calls that pass transfer arguments. Usage: python own_transfers_survey.py [root]"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import re, sys, collections, pathlib

def split_args(s):
    out, depth, cur, q = [], 0, [], None
    i = 0
    while i < len(s):
        c = s[i]
        if q:
            cur.append(c)
            if c == chr(92): cur.append(s[i+1]); i += 1
            elif c == q: q = None
        elif c in '"\'': q = c; cur.append(c)
        elif c in '([{': depth += 1; cur.append(c)
        elif c in ')]}': depth -= 1; cur.append(c)
        elif c == ',' and depth == 0: out.append(''.join(cur)); cur = []
        else: cur.append(c)
        i += 1
    out.append(''.join(cur))
    return out

def calls(text, names):
    for m in re.finditer(r'(?<![\w.])(%s)\(' % '|'.join(names), text):
        i = m.end(); depth = 1; q = None
        while i < len(text) and depth:
            c = text[i]
            if q:
                if c == chr(92): i += 1
                elif c == q: q = None
            elif c in '"\'': q = c
            elif c == '(': depth += 1
            elif c == ')': depth -= 1
            i += 1
        yield m.start(), m.group(1), m.end(), i - 1, text[m.end():i-1]

if __name__ == '__main__':
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'code')
    shapes = collections.Counter()
    for p in root.rglob('*.dm'):
        t = p.read_text(encoding='utf-8', errors='replace')
        for s, name, a, b, body in calls(t, ['own_set', 'own_add', 'own_put']):
            args = split_args(body)
            named = tuple(sorted(x.split('=')[0].strip() for x in args if re.match(r'\s*\w+\s*=[^=]', x)))
            shapes[(name, len(args) - len(named), named)] += 1
    for k, v in shapes.most_common(): print(v, k)
