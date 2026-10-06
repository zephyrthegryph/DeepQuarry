#!/usr/bin/env python3
"""Life stages to sequence steps (doc/rewrite/life_sequences.md S3, doc/rewrite/om_retirement.md L1).

Every /datum/om/stage/life/<family>[/<variant>] becomes procs on the mob type its `of` names:

    perform(self, ctx)      -> /mob/T/proc/life_<family>(datum/seq_frame/life/F)
    idle(self)              -> /mob/T/proc/life_<family>_due()          (the returns negated: should_run)
    rewake_delay(self)      -> /mob/T/proc/life_<family>_rewake()
    applies(self)           -> /mob/T/proc/life_<family>_applies()      (the declaration is wrapped in it)
    <helper>(self, args...) -> /mob/T/proc/life_<family>_<helper>(args...)

Trait stages (/datum/om/stage/life/trait/<x>) become contributed steps: the contributor (a /datum/trait_state, or the
datum that called om_stage_add()) declares them in its own life_steps().

The step declarations (seq_step(), the derived `after =` edges, `when =`, `reads =`, `should_run =`, `rewake =`) are
written to code/modules/mob/living/life/life_steps.dm, one life_steps() override per mob type.

Bodies move verbatim except: `self.` -> `src.`, `self` -> `src`, the frame calls (`ctx.fact("x")`, `ctx.abort()`,
`ctx.set_fact()`, `ctx.forget()`, `ctx.dt`) -> the seq_frame's, helper calls -> the renamed procs, and `type`
tests on the stage path evaluated per variant. Anything the script cannot translate is listed as HAND on stdout.

Usage: life_stage_steps.py [--write]   (dry run prints the plan and the HAND list)
"""
import collections
import os
import re
import subprocess
import sys

ROOT = '/datum/om/stage/life'
STEPS_FILE = 'code/modules/mob/living/life/life_steps.dm'
WRITE = '--write' in sys.argv
SKIP_DIRS = ('code/modules/unit_tests/', 'code/modules/benchmarks/', 'code/datums/om/')

HAND = []


def hand(msg):
    HAND.append(msg)


def git_files():
    out = subprocess.run(['git', 'grep', '-l', ROOT, '--', '*.dm'], capture_output=True, text=True).stdout
    return [f for f in out.split('\n') if f and not f.startswith(SKIP_DIRS)]


# ---------------------------------------------------------------- parsing

HEAD_TYPE = re.compile(r'^(/datum/om/stage/life(?:/[A-Za-z0-9_]+)*)\s*(//.*)?$')
HEAD_PROC = re.compile(r'^(/datum/om/stage/life(?:/[A-Za-z0-9_]+)*?)/(proc/)?([A-Za-z0-9_]+)\((.*)\)\s*(as\s+\S+)?\s*(//.*)?$')


class Block:
    def __init__(self, f, start, end, doc_start):
        self.file = f
        self.start = start      # header line index
        self.end = end          # exclusive
        self.doc_start = doc_start
        self.kind = None
        self.path = None
        self.proc = None
        self.params = None
        self.ret = None
        self.lines = None


def split_blocks(f, L):
    """Top-level blocks: a col-0 non-comment header, its indented body, the comment lines directly above it."""
    blocks = []
    i = 0
    n = len(L)
    while i < n:
        line = L[i]
        if line and not line[0].isspace() and not line.startswith('//') and not line.startswith('#'):
            j = i + 1
            while j < n and (L[j] == '' or L[j][0].isspace()):
                j += 1
            # trailing blank lines are separation, not body
            k = j
            while k > i + 1 and L[k - 1].strip() == '':
                k -= 1
            d = i
            while d > 0 and L[d - 1].startswith('//'):
                d -= 1
            blocks.append(Block(f, i, k, d))
            i = j
            continue
        i += 1
    return blocks


class Stage:
    def __init__(self, path):
        self.path = path
        self.vars = {}          # name -> expression text
        self.var_lines = {}
        self.procs = {}         # name -> Block
        self.type_block = None
        self.extra_var_decls = []

    def __repr__(self):
        return self.path


stages = {}
file_lines = {}
file_blocks = {}


def stage(path):
    if path not in stages:
        stages[path] = Stage(path)
    return stages[path]


def parse():
    for f in git_files():
        L = open(f, encoding='utf-8').read().split('\n')
        file_lines[f] = L
        bl = split_blocks(f, L)
        file_blocks[f] = bl
        for b in bl:
            h = L[b.start]
            m = HEAD_TYPE.match(h)
            if m:
                b.kind = 'type'
                b.path = m.group(1)
                S = stage(b.path)
                if S.type_block:
                    hand(f'{f}:{b.start + 1}: second type block for {b.path}')
                S.type_block = b
                for li in range(b.start + 1, b.end):
                    s = L[li].strip()
                    if not s or s.startswith('//'):
                        continue
                    mm = re.match(r'^(var/(?:[A-Za-z_/]+/)?)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*(.*?))?\s*(//.*)?$', s)
                    if not mm:
                        hand(f'{f}:{li + 1}: unparsed stage var line: {s}')
                        continue
                    if mm.group(1):
                        S.extra_var_decls.append((li, s))
                    S.vars[mm.group(2)] = (mm.group(3) or '').strip()
                    S.var_lines[mm.group(2)] = li
                continue
            m = HEAD_PROC.match(h)
            if m:
                b.kind = 'proc'
                b.path = m.group(1)
                b.proc = m.group(3)
                b.params = m.group(4)
                b.ret = m.group(5)
                S = stage(b.path)
                if b.proc in S.procs:
                    hand(f'{f}:{b.start + 1}: second definition of {b.path}/{b.proc}')
                S.procs[b.proc] = b
                continue
            if h.startswith(ROOT):
                hand(f'{f}:{b.start + 1}: unparsed stage header: {h}')


