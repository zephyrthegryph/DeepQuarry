"""look_sweep.py track: the vars a draw() reads become TRACKED (doc/rewrite/codemod_rules.md, "The draw sweep").

A draw is redrawn by the refresh engine when something it reads publishes a change. A plain var publishes nothing, so its
writers had to call update_icon() (now changed()). For each var a draw() reads that nothing publishes (look_convert.draw_coverage),
when every write to it can be rewritten, the var becomes TRACKED(U, var) on its one declaring type U and every write in the tree
becomes the generated setter: `v = x` -> `set_v(x)`, `v += x` -> `set_v(v + (x))`, `v++` -> `set_v(v + 1)`, `X.v = x` ->
`X.set_v(x)`, also as the tail of a one-line `if(c) ...` / `else ...`. Writes in unit tests, benchmarks and type defaults stay.

Left as they are, by code: builtin (an atom builtin), owner_shape (not one declaring type on the readers' chains), shared_name
(declared on unrelated types too, so `X.v = ` cannot be attributed), already (tracked), setter_exists (a hand-written set_<var>
in the chain), decl_shape (static/global, or no declaration line), macro_write (written in a #define), write_place (a write outside
a proc), write_form (a write inside a larger expression or two on a line), owned_writes (a write in a folder another session owns,
without --owned-ok).
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import collections
import re

from dmlib import strip_code  # noqa: E402
from look_convert import ATOM_BUILTINS, Index, code_and_comment, draw_coverage

TRACK_SKIP = ATOM_BUILTINS | {"stat", "reagents", "contents", "loc", "src", "usr"}
WRITE_OPS = r"(?:=(?!=)|\+=|-=|\|=|&=|\*=|/=)"
OWNED_PREFIXES = ("code/datums/om/", "code/datums/entity_state/", "code/game/objects/", "code/game/turfs/", "code/modules/body/organs/", "code/modules/mob/living/life/")
TEST_PREFIXES = ("code/modules/unit_tests/", "code/modules/benchmarks/", "code/modules/tgs/")
ATOMS = ("/atom", "/obj", "/mob", "/turf", "/area")


def candidates(ix):
    """var -> the draw() types that read it while nothing publishes it."""
    cands = collections.defaultdict(set)
    for t in sorted(ix.draws):
        if not t.startswith(ATOMS):
            continue
        _has, _covered, untracked = draw_coverage(ix, t)
        for u in untracked:
            name = u.split(" ")[0]
            if name.endswith(".*") or name.endswith("()"):
                continue
            cands[name].add(t)
    return cands


def find_decl(ix, U, var):
    """(rel, index of the line after which TRACKED goes) for U's declaration of var, or None."""
    head = re.compile(r"^" + re.escape(U) + r"/var/(?:(?:tmp|static|global|const|final)/)*(?:[\w/]+/)?" + re.escape(var) + r"\b")
    inner = re.compile(r"^\tvar/(?:(?:tmp|static|global|const|final)/)*(?:[\w/]+/)?" + re.escape(var) + r"\b")
    for rel, f in ix.files.items():
        L = f.lines
        block = None
        for i, l in enumerate(L):
            if l and l[0] not in " \t":
                bm = re.match(r"^(/[\w/]+)\s*(//.*)?$", l)
                block = bm.group(1) if bm else None
                if head.match(l):
                    return rel, i, l
                continue
            if block == U and inner.match(l):
                j = i + 1
                while j < len(L) and (not L[j].strip() or L[j][0] in " \t" or L[j].startswith("//")):
                    j += 1  # a column-0 comment inside the block does not end it
                while j - 1 > i and (not L[j - 1].strip() or L[j - 1].startswith("//")):
                    j -= 1
                return rel, j - 1, l
    return None


def shadowed(var, params, body_before):
    return bool(re.search(r"\bvar/(?:[\w/]+/)?" + re.escape(var) + r"\b", body_before) or re.search(r"(?<![\w])" + re.escape(var) + r"\b", params))


_write_index = {}


def write_index(ix):
    """var name -> the files with a line that may write it (one pass over the tree)."""
    if not _write_index:
        any_write = re.compile(r"([A-Za-z_]\w*)\s*(?:" + WRITE_OPS + r"|\+\+|--)")
        for rel, f in ix.files.items():
            for l in f.lines:
                if "=" not in l and "++" not in l and "--" not in l:
                    continue
                for m in any_write.finditer(strip_code(l)):
                    _write_index.setdefault(m.group(1), set()).add(rel)
    return _write_index


