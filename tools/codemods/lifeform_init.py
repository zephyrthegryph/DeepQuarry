#!/usr/bin/env python3
r"""Initialize() overrides -> the lifecycle forms (doc/rewrite/final_api.html section 6 "Lifecycle forms"; code/engine/lifeforms/).

    python tools/codemods/lifeform_init.py [--apply] [--class C ...] [--sites] [--others] [--paths prefix ...] [--residue out.json]

An override (kept by an ALLOW(init/...) or not) whose every statement past its one `..()` call is something a form declares is deleted, and
the entries go into the type's CAPABILITIES block (made when it has none):

  rolls      `v = <expression with rand/pick/prob/pickweight>`, `if(prob(N)) v = X [else v = Y]`, `randpixel_xy()`, the pixel_x/pixel_y pair:
             rolls(nameof(v), range_of(a, b) | pick_one(list(...)) | chance(N)), rolls(ROLL_PIXEL, PIXEL_JITTER(n)), or for anything else
             rolls(nameof(v), PROC_REF(roll_v)) with a generated `roll_v(datum/roller/R)` drawing through R (R.number, R.choose, R.chance,
             R.weighted). Expressions that call anything but the random procs and a few pure helpers are left alone.
  params     `Initialize(mapload, a, b)` whose statements store each argument: `v = a`, `src.v = a`, `rel_set(src, nameof(v), a)`,
             `if(!isnull(a)) v = a`, `if(a) v = a`, `set_dir(a)` / `if(a) set_dir(a)`: param(nameof(v), pos = N) for the N-th argument.
  contains   `new /T(src)` (statements alone): initial_contents(/T), repeated ones with count =.
  knows      `add_language(LANGUAGE_X)`: knows(LANGUAGE_X).
  parts      `default_apply_parts()` in a machine whose ancestors below /obj/machinery override no Initialize(): default_parts()
             (code/library/machine/parts.dm).
  rotatable  `make_rotatable()` / `make_rotatable(only_flip = TRUE)` on a type whose chain overrides none of the rotation hooks
             (handle_rotation_verbs, ghosts_can_use_rotate_verbs, can_use_rotate_verbs_while_anchored): rotatable() (library).
  lifetime   `expire(X)` of a constant delay: `T/lifecycle_lifetime = X` (the movable's init arms it).
  no-op      `update_icon()` on a type whose chain has no legacy appearance declaration: dropped (look_sweep dead).

The classes combine: an override of rolls and contains statements converts. Idempotent. Run `analyze gen` afterwards.
"""
import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmlib import File, block_end, capabilities_index, dm_files, procs_in, statements, strip_code, split_args  # noqa: E402

PARENT = re.compile(r"^(\.\s*=\s*\.\.\((.*)\)|return\s+\.\.\((.*)\)|\.\.\((.*)\))$")
RETURN_DOT = re.compile(r"^return\s*\.?$")
ASSIGN = re.compile(r"^(?:src\.)?([a-z_]\w*)\s*=\s*(?!=)(.+)$")
RANDOM = re.compile(r"(?<![\w.])(rand|pick|prob|pickweight)\s*\(")
SAFE_CALLS = {"rand", "pick", "prob", "pickweight", "round", "clamp", "max", "min", "initial", "num2text", "text", "list", "length", "uppertext",
              "lowertext", "capitalize", "floor", "ceil", "abs", "rgb", "isnull"}
COND = re.compile(r"^(if|else if)\s*\((.*)\)\s*(.*)$")
NEW_SRC = re.compile(r"^new\s*(/[\w/]+)\s*\(\s*src\s*\)$")
ADD_LANG = re.compile(r"^add_language\(\s*(LANGUAGE_\w+)\s*\)$")
SET_DIR = re.compile(r"^set_dir\(\s*(\w+)\s*\)$")
REL_SET = re.compile(r"^rel_set\(\s*src\s*,\s*nameof\((\w+)\)\s*,\s*(\w+)\s*\)$")
SKIP_VARS = {"loc", "contents", "vars", "type", "parent_type", "tag", "verbs", "x", "y", "z", "density", "opacity"}