# ---------------------------------------------------------------- the stage tree

BASE_DEFAULTS = {
    'of': '/mob/living',
    'wake_on': 'CHANGE_MOB_LOC | CHANGE_MOB_CONDITIONS',
    'life_sets': 'LIFE_SET_LIVING',
    'order': '0',
    'run_if': '',
    'reads': '',
    'woken_by': '',
}


def parent_path(p):
    return p.rsplit('/', 1)[0]


def eff(path, var):
    """A var's value on stage `path`, inherited along the stage tree."""
    p = path
    while p.startswith(ROOT):
        S = stages.get(p)
        if S and var in S.vars:
            return S.vars[var]
        if p == ROOT:
            break
        p = parent_path(p)
    if var == 'order' and path.startswith(ROOT + '/trait'):
        return 'LIFE_PHASE_INPUT + 10'
    if var == 'wake_on' and path.startswith(ROOT + '/trait'):
        return '0'
    return BASE_DEFAULTS.get(var, '')


def family_of(path):
    rel = path[len(ROOT) + 1:].split('/') if path != ROOT else []
    if not rel:
        return None
    if rel[0] == 'trait':
        if len(rel) < 2:
            return None
        return ROOT + '/trait/' + rel[1]
    return ROOT + '/' + rel[0]


def fam_key(root):
    return root[len(ROOT) + 1:].replace('/', '_')


def eval_order(expr):
    env = {'LIFE_PHASE_INPUT': 1000, 'LIFE_PHASE_BODY': 2000, 'LIFE_PHASE_MIND': 3000,
           'LIFE_PHASE_OUTPUT': 4000, 'LIFE_PHASE_TAIL': 5000}
    try:
        return eval(expr, {}, env)
    except Exception:
        hand(f'order expression not evaluable: {expr}')
        return 0


def band(order):
    if order >= 5000:
        return 'LIFE_TAIL'
    if order >= 4000:
        return 'LIFE_OUTPUT'
    if order >= 3000:
        return 'LIFE_MIND'
    if order >= 2000:
        return 'LIFE_BODY'
    return 'LIFE_INPUT'


RUN_IF = {
    '': [],
    'LIFE_RUN_IF_PLACED': ['placed'],
    'FACT("placed")': ['placed'],
    'LIFE_RUN_IF_PLACED_ALIVE': ['placed', 'alive'],
    'LIFE_RUN_IF_STATUS_OK': ['placed', 'status_ok'],
    'LIFE_RUN_IF_LIVE_BIOLOGY': ['!in_stasis', 'alive'],
    'LIFE_RUN_IF_PLACED_LIVE_BIOLOGY': ['placed', '!in_stasis', 'alive'],
    'LIFE_RUN_IF_PLACED_UNPAUSED': ['placed', '!in_stasis'],
    'LIFE_RUN_IF_DEAD_BIOLOGY': ['!in_stasis', '!alive'],
    'FACT("alive")': ['alive'],
    'NOT_OF(FACT("alive"))': ['!alive'],
    'ALL_OF(FACT("placed"), FACT("alive"))': ['placed', 'alive'],
}


class Family:
    def __init__(self, root):
        self.root = root
        self.key = fam_key(root)
        self.trait = root.startswith(ROOT + '/trait/')
        self.variants = []      # stage paths that are variants (root first)
        self.members = []       # every stage path in the family

    @property
    def handler(self):
        return 'life_' + self.key


families = {}


def build_families():
    for p in sorted(stages):
        r = family_of(p)
        if not r:
            continue
        F = families.setdefault(r, Family(r))
        F.members.append(p)
    for r, F in families.items():
        if r not in stages:
            stages[r] = Stage(r)
        for p in sorted(F.members, key=lambda x: (x.count('/'), x)):
            if p == r:
                F.variants.insert(0, p)
                continue
            par = parent_path(p)
            if eff(p, 'of') == eff(par, 'of'):
                if stages[p].procs:
                    hand(f'{p}: a stage segment that only inherits its parent\'s of but defines procs')
                continue
            F.variants.append(p)
        if r not in F.variants:
            F.variants.insert(0, r)
        for v in F.variants:
            if v != r and stages[v].vars.get('order') not in (None,) and v in stages and 'order' in stages[v].vars:
                hand(f'{v}: a variant overrides order')


# ---------------------------------------------------------------- body translation

FRAME_SUBS = [
    (re.compile(r'ctx\.fact\("environment"\)'), 'F.environment()'),
    (re.compile(r'ctx\.fact\("alive"\)'), 'F.alive()'),
    (re.compile(r'ctx\.fact\("placed"\)'), 'F.placed()'),
    (re.compile(r'ctx\.fact\("in_stasis"\)'), 'F.in_stasis()'),
    (re.compile(r'ctx\.fact\("status_ok"\)'), 'F.status_passed()'),
    (re.compile(r'ctx\.abort\(\)'), 'F.abort()'),
    (re.compile(r'ctx\.set_fact\("status_ok",\s*(.*)\)$'), r'F.status_ok = \1'),
    (re.compile(r'ctx\.forget\('), 'F.forget('),
    (re.compile(r'ctx\.dt\b'), 'F.dt'),
    (re.compile(r'ctx\.stasis\b'), 'F.stasis'),
]