def plan(ix, var, readers, owned_ok):
    if var in TRACK_SKIP:
        return "builtin"
    owners = [u for u, vs in ix.vars.items() if var in vs and u.startswith(ATOMS)]
    mine = [u for u in owners if any(u in ix.chain(r) for r in readers)]
    if len(mine) != 1:
        return "owner_shape"
    U = mine[0]
    if any(not ix.related(o, U) for o in owners if o != U):
        return "shared_name"
    if any(ix.tracked_on(r, var) for r in readers):
        return "already"
    for (t, name) in ix.proc_defs:
        if name == "set_" + var and ix.related(t, U):
            return "setter_exists"
    decl = find_decl(ix, U, var)
    if not decl or re.search(r"/(static|global|const)/", strip_code(decl[2])):
        return "decl_shape"
    writes = []
    pat = re.compile(r"(?<![\w])((?:[A-Za-z_]\w*(?:\(\))?\s*\??\.\s*)*)" + re.escape(var) + r"\s*(" + WRITE_OPS + r"|\+\+|--)")
    for rel in sorted(write_index(ix).get(var, ())):
        f = ix.files[rel]
        if rel.startswith(TEST_PREFIXES):
            continue
        L = f.lines
        ptype = pname = None
        params = ""
        start = 0
        for i, l in enumerate(L):
            if l and l[0] not in " \t":
                hm = re.match(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\((.*)$", l)
                if hm and "=" not in strip_code(l).split("(")[0]:
                    ptype, pname, params, start = hm.group(1), hm.group(2), strip_code(hm.group(3)), i
                else:
                    ptype = pname = None
                    params = ""
                if l.startswith("#define") and var in l and pat.search(strip_code(l)):
                    return "macro_write"
                continue
            if var not in l:
                continue
            code = strip_code(l)
            ms = list(pat.finditer(code))
            if not ms:
                continue
            m = ms[0]
            recv = m.group(1).replace(" ", "")
            bare = recv in ("", "src.")
            if ptype is None:
                if bare and re.match(r"^\t" + re.escape(var) + r"\s*=", code):
                    continue  # a type default in a block
                if bare:
                    continue  # a write in a non-proc context we cannot place: a block default deeper in, or a list literal
                return "write_place:%s:%d" % (rel, i + 1)
            if pname == "set_" + var:
                continue
            if bare:
                if ptype.startswith("/proc") or U not in ix.chain(ptype):
                    continue  # a global proc or another type: its own local, parameter or var of that name
                if shadowed(var, params, "\n".join(strip_code(x) for x in L[start:i])):
                    continue
            if len(ms) > 1:
                return "write_form:%s:%d" % (rel, i + 1)
            stmt = code.strip()
            prefix = ""
            tail = stmt
            ctl = re.match(r"^((?:else\s+)?if\s*\((?:[^()]|\([^()]*\))*\)|else)\s+(.*)$", stmt)
            if ctl:
                prefix, tail = ctl.group(1) + " ", ctl.group(2)
            am = re.match(r"^((?:[A-Za-z_]\w*(?:\(\))?\s*\??\.\s*)*)" + re.escape(var) + r"\s*(" + WRITE_OPS + r")\s*(.*)$", tail)
            im = re.match(r"^((?:[A-Za-z_]\w*(?:\(\))?\s*\??\.\s*)*)" + re.escape(var) + r"\s*(\+\+|--)$", tail)
            if not am and not im:
                return "write_form:%s:%d" % (rel, i + 1)
            recv = (am or im).group(1).replace(" ", "")
            if recv == "src.":
                recv = ""
            cur = recv + var
            raw = l.strip()
            raw_tail = raw[len(prefix):] if prefix and raw.startswith(prefix.rstrip()) else raw
            if prefix and not raw.startswith(prefix.rstrip()):
                return "write_form:%s:%d" % (rel, i + 1)
            kept, comment = code_and_comment(raw_tail)
            if am:
                op = am.group(2)
                rhs = kept.split(op, 1)[1].strip()
                if op == "=":
                    new = "%sset_%s(%s)" % (recv, var, rhs)
                else:
                    new = "%sset_%s(%s %s (%s))" % (recv, var, cur, op[0], rhs)
            else:
                new = "%sset_%s(%s %s 1)" % (recv, var, cur, "+" if im.group(2) == "++" else "-")
            ind = re.match(r"^[ \t]*", l).group(0)
            writes.append((rel, i, ind + prefix + new + comment))
    if not writes:
        return "no_writes"  # nothing writes it in a proc: a constant of the type (its untracked verdict came from a set_<var>() call)
    if not owned_ok and any(w[0].startswith(OWNED_PREFIXES) for w in writes):
        return "owned_writes"
    return {"owner": U, "macro": "TRACKED(%s, %s)" % (U, var), "after": (decl[0], decl[1]), "writes": writes}


def run(args, root, rels):
    ix = Index(root, rels)
    cands = candidates(ix)
    plans = {}
    codes = collections.Counter()
    why = {}
    only = set(args.vars or [])
    for var in sorted(cands):
        if only and var not in only:
            continue
        p = plan(ix, var, cands[var], args.owned_ok)
        if isinstance(p, str):
            codes[p.split(":")[0]] += 1
            why[var] = p
            continue
        plans[var] = p
    print("look_sweep track: %d vars %s, %d left %s" % (len(plans), "tracked" if args.apply else "trackable", len(why), dict(codes)))
    if args.sites:
        for var, p in sorted(plans.items()):
            print("    track %s on %s (%d writes)" % (var, p["owner"], len(p["writes"])))
        for var, w in sorted(why.items()):
            print("    left  %s: %s" % (var, w))
    if not args.apply:
        return
    edits = collections.defaultdict(dict)
    adds = collections.defaultdict(list)
    for var, p in plans.items():
        for rel, i, new in p["writes"]:
            edits[rel][i] = new
        adds[p["after"][0]].append((p["after"][1], p["macro"]))
    for rel in set(edits) | set(adds):
        f = ix.files[rel]
        for i, new in edits.get(rel, {}).items():
            f.lines[i] = new
        for i, macro in sorted(adds.get(rel, []), reverse=True):
            f.lines.insert(i + 1, macro)
        f.dirty = True
        f.save()