def cond_split(code):
    """("if" | "else if", condition, tail) of an if statement, the condition's brackets balanced; None otherwise."""
    m = re.match(r"^(if|else if)\s*\(", code)
    if not m:
        return None
    depth, k = 1, m.end()
    while k < len(code) and depth:
        depth += {"(": 1, ")": -1}.get(code[k], 0)
        k += 1
    if depth:
        return None
    return m.group(1), code[m.end():k - 1], code[k:].strip()


def calls_in(expr):
    return re.findall(r"(?<![\w.])([A-Za-z_]\w*)\s*\(", expr)


def safe_expr(expr):
    """The expression only calls the random procs and pure helpers, and reads no world state (string text is not code)."""
    expr = strip_code(expr)
    if re.search(r"\b(loc|get_turf|get_area|GLOB\.\w+\s*\[|usr|world)\b", expr):
        return False
    return all(c in SAFE_CALLS for c in calls_in(expr))


def to_roller(expr):
    """The expression with the world RNG's procs drawn from R instead."""
    out = []
    i = 0
    while i < len(expr):
        m = re.compile(r"(?<![\w.])(rand|pick|prob|pickweight)\s*\(").search(expr, i)
        if not m:
            out.append(expr[i:])
            break
        out.append(expr[i:m.start()])
        o = expr.index("(", m.start())
        depth, j = 0, o
        while j < len(expr):
            if expr[j] == "(":
                depth += 1
            elif expr[j] == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        inner = to_roller(expr[o + 1:j])
        args = [a.strip() for a in split_args(inner) if a.strip()]
        name = m.group(1)
        if name == "rand":
            out.append("R.unit()" if not args else ("R.number(%s)" % ", ".join(args) if len(args) == 2 else "R.number(0, %s)" % args[0]))
        elif name == "prob":
            out.append("R.chance(%s)" % inner)
        elif name == "pickweight":
            out.append("R.weighted(%s)" % inner)
        else:
            out.append("R.choose(%s)" % (args[0] if len(args) == 1 else "list(%s)" % ", ".join(args)))
        i = j + 1
    return "".join(out)


NUM = r"-?\d+(?:\.\d+)?"


def generator(expr):
    """A named generator for a plain random expression, or None (the caller writes a roll proc)."""
    e = expr.strip()
    m = re.fullmatch(r"rand\(\s*(%s|[A-Z_]\w*)\s*,\s*(%s|[A-Z_]\w*)\s*\)" % (NUM, NUM), e)
    if m:
        return "range_of(%s, %s)" % (m.group(1), m.group(2))
    m = re.fullmatch(r"prob\(\s*(%s|[A-Z_]\w*)\s*\)" % NUM, e)
    if m:
        return "chance(%s)" % m.group(1)
    m = re.fullmatch(r"pick\((.*)\)", e)
    if m and calls_in(m.group(1)) in ([], ["list"]):
        args = [a.strip() for a in split_args(m.group(1)) if a.strip()]
        if len(args) >= 2 and all(re.fullmatch(r'"[^"\[\]]*"|%s|[A-Z_]\w*|/[\w/]+' % NUM, a) for a in args):
            return "pick_one(list(%s))" % ", ".join(args)
        if len(args) == 1 and args[0].startswith("list(") and RANDOM.search(args[0]) is None:
            return "pick_one(%s)" % args[0]
    m = re.fullmatch(r"pickweight\((list\(.*\))\)", e)
    if m and RANDOM.search(m.group(1)) is None:
        return "pick_weighted(%s)" % m.group(1)
    return None


class Plan:
    def __init__(self, proc):
        self.proc = proc
        self.entries = []
        self.procs = []  # (name, body lines)
        self.defaults = []  # (var, value): a type default written beside the type
        self.dropped = 0  # statements that did nothing (a no-op update_icon())
        self.why = None


# Set by main(): the types that override Initialize(), the types that override a rotation hook, and the appearance chains (look_sweep).
INIT_TYPES = set()
ROT_HOOK_TYPES = set()
CHAINS = None


def ancestors_of(t):
    out = []
    while t.count("/") > 1:
        t = t.rsplit("/", 1)[0]
        out.append(t)
    return out


def related_any(t, types):
    return any(u == t or u.startswith(t + "/") or t.startswith(u + "/") for u in types)