def split_params(params):
    out = []
    depth = 0
    cur = ''
    for ch in params:
        if ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
            continue
        if ch in '([':
            depth += 1
        elif ch in ')]':
            depth -= 1
        cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


VALUE_ONLY = {}


def eval_type_tests(text, variant, F):
    """`type == /datum/om/stage/...`, `type != ...`, `type in <static list>`: evaluated for `variant`."""
    if re.search(r'\btype in value_only\b', text):
        text = re.sub(r'\btype in value_only\b', 'TRUE' if variant in VALUE_ONLY.get(F.root, ()) else 'FALSE', text)
    def eq(m):
        neg = m.group(1) == '!='
        same = m.group(2) == variant
        return 'TRUE' if same != neg else 'FALSE'
    text = re.sub(r'\btype\s*(==|!=)\s*(/datum/om/stage/life[A-Za-z0-9_/]*)', eq, text)
    return text


def translate_body(lines, F, variant, helpers, where):
    out = []
    lines = strip_static_lists(lines, F)
    for line in lines:
        s = line
        s = eval_type_tests(s, variant, F)
        for rx, rep in FRAME_SUBS:
            s = rx.sub(rep, s)
        if 'ctx' in re.sub(r'"[^"]*"', '', s):
            if re.search(r'\bctx\b', s):
                s = re.sub(r'\bctx\b', 'F', s)
                hand(f'{where}: other ctx use, passed as F: {line.strip()}')
        for h in helpers:
            s = re.sub(r'(?<![\w.])' + h + r'\(\s*self\s*,\s*', f'life_{F.key}_{h}(', s)
            s = re.sub(r'(?<![\w.])' + h + r'\(\s*self\s*\)', f'life_{F.key}_{h}()', s)
        s = re.sub(r'(?<![\w.])idle\(\s*self\s*\)', f'!life_{F.key}_due()', s)
        s = re.sub(r'(?<![\w.])perform\(\s*self\s*,\s*ctx\s*\)', f'life_{F.key}(F)', s)
        s = re.sub(r'\bself\.', 'src.', s)
        s = re.sub(r'(?<![\w."])self\b', 'src', s)
        code = re.sub(r'"[^"]*"', '""', s.split('//')[0])
        if re.search(r'\btype\b', code) and 'typecache' not in code and 'type =' not in code:
            if re.search(r'(?<![\w.])type\b', code):
                hand(f'{where}: `type` left in body: {line.strip()}')
        if re.search(r'/datum/om/stage', code):
            hand(f'{where}: stage path left in body: {line.strip()}')
        if re.search(r'(?<![\w.])src\b', line.split('//')[0]) and not re.search(r'\bself\b', line):
            hand(f'{where}: `src` in a stage body meant the stage: {line.strip()}')
        if re.search(r'\b(name|woken_by|wake_on|order|life_sets|run_if)\b', code) and re.search(r'(?<![\w.])(woken_by|wake_on|life_sets|run_if)\b', code):
            hand(f'{where}: stage var read in body: {line.strip()}')
        out.append(s)
    return out


def strip_static_lists(lines, F):
    """Drops a `var/static/list/value_only = list(<stage paths>)` declaration, recording its members."""
    out = []
    i = 0
    while i < len(lines):
        if re.match(r'^\s*var/static/list/value_only\s*=\s*list\($', lines[i]):
            members = []
            i += 1
            while i < len(lines) and not re.match(r'^\s*\)\s*$', lines[i]):
                members.append(lines[i].strip().rstrip(','))
                i += 1
            VALUE_ONLY[F.root] = set(members)
            i += 1
            continue
        out.append(lines[i])
        i += 1
    return out


def negate_returns(lines, where):
    """idle() -> should_run(): every `return X` becomes `return !(X)`; a bare return (null: not idle) is TRUE."""
    out = []
    for line in lines:
        m = re.match(r'^(\s*)return\b\s*(.*?)\s*(//.*)?$', line)
        if m and not line.strip().startswith('//'):
            ind, expr, com = m.group(1), m.group(2), m.group(3) or ''
            if expr == '':
                expr2 = 'TRUE'
            elif expr == 'TRUE':
                expr2 = 'FALSE'
            elif expr == 'FALSE':
                expr2 = 'TRUE'
            elif re.fullmatch(r'!\s*\(.*\)', expr) and expr.count('(') == 1:
                expr2 = expr[1:].strip()
            elif re.fullmatch(r'![A-Za-z_][\w.]*(\(\))?', expr):
                expr2 = expr[1:]
            elif re.fullmatch(r'!!.*', expr):
                expr2 = '!' + expr[2:]
            else:
                expr2 = f'!({expr})'
            out.append(f'{ind}return {expr2}' + (f' {com}' if com else ''))
            continue
        # a one-line `if(x) return y`
        m = re.match(r'^(\s*if\(.*\)\s*)return\b\s*(.*?)\s*$', line)
        if m and not line.strip().startswith('//'):
            hand(f'{where}: one-line if-return in idle(): {line.strip()}')
        out.append(line)
    return out


def simplify_bools(lines):
    out = []
    for s in lines:
        s = re.sub(r'\bTRUE\s*&&\s*', '', s)
        s = re.sub(r'\s*&&\s*TRUE\b', '', s)
        s = re.sub(r'\bFALSE\s*\|\|\s*', '', s)
        s = re.sub(r'\s*\|\|\s*FALSE\b', '', s)
        s = re.sub(r'!\(FALSE\)', 'TRUE', s)
        s = re.sub(r'!\(TRUE\)', 'FALSE', s)
        m = re.match(r'^(\s*return )!\((.*)\)(\s*//.*)?$', s)
        if m and balanced(m.group(2)):
            s = m.group(1) + de_morgan(m.group(2)) + (m.group(3) or '')
        out.append(s)
    # `if(FALSE)` and its one-line body go; `if(TRUE)` keeps its body, dedented
    res = []
    i = 0
    while i < len(out):
        m = re.match(r'^(\s*)if\((TRUE|FALSE)\)\s*$', out[i])
        if m and i + 1 < len(out) and out[i + 1].startswith(m.group(1) + '\t') and not (i + 2 < len(out) and out[i + 2].startswith(m.group(1) + '\t')):
            if m.group(2) == 'TRUE':
                res.append(m.group(1) + out[i + 1].strip())
            i += 2
            continue
        res.append(out[i])
        i += 1
    return res


def balanced(expr):
    depth = 0
    for ch in expr:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth < 0:
                return False
    return depth == 0


def top_split(expr, op):
    parts, depth, cur, i = [], 0, '', 0
    while i < len(expr):
        ch = expr[i]
        if ch == '"':
            j = expr.index('"', i + 1)
            cur += expr[i:j + 1]
            i = j + 1
            continue
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if depth == 0 and expr.startswith(op, i):
            parts.append(cur.strip())
            cur = ''
            i += len(op)
            continue
        cur += ch
        i += 1
    parts.append(cur.strip())
    return parts


def negate_term(t):
    if t.startswith('(') and t.endswith(')') and balanced(t[1:-1]):
        return '!' + t
    if t.startswith('!') and not t.startswith('!!') and (re.fullmatch(r'![\w.?]+(\(.*\))?', t) or (t[1] == '(' and t.endswith(')') and balanced(t[2:-1]))):
        inner = t[1:]
        if inner.startswith('(') and inner.endswith(')') and balanced(inner[1:-1]) and ' ' not in inner[1:-1]:
            return inner[1:-1]
        return inner
    if re.fullmatch(r'[\w.?\[\]"]+(\(.*\))?', t) and balanced(t):
        return '!' + t
    m = re.fullmatch(r'(.+?)\s*(==|!=|<=|>=|<|>)\s*(.+)', t)
    if m and '&&' not in t and '||' not in t and balanced(m.group(1)) and balanced(m.group(3)):
        flip = {'==': '!=', '!=': '==', '<=': '>', '>=': '<', '<': '>=', '>': '<='}
        return f'{m.group(1)} {flip[m.group(2)]} {m.group(3)}'
    return f'!({t})'


def de_morgan(expr):
    """!(expr) written without the outer negation where that reads better."""
    for op, other in (('&&', ' || '), ('||', ' && ')):
        parts = top_split(expr, op)
        if len(parts) > 1:
            if other == ' && ' and any('||' in p for p in parts):
                return f'!({expr})'
            neg = [negate_term(p) for p in parts]
            if op == '&&' and any(('&&' in n or '||' in n) and not n.startswith('!(') for n in neg):
                neg = [n if not ('||' in n and not n.startswith('(')) else f'({n})' for n in neg]
            return other.join(neg)
    n = negate_term(expr.strip())
    return n


# ---------------------------------------------------------------- emission

def mob_of(variant):
    return eff(variant, 'of')


def proc_params(b, drop_self=True):
    ps = split_params(b.params)
    if drop_self and ps and re.search(r'\bself$', ps[0]):
        ps = ps[1:]
    return ps


def body_lines(b):
    L = file_lines[b.file]
    return L[b.start + 1:b.end]


def doc_lines(b):
    L = file_lines[b.file]
    return L[b.doc_start:b.start]


# Which stage proc name becomes which mob proc name.
def target_name(F, procname):
    if procname == 'perform':
        return F.handler
    if procname == 'idle':
        return F.handler + '_due'
    if procname == 'rewake_delay':
        return F.handler + '_rewake'
    if procname == 'applies':
        return F.handler + '_applies'
    return f'life_{F.key}_{procname}'


def is_noop(b):
    if b is None:
        return True
    body = [l.strip() for l in body_lines(b) if l.strip() and not l.strip().startswith('//')]
    return body in ([], ['return'], ['SHOULD_CALL_PARENT(TRUE)'], ['SHOULD_CALL_PARENT(TRUE)', '..()'])


def root_is_noop(F):
    S = stages[F.root]
    perf = S.procs.get('perform')
    idle = S.procs.get('idle')
    if F.trait:
        return False
    if not is_noop(perf):
        return False
    if idle is None:
        return False
    body = [l.strip() for l in body_lines(idle) if l.strip()]
    if any('type in value_only' in l for l in body):
        return True
    return body == [f'return type == {F.root}']