def plan_override(proc):
    """A Plan when every statement converts, else (None, reason)."""
    f = proc.file
    params = proc.params()
    if params is None:
        return None, "header_spans_lines"
    stmts = statements(f, proc.start + 1, proc.end)
    if not stmts or any(s.indent < 1 for s in stmts):
        return None, "odd_indent"
    if any(f.lines[k].lstrip().startswith("#") for k in range(proc.start + 1, proc.end)):
        return None, "preprocessor"
    top = [s for s in stmts if s.indent == 1]
    parent = [s for s in top if PARENT.match(s.code)]
    if len(parent) != 1:
        return None, "parent_call_count"
    pm = PARENT.match(parent[0].code)
    pargs = next(g for g in pm.groups()[1:] if g is not None).strip()
    extra = [p for p in params[1:] if p != "..."]
    if pargs not in ("", "mapload") and pargs.replace(" ", "") != ",".join(["mapload"] + extra):
        return None, "parent_args"
    rest = [s for s in stmts if s is not parent[0] and not RETURN_DOT.match(s.code)]
    if not rest:
        return None, "redundant"
    # Work on the raw text (string contents kept); strip_code() blanks strings but keeps columns, so the raw statement is the same span.
    for s in rest:
        if s.first != s.last:
            return None, "multiline"
        s.code = f.lines[s.first].lstrip()[: len(s.code)]
    plan = Plan(proc)
    whole = block_roll(f, proc, rest)
    if whole:
        var, body = whole
        plan.procs.append(("roll_%s" % var, body))
        plan.entries.append("rolls(nameof(%s), PROC_REF(roll_%s))" % (var, var))
        if [p for p in params[1:] if p != "..."]:
            return None, "ctor_arg_used"
        return plan, None
    pixel = {}
    i = 0
    rolled = []
    stored_params = {}
    contains_counts = collections.OrderedDict()
    while i < len(rest):
        s = rest[i]
        code = s.code
        nxt = rest[i + 1] if i + 1 < len(rest) else None
        # randpixel_xy()
        if code == "randpixel_xy()" and s.indent == 1:
            plan.entries.append("rolls(ROLL_PIXEL, PIXEL_JITTER(nameof(randpixel)))")
            i += 1
            continue
        m = cond_split(code)
        if m and s.indent == 1 and m[0] == "if":
            cond, tail = m[1], m[2]
            # if(!isnull(a)) v = a / if(a) v = a / if(a) set_dir(a)
            pm2 = re.fullmatch(r"!?\s*(?:isnull\()?\s*(\w+)\s*\)?", cond.replace("!isnull(", "isnull(").strip())
            body = tail.strip()
            body_stmt = None
            if not body and nxt is not None and nxt.indent == 2:
                body_stmt = nxt
                body = nxt.code
            if pm2 and pm2.group(1) in extra:
                a = pm2.group(1)
                tgt = stored_target(body, a)
                if tgt and (not body_stmt or (i + 2 >= len(rest) or rest[i + 2].indent == 1)):
                    stored_params[a] = tgt
                    i += 2 if body_stmt else 1
                    continue
            # if(!v) v = <random>: rolled only while the var holds nothing (a subtype or map that gives one keeps it)
            nm2 = re.fullmatch(r"!\s*(\w+)|isnull\(\s*(\w+)\s*\)", cond.strip())
            am0 = ASSIGN.match(body) if body else None
            if nm2 and am0 and am0.group(1) == (nm2.group(1) or nm2.group(2)) and RANDOM.search(am0.group(2)) and safe_expr(am0.group(2))                     and am0.group(1) not in SKIP_VARS and (not body_stmt or i + 2 >= len(rest) or rest[i + 2].indent == 1):
                var, expr = am0.group(1), am0.group(2)
                gen = generator(expr)
                if not gen:
                    pname = "roll_%s" % var
                    plan.procs.append((pname, ["	return %s" % to_roller(expr)]))
                    gen = "PROC_REF(%s)" % pname
                plan.entries.append("rolls(nameof(%s), %s, when = cond_not(nameof(%s)))" % (var, gen, var))
                rolled.append(var)
                i += 2 if body_stmt else 1
                continue
            # if(prob(N)) v = X [else v = Y]
            if RANDOM.search(cond) and safe_expr(cond):
                am = ASSIGN.match(body)
                if am and am.group(1) not in SKIP_VARS and safe_expr(am.group(2)):
                    var, val = am.group(1), am.group(2)
                    consumed = 2 if body_stmt else 1
                    other = var
                    after = rest[i + consumed] if i + consumed < len(rest) else None
                    if after is not None and after.indent == 1 and after.code.startswith("else"):
                        etail = after.code[4:].strip()
                        econsumed = 1
                        if not etail and i + consumed + 1 < len(rest) and rest[i + consumed + 1].indent == 2:
                            etail = rest[i + consumed + 1].code
                            econsumed = 2
                        em = ASSIGN.match(etail)
                        if not em or em.group(1) != var or not safe_expr(em.group(2)):
                            return None, "condition"
                        other = em.group(2)
                        consumed += econsumed
                    pname = "roll_%s" % var
                    plan.procs.append((pname, ["\treturn %s ? %s : %s" % (to_roller(cond), to_roller(val), to_roller(other))]))
                    plan.entries.append("rolls(nameof(%s), PROC_REF(%s))" % (var, pname))
                    rolled.append(var)
                    i += consumed
                    continue
            return None, "condition"
        if s.indent != 1:
            return None, "nested"
        if code == "default_apply_parts()" and proc.type.startswith("/obj/machinery/"):
            if any(a in INIT_TYPES for a in ancestors_of(proc.type) if a.count("/") > 2):
                return None, "parts_ancestor_init"
            plan.entries.append("default_parts()")
            i += 1
            continue
        rm = re.fullmatch(r"make_rotatable\(\s*(only_flip\s*=\s*TRUE)?\s*\)", code)
        if rm:
            if related_any(proc.type, ROT_HOOK_TYPES):
                return None, "rotation_hooks"
            plan.entries.append("rotatable(only_flip = TRUE)" if rm.group(1) else "rotatable()")
            i += 1
            continue
        if code == "update_icon()" and CHAINS is not None and not CHAINS.live(proc.type):
            plan.dropped += 1
            i += 1
            continue
        em = re.fullmatch(r"expire\((.+)\)", code)
        if em and not re.search(r"(?<![A-Z_])[a-z_][a-z0-9_]*(?![A-Z0-9_(])", re.sub(r"\b(SECONDS?|MINUTES?|DECISECONDS?|DS|TICKS?)\b", "", em.group(1))):
            plan.defaults.append(("lifecycle_lifetime", em.group(1).strip()))
            i += 1
            continue
        # contains / knows
        nm = NEW_SRC.match(code)
        if nm:
            contains_counts[nm.group(1)] = contains_counts.get(nm.group(1), 0) + 1
            i += 1
            continue
        lm = ADD_LANG.match(code)
        if lm:
            plan.entries.append("knows(%s)" % lm.group(1))
            i += 1
            continue
        # params: v = a, rel_set(src, nameof(v), a), set_dir(a)
        hit = None
        for a in extra:
            tgt = stored_target(code, a)
            if tgt:
                hit = (a, tgt)
                break
        if hit:
            stored_params[hit[0]] = hit[1]
            i += 1
            continue
        om = re.match(r"^(?:src\.)?([a-z_]\w*)\s*(\+|-)=\s*(.+)$", code)
        if om and om.group(1) not in SKIP_VARS and RANDOM.search(om.group(3)) and safe_expr(om.group(3)):
            var = om.group(1)
            pname = "roll_%s" % var
            plan.procs.append((pname, ["	return %s %s (%s)" % (var, om.group(2), to_roller(om.group(3)))]))
            plan.entries.append("rolls(nameof(%s), PROC_REF(%s))" % (var, pname))
            rolled.append(var)
            i += 1
            continue
        am = ASSIGN.match(code)
        if am and am.group(1) not in SKIP_VARS and RANDOM.search(am.group(2)) and safe_expr(am.group(2)):
            var, expr = am.group(1), am.group(2)
            if var in ("pixel_x", "pixel_y"):
                pixel[var] = expr
            gen = generator(expr)
            if gen:
                plan.entries.append("rolls(nameof(%s), %s)" % (var, gen))
            else:
                pname = "roll_%s" % var
                plan.procs.append((pname, ["\treturn %s" % to_roller(expr)]))
                plan.entries.append("rolls(nameof(%s), PROC_REF(%s))" % (var, pname))
            rolled.append(var)
            i += 1
            continue
        return None, "statement"
    # Every extra argument must be stored, or unused.
    body_text = "\n".join(s.code for s in rest)
    for pos, a in enumerate(extra, 1):
        if a in stored_params:
            plan.entries.append("param(nameof(%s), pos = %d)" % (stored_params[a], pos))
        elif re.search(r"(?<![\w.])%s(?!\w)" % re.escape(a), body_text):
            return None, "ctor_arg_used"
    # The two pixel rolls of one range become one jitter.
    if set(pixel) == {"pixel_x", "pixel_y"}:
        gx, gy = generator(pixel["pixel_x"]), generator(pixel["pixel_y"])
        mx = re.fullmatch(r"range_of\((-?[\w.]+), ([\w.]+)\)", gx or "")
        my = re.fullmatch(r"range_of\((-?[\w.]+), ([\w.]+)\)", gy or "")
        if mx and my and gx == gy and mx.group(1).lstrip("-") == mx.group(2) and mx.group(1).startswith("-"):
            plan.entries = [e for e in plan.entries if not e.startswith(("rolls(nameof(pixel_x)", "rolls(nameof(pixel_y)"))]
            plan.entries.insert(0, "rolls(ROLL_PIXEL, PIXEL_JITTER(%s))" % mx.group(2))
    for t, n in contains_counts.items():
        plan.entries.append("initial_contents(%s%s)" % (t, ", count = %d" % n if n > 1 else ""))
    # A var rolled twice (if/else chains) is one roll proc already; two entries for one var keep the last.
    seen = set()
    entries = []
    for e in reversed(plan.entries):
        key = e.split(",")[0]
        if key.startswith("rolls(nameof(") and key in seen:
            continue
        seen.add(key)
        entries.append(e)
    plan.entries = list(reversed(entries))
    if not plan.entries and not plan.defaults and not plan.dropped:
        return None, "nothing"
    return plan, None