def owner_proc_defined(F, variant, procname):
    """The nearest stage up the variant chain (variant, its parents, the root) that defines procname, else None."""
    p = variant
    while p.startswith(F.root):
        S = stages.get(p)
        if S and procname in S.procs:
            return p
        if p == F.root:
            break
        p = parent_path(p)
    return None


def variant_parent(F, v):
    """The variant whose mob type is v's nearest ancestor among the family's variants."""
    p = parent_path(v)
    while p.startswith(F.root):
        if p in F.variants:
            return p
        if p == F.root:
            break
        p = parent_path(p)
    return F.root if v != F.root else None


emitted = collections.defaultdict(list)    # file -> list of (anchor_line, text lines) inserted in place of the stage blocks
removed = collections.defaultdict(set)     # file -> set of line indices removed
replacement = {}                           # (file, block start) -> list of lines


def emit_family(F):
    if F.trait:
        return emit_trait(F)
    root_noop = root_is_noop(F)
    helpers = set()
    for v in F.members:
        for pn in stages[v].procs:
            if pn not in ('perform', 'idle', 'rewake_delay', 'applies'):
                helpers.add(pn)
    F.helpers = helpers
    for v in F.members:
        S = stages[v]
        is_variant = v in F.variants
        mob = mob_of(v) if is_variant else mob_of(v)
        defined_mobs = set()
        for pn, b in S.procs.items():
            where = f'{b.file}:{b.start + 1} {v}/{pn}'
            # first definition on the mob chain is proc/, overrides are not
            first = (v == F.root) or owner_proc_defined(F, variant_parent(F, v) or F.root, pn) is None
            if pn not in ('perform', 'idle', 'rewake_delay', 'applies') and v != F.root and owner_proc_defined(F, parent_path(v), pn) is None:
                first = True
            name = target_name(F, pn)
            if pn == 'perform':
                params = ['datum/seq_frame/life/F']
                bl = translate_body(body_lines(b), F, v, helpers, where)
            elif pn == 'idle':
                params = []
                bl = translate_body(body_lines(b), F, v, helpers, where)
                bl = simplify_bools(negate_returns(bl, where))
            else:
                params = proc_params(b)
                bl = translate_body(body_lines(b), F, v, helpers, where)
            if pn == 'perform' and root_noop and v == F.root:
                bl = ['\treturn']
            header = f'{mob}/{"proc/" if first else ""}{name}({", ".join(params)})' + (f' {b.ret}' if b.ret else '')
            doc = [re.sub(r'\bidle\b', 'should_run', d) if pn == 'idle' else d for d in doc_lines(b)]
            replacement[(b.file, b.start)] = (b, doc + [header] + bl)
        # Inherited idle bodies that test the stage type: re-emit for this variant.
        if is_variant and v != F.root and 'idle' not in S.procs:
            src_p = owner_proc_defined(F, v, 'idle')
            if src_p:
                ib = stages[src_p].procs['idle']
                raw = '\n'.join(body_lines(ib))
                if re.search(r'\btype\b', raw):
                    where = f'{v} (inherited idle from {src_p})'
                    bl = translate_body(body_lines(ib), F, v, helpers, where)
                    bl = simplify_bools(negate_returns(bl, where))
                    text = [f'{mob}/{F.handler}_due()'] + bl
                    tb = S.type_block or S.procs.get('perform')
                    if tb is None:
                        hand(f'{v}: no block to anchor an inherited should_run on')
                    else:
                        emitted[(tb.file, tb.start)].append(text)
        if S.type_block:
            b = S.type_block
            if (b.file, b.start) not in replacement:
                replacement[(b.file, b.start)] = (b, [])
            for li, s in S.extra_var_decls:
                hand(f'{b.file}:{li + 1}: stage instance var: {s}')
    # A root that has no proc for a handler the variants override: declare it (empty) on the root mob type.
    for pn in ('perform', 'idle', 'rewake_delay', 'applies'):
        if any(pn in stages[v].procs for v in F.members) and pn not in stages[F.root].procs:
            name = target_name(F, pn)
            body = {'perform': ['\treturn'], 'idle': ['\treturn TRUE'], 'rewake_delay': ['\treturn 0'], 'applies': ['\treturn TRUE']}[pn]
            params = 'datum/seq_frame/life/F' if pn == 'perform' else ''
            text = [f'{mob_of(F.root)}/proc/{name}({params})'] + body
            tb = stages[F.root].type_block
            if tb is None:
                hand(f'{F.root}: no type block to anchor {name}')
            else:
                emitted[(tb.file, tb.start)].append(text)


def emit_trait(F):
    """A trait stage: its perform (or state_type's life_tick) becomes a step its contributor declares."""
    S = stages[F.root]
    st = S.vars.get('state_type')
    F.contributor = st
    F.helpers = set()
    b = S.procs.get('perform')
    if b:
        where = f'{b.file}:{b.start + 1} {F.root}/perform'
        bl = translate_body(body_lines(b), F, F.root, set(), where)
        F.perform_text = bl
        replacement[(b.file, b.start)] = (b, [])
    for pn in S.procs:
        if pn != 'perform':
            pb = S.procs[pn]
            hand(f'{pb.file}:{pb.start + 1}: trait stage proc {pn}')
            replacement[(pb.file, pb.start)] = (pb, [])
    if S.type_block:
        replacement[(S.type_block.file, S.type_block.start)] = (S.type_block, [])


def rewrite_files():
    for f, L in file_lines.items():
        out = []
        blocks = {b.start: b for b in file_blocks[f]}
        skip_to = -1
        i = 0
        # emitted extras anchored at a block get appended after that block's replacement
        while i < len(L):
            b = blocks.get(i)
            if b is not None and (f, b.start) in replacement:
                _, text = replacement[(f, b.start)]
                # drop the doc comment lines already emitted above the header (a proc re-emits them; a removed type
                # block keeps them, so they stay above the step proc that follows)
                while b.kind == 'proc' and out and b.doc_start < i and out[-1] in L[b.doc_start:b.start] and len(out) >= (i - b.doc_start):
                    for _ in range(i - b.doc_start):
                        out.pop()
                    break
                extra = emitted.get((f, b.start), [])
                if text:
                    out.extend(text)
                for t in extra:
                    if text:
                        out.append('')
                    out.extend(t)
                if not text and not extra:
                    # removed block: a kept doc comment attaches to the next block; else drop one blank line
                    i = b.end
                    if b.doc_start < b.start:
                        while i < len(L) and L[i].strip() == '':
                            i += 1
                    elif i < len(L) and L[i].strip() == '' and out and out[-1].strip() == '':
                        i += 1
                    continue
                i = b.end
                continue
            out.append(L[i])
            i += 1
        new = '\n'.join(out)
        if WRITE:
            open(f, 'w', encoding='utf-8', newline='\n').write(new)


# ---------------------------------------------------------------- declarations and order

def load_mob_life_sets():
    out = subprocess.run(['git', 'grep', '-n', '-E', r'^\s+life_set = ', '--', '*.dm'], capture_output=True, text=True).stdout
    sets = {'/mob/living': 'LIFE_SET_LIVING'}
    for line in out.split('\n'):
        if not line:
            continue
        f, ln, text = line.split(':', 2)
        L = open(f, encoding='utf-8').read().split('\n')
        k = int(ln) - 1
        while k >= 0 and (not L[k] or L[k][0].isspace()):
            k -= 1
        hdr = L[k].strip()
        if hdr.startswith('/mob'):
            sets[hdr.split('//')[0].strip()] = text.split('=', 1)[1].strip()
    return sets


SETBITS = {'LIFE_SET_LIVING': 1, 'LIFE_SET_ROBOT': 2, 'LIFE_SET_AI': 4, 'LIFE_SET_PAI': 8, 'LIFE_SET_DECOY': 16, 'LIFE_SET_DELIST': 32}


def setmask(expr):
    m = 0
    for tok in re.findall(r'LIFE_SET_[A-Z]+', expr):
        m |= SETBITS[tok]
    return m


def is_sub(t, base):
    return t == base or t.startswith(base + '/')


def resolve(F, t):
    best = None
    for v in F.variants:
        o = mob_of(v)
        if is_sub(t, o) and (best is None or len(mob_of(best)) < len(o)):
            best = v
    return best


def plans_and_edges(mob_sets):
    mob_types = set(mob_sets)
    for F in families.values():
        for v in F.variants:
            mob_types.add(mob_of(v))
    mob_types = sorted(mob_types)

    def life_set_of(t):
        best = None
        for k, val in mob_sets.items():
            if is_sub(t, k) and (best is None or len(k) > len(best)):
                best = k
        return setmask(mob_sets[best]) if best else 1

    def pos_key(F, t=None):
        v = resolve(F, t) if (t and not F.trait) else F.root
        return (eval_order(eff(v, 'order')), F.root)

    entity_fams = [F for F in families.values() if not F.trait]
    trait_fams = [F for F in families.values() if F.trait]
    plans = []
    for t in mob_types:
        ls = life_set_of(t)
        chosen = []
        for F in entity_fams:
            v = resolve(F, t)
            if v is None:
                continue
            if not (setmask(eff(v, 'life_sets')) & ls):
                continue
            chosen.append(F)
        extra_sets = [[]] + [[X] for X in trait_fams] + [trait_fams]
        if not (ls & 1):
            extra_sets = [[]]
        for ex in extra_sets:
            plan = sorted(chosen + ex, key=lambda X: pos_key(X, t))
            plans.append([X.handler if not X.trait else trait_key(X) for X in plan])
    band_of = {}
    for F in families.values():
        band_of[F.handler if not F.trait else trait_key(F)] = band(eval_order(eff(F.root, 'order')))
    return plans, band_of


def trait_key(F):
    return 'life_' + F.key


def sort_lt(a, b):
    return a < b