def block_roll(f, proc, rest):
    """(var, roll proc body) when every statement is a random branch (if/else if/else on prob/rand/pick) or a write of one var (=, +=, -=)
    from a safe expression: the whole body becomes that var's roll, drawing through R. None otherwise."""
    target = None
    has_random = False
    lines = []
    for s in rest:
        code = s.code
        tail = None
        c = cond_split(code)
        if c:
            if not safe_expr(c[1]) or not RANDOM.search(c[1]):
                return None
            has_random = True
            tail = c[2]
            head = "%s(%s)" % (c[0], to_roller(c[1]))
        elif code == "else" or code.startswith("else "):
            tail = code[4:].strip()
            head = "else"
        else:
            head = None
            tail = code
        if tail:
            m = re.match(r"^(?:src\.)?([a-z_]\w*)\s*(\+=|-=|=)\s*(?!=)(.+)$", tail)
            if not m or not safe_expr(m.group(3)) or m.group(1) in SKIP_VARS:
                return None
            if target and m.group(1) != target:
                return None
            target = m.group(1)
            if RANDOM.search(m.group(3)):
                has_random = True
            if re.search(r"(?<![\w.])%s(?!\w)" % re.escape(target), m.group(3)):
                return None
            write = ". %s %s" % (m.group(2), to_roller(m.group(3)))
            text = (head + " " + write) if head else write
        else:
            text = head
        lines.append("\t" * int(s.indent) + text)
    if not target or not has_random:
        return None
    return target, ["\t. = islist(%s) ? list() + %s : %s" % (target, target, target)] + lines