def derive_edges(plans, band_of, anchors):
    nodes = []
    prec = {}
    presence = {}
    for p, plan in enumerate(plans):
        for i, k in enumerate(plan):
            if k not in prec:
                nodes.append(k)
                prec[k] = []
                presence[k] = set()
            if i > 0 and plan[i - 1] not in prec[k]:
                prec[k].append(plan[i - 1])
            presence[k].add(p)
    # topological order (stable by first appearance)
    order = []
    indeg = {k: 0 for k in nodes}
    succ = {k: [] for k in nodes}
    for k in nodes:
        for d in prec[k]:
            indeg[k] += 1
            succ[d].append(k)
    ready = [k for k in nodes if indeg[k] == 0]
    while ready:
        k = ready.pop(0)
        order.append(k)
        for s in succ[k]:
            indeg[s] -= 1
            if indeg[s] == 0:
                ready.append(s)
    if len(order) != len(nodes):
        raise SystemExit('plans disagree on an order')
    edges = {}
    for i, r in enumerate(order):
        bnd = band_of[r]
        e = [bnd]
        mine = presence[r]
        cover = -1
        inversions = []
        for j in range(i):
            d = order[j]
            if band_of[d] != bnd:
                continue
            theirs = presence[d]
            if not (mine - theirs):
                cover = j
            if (mine & theirs) and d > r:
                inversions.append(j)
        if inversions:
            if cover >= 0 and cover >= inversions[0]:
                e.append(order[cover])
            for j in inversions:
                if j > cover:
                    e.append(order[j])
        edges[r] = e
    return edges, order


def check_edges(plans, edges, anchors):
    bad = 0
    for plan in plans:
        nodes = anchors + plan
        deps = {k: [d for d in edges.get(k, []) if d in nodes] for k in nodes}
        for i, a in enumerate(anchors):
            deps[a] = [anchors[i - 1]] if i else []
        indeg = {k: len(deps[k]) for k in nodes}
        succ = {k: [] for k in nodes}
        for k in nodes:
            for d in deps[k]:
                succ[d].append(k)
        ready = sorted([k for k in nodes if indeg[k] == 0 and k not in anchors])
        ready_a = sorted([k for k in nodes if indeg[k] == 0 and k in anchors])
        got = []
        while ready or ready_a:
            k = ready.pop(0) if ready else ready_a.pop(0)
            got.append(k)
            for s in succ[k]:
                indeg[s] -= 1
                if indeg[s] == 0:
                    (ready_a if s in anchors else ready).append(s)
                    ready.sort()
                    ready_a.sort()
        got = [g for g in got if g not in anchors]
        if got != plan:
            bad += 1
            print('EDGE MISMATCH', plan, got)
    return bad == 0


def when_of(v):
    expr = eff(v, 'run_if')
    if expr not in RUN_IF:
        hand(f'{v}: run_if {expr} has no `when` mapping')
        return []
    return RUN_IF[expr]


FIELD_CHANNEL = {}


def load_fields():
    out = subprocess.run(['git', 'grep', '-h', '-E', r'^OM_FIELD(_TYPED)?\(', '--', '*.dm'], capture_output=True, text=True).stdout
    for line in out.split('\n'):
        m = re.match(r'OM_FIELD\(([^,]+),\s*(\w+),\s*[^,]+,\s*(\w+)\)', line)
        if m:
            FIELD_CHANNEL[m.group(2)] = m.group(3)
        m = re.match(r'OM_FIELD_TYPED\(([^,]+),\s*[^,]+,\s*(\w+),\s*[^,]+,\s*(\w+)\)', line)
        if m:
            FIELD_CHANNEL[m.group(2)] = m.group(3)


def reads_of(v):
    chans = eff(v, 'wake_on').strip()
    parts = [] if chans in ('', '0') else [c.strip() for c in chans.split('|')]
    reads = eff(v, 'reads')
    for name in re.findall(r'"(\w+)"', reads):
        ch = FIELD_CHANNEL.get(name)
        if ch is None:
            hand(f'{v}: reads "{name}" is not an OM_FIELD')
        elif ch not in parts:
            parts.append(ch)
    return parts


def has_proc_in_chain(F, v, pn):
    return owner_proc_defined(F, v, pn) is not None


def decl_for(F, v, edges):
    args = [f'PROC_REF({F.handler})']
    after = edges[F.handler]
    args.append('after = ' + (after[0] if len(after) == 1 else 'list(' + ', '.join(a if a.startswith('LIFE_') else f'"{a}"' for a in after) + ')'))
    w = when_of(v)
    if w:
        args.append('when = ' + (f'"{w[0]}"' if len(w) == 1 else 'list(' + ', '.join(f'"{x}"' for x in w) + ')'))
    r = reads_of(v)
    if r:
        args.append('reads = ' + ' | '.join(r))
    if any('idle' in stages[x].procs for x in F.members):
        args.append(f'should_run = PROC_REF({F.handler}_due)')
    if any('rewake_delay' in stages[x].procs for x in F.members):
        args.append(f'rewake = PROC_REF({F.handler}_rewake)')
    wb = eff(v, 'woken_by')
    if wb:
        args.append(f'woken_by = {wb}')
    return 'seq_step(' + ', '.join(args) + ')'


def declarations(edges, mob_sets):
    per_mob = collections.defaultdict(list)
    for F in sorted(families.values(), key=lambda F: (eval_order(eff(F.root, 'order')), F.root)):
        if F.trait:
            continue
        noop = root_is_noop(F)
        decl_variants = []
        if not noop:
            decl_variants.append(F.root)
        for v in F.variants:
            if v == F.root:
                continue
            par = variant_parent(F, v)
            differs = any(eff(v, x) != eff(par, x) for x in ('run_if', 'wake_on', 'life_sets', 'reads', 'woken_by'))
            if (noop and par == F.root) or differs:
                decl_variants.append(v)
        for v in decl_variants:
            stmt = decl_for(F, v, edges)
            sets = eff(v, 'life_sets')
            conds = []
            conds.append(f'life_set & ({sets})' if '|' in sets else f'life_set & {sets}')
            if any('applies' in stages[x].procs for x in F.members):
                conds.append(f'{F.handler}_applies()')
            per_mob[mob_of(v)].append((conds, stmt, F.key))
    return per_mob