def stored_target(code, a):
    """The var an argument `a` is stored into by this statement, or None."""
    m = ASSIGN.match(code)
    if m and m.group(2).strip() == a and m.group(1) not in SKIP_VARS:
        return m.group(1)
    m = REL_SET.match(code)
    if m and m.group(2) == a:
        return m.group(1)
    m = SET_DIR.match(code)
    if m and m.group(1) == a:
        return "dir"
    return None


def delete_override(f, proc):
    start = proc.start
    # its keep and doc comment lines directly above
    while start > 0 and f.lines[start - 1].lstrip().startswith("//") and not f.lines[start - 1].startswith(("\t", " ")):
        start -= 1
    end = proc.end
    while end < len(f.lines) and f.lines[end].strip() == "":
        end += 1
    keep_blank = start > 0 and f.lines[start - 1].strip() != "" and end < len(f.lines)
    f.lines[start:end] = [""] if keep_blank else []
    f.dirty = True
    return start + (1 if keep_blank else 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--sites", action="store_true")
    ap.add_argument("--others", action="store_true")
    ap.add_argument("--paths", nargs="*", default=["code/", "maps/"])
    ap.add_argument("--residue")
    a = ap.parse_args()
    files = dm_files(a.paths, others=a.others)
    global CHAINS
    every = dm_files(["code/"], others=True)
    for rel in every:
        g = File(rel)
        for p in procs_in(g):
            if p.name == "Initialize" and p.kind is None:
                INIT_TYPES.add(p.type)
            if p.name in ("handle_rotation_verbs", "ghosts_can_use_rotate_verbs", "can_use_rotate_verbs_while_anchored"):
                ROT_HOOK_TYPES.add(p.type)
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "dx", "codemods"))
    import look_sweep  # noqa: E402
    CHAINS = look_sweep.Chains({rel: File(rel) for rel in look_sweep.code_files()})
    counts = collections.Counter()
    residue = collections.Counter()
    cap_idx = capabilities_index() if a.apply else None
    opened = {}

    def get(rel):
        if rel not in opened:
            opened[rel] = File(rel)
        return opened[rel]

    sites = []
    for rel in files:
        if rel.startswith(("code/modules/unit_tests/", "code/tests/", "code/modules/benchmarks/", "code/engine/")):
            continue
        f = get(rel)
        if "Initialize" not in "\n".join(f.lines):
            continue
        procs = [p for p in procs_in(f) if p.name == "Initialize" and p.kind is None]
        for proc in reversed(procs):
            plan, why = plan_override(proc)
            if not plan:
                residue[why] += 1
                continue
            kinds = sorted({e.split("(")[0] for e in plan.entries})
            counts["+".join(kinds)] += 1
            sites.append("%s\t%s:%d\t%s" % (proc.type, rel, proc.start + 1, "; ".join(plan.entries)))
            if not a.apply:
                continue
            ty = proc.type
            at = delete_override(f, proc)
            roll_procs = []
            for name, body in plan.procs:
                roll_procs += ["", "/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.",
                               "%s/proc/%s(datum/roller/R)" % (ty, name)] + body
            entries = ["\t" + e for e in plan.entries]
            if plan.defaults:
                f.lines[at:at] = ["%s/%s = %s" % (ty, var, value) for var, value in plan.defaults] + [""]
            if not entries and not roll_procs:
                f.dirty = True
                continue
            where = cap_idx.get(ty)
            if where and where[0] == rel:
                hdr = where[1]
                if hdr >= at:
                    hdr += 0  # deletion above shifted it: recompute
                    hdr = next(k for k, l in enumerate(f.lines) if l.startswith("CAPABILITIES(%s)" % ty))
                insert_at = block_end(f, hdr)
                f.lines[insert_at:insert_at] = entries
                if insert_at <= at:
                    at += len(entries)
                f.lines[at:at] = roll_procs[1:] + [""] if roll_procs else []
            elif where:
                g = get(where[0])
                hdr = next(k for k, l in enumerate(g.lines) if l.startswith("CAPABILITIES(%s)" % ty))
                insert_at = block_end(g, hdr)
                g.lines[insert_at:insert_at] = entries
                g.dirty = True
                if roll_procs:
                    f.lines[at:at] = roll_procs[1:] + [""]
            else:
                block = ["CAPABILITIES(%s)" % ty] + entries
                f.lines[at:at] = block + roll_procs + [""]
                cap_idx[ty] = (rel, at)
            f.dirty = True
    if a.apply:
        for g in opened.values():
            g.save()
    if a.sites:
        print("\n".join(sites))
    print("lifeform_init: converted %s (%d); left %s" % (dict(counts.most_common()), sum(counts.values()), dict(residue.most_common())))
    if a.residue:
        with open(a.residue, "w") as fh:
            json.dump(dict(residue), fh)


if __name__ == "__main__":
    main()