def write_steps_file(per_mob, edges, F_traits):
    out = ['// Life steps (doc/rewrite/life_sequences.md, doc/rewrite/om_retirement.md L1).',
           '//',
           '// Each mob type declares the Life steps it runs. A step is a proc on the mob type (life_<step>(F)), overridden by',
           '// subtypes; `after =` edges reproduce the old stage order (derived by tools/dx/codemods/life_stage_steps.py; the',
           '// solver breaks ties by key). `when =` names the frame conditions (/datum/sequence/life/conditions()), `reads =` the',
           '// change channels that wake a sleeping step, `should_run =` says it has work, `rewake =` wakes it anyway after a',
           '// delay. A later declaration of the same step on a subtype replaces the parent\'s. A step runs only for the Life set',
           '// (life_set) it serves: preview dummies and delisted mobs keep none of the living steps.',
           '']
    order_mobs = sorted(per_mob, key=lambda t: (t.count('/'), t))
    for t in order_mobs:
        out.append(f'{t}/life_steps()')
        out.append('	. = ..()')
        groups = collections.OrderedDict()
        for conds, stmt, key in per_mob[t]:
            groups.setdefault(conds[0], []).append((conds[1:], stmt))
        for setcond, items in groups.items():
            out.append(f'	if({setcond})')
            for rest, stmt in items:
                if rest:
                    out.append(f'		if({" && ".join(rest)})')
                    out.append(f'			. += {stmt}')
                else:
                    out.append(f'		. += {stmt}')
        out.append('')
    if WRITE:
        open(STEPS_FILE, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
    return out


def trait_decls(edges):
    lines = {}
    for F in families.values():
        if not F.trait:
            continue
        S = stages[F.root]
        k = trait_key(F)
        after = edges[k]
        a = after[0] if len(after) == 1 else 'list(' + ', '.join(x if x.startswith('LIFE_') else f'"{x}"' for x in after) + ')'
        args = [f'PROC_REF({k})', f'after = {a}', f'key = "{k}"']
        w = when_of(F.root)
        if w:
            args.append('when = ' + (f'"{w[0]}"' if len(w) == 1 else 'list(' + ', '.join(f'"{x}"' for x in w) + ')'))
        r = reads_of(F.root)
        if r:
            args.append('reads = ' + ' | '.join(r))
        wb = eff(F.root, 'woken_by')
        if wb:
            args.append(f'woken_by = {wb}')
        lines[F.root] = 'seq_step(' + ', '.join(args) + ')'
    return lines


def drop_life_stage_line(state_type, root):
    out = subprocess.run(['git', 'grep', '-n', '-F', f'life_stage = {root}', '--', '*.dm'], capture_output=True, text=True).stdout
    for line in out.split('\n'):
        if not line:
            continue
        f, ln, _ = line.split(':', 2)
        if f not in file_lines:
            file_lines[f] = open(f, encoding='utf-8').read().split('\n')
            file_blocks[f] = split_blocks(f, file_lines[f])
        DROP_LINES[f].add(int(ln) - 1)


DROP_LINES = collections.defaultdict(set)


def main():
    parse()
    build_families()
    load_fields()
    mob_sets = load_mob_life_sets()
    for F in families.values():
        emit_family(F)
    plans, band_of = plans_and_edges(mob_sets)
    anchors = ['LIFE_INPUT', 'LIFE_BODY', 'LIFE_MIND', 'LIFE_OUTPUT', 'LIFE_TAIL']
    edges, order = derive_edges(plans, band_of, anchors)
    ok = check_edges(plans, edges, anchors)
    per_mob = declarations(edges, mob_sets)
    steps = write_steps_file(per_mob, edges, None)
    td = trait_decls(edges)
    print(f'families {len(families)}, plans {len(plans)}, edges ok {ok}')
    print('order:', ' '.join(order))
    print('\n'.join(steps))
    print('--- trait declarations')
    for root, line in sorted(td.items()):
        F = families[root]
        print(f'{root}  contributor={getattr(F, "contributor", None)}\n\t{line}')
        if getattr(F, 'perform_text', None):
            print('\tperform body:\n' + '\n'.join('\t\t' + l for l in F.perform_text))
    for root, line in td.items():
        F = families[root]
        S = stages[root]
        st = S.vars.get('state_type')
        if st and not getattr(F, 'perform_text', None):
            tb = S.type_block
            text = [f'/// One Life step per cycle while attached (doc/rewrite/om_retirement.md L1).',
                    f'{st}/life_steps()',
                    f'	return list({line.replace("PROC_REF(" + trait_key(F) + ")", "PROC_REF(life_tick)")})']
            replacement[(tb.file, tb.start)] = (tb, text)
            drop_life_stage_line(st, root)
        else:
            hand(f'{root}: trait stage with its own perform: convert its contributor by hand')
    rewrite_files()
    print('--- HAND', len(HAND))
    for h in HAND:
        print('HAND', h)


if __name__ == '__main__':
    main()
