#!/usr/bin/env python3
r"""DECLARE_PERIODIC_WHILE / DECLARE_REPEAT -> a type-level every(interval, then(PROC_REF(x)), when = ...)
(doc/rewrite/codemod_rules.md, "DECLARE_PERIODIC_WHILE and DECLARE_REPEAT -> every()").

    python tools/dx/codemods/periodic_while.py [--check] [--sites] [--why] [--only /type] [--files paths...]

One declaration at a time. The fields it names become TRACKED (an OM_FIELD turns into the var line plus TRACKED), the declaration turns into an every() entry in the
type's CAPABILITIES block, and for a PERIODIC_WHILE its periodic_step() handler (and every override of it below the type) is renamed <type>_step and takes
(datum/act/timer/A). A declaration that does not match the rules exactly is residue with a code (--sites lists them). Idempotent. Run `analyze gen` afterwards.
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import os
import re
import subprocess
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ui_declare import File, body_range, related, split_args, strip_code, words_in  # noqa: E402

SKIP = ("code/__defines/", "code/modules/unit_tests/", "code/tests/", "tools/", "code/modules/tgs/", "code/datums/sys/")
CADENCES = {"PERIODIC_SLOW": "2 SECONDS", "PERIODIC_SECOND": "1 SECOND", "PERIODIC_FAST": "0.2 SECONDS"}
ATOM_ROOTS = ("/obj", "/turf", "/mob", "/area", "/atom")
HEAD = re.compile(r"^(DECLARE_PERIODIC_WHILE_ALL|DECLARE_PERIODIC_WHILE|DECLARE_PERIODIC|DECLARE_REPEAT)\((.*)\)\s*(//.*)?$")
OMF = re.compile(r"^OM_FIELD\((/[\w/]+),\s*(\w+),\s*(.*),\s*(CHANGE_\w+)\)\s*(//.*)?$")
OMF_TYPED = re.compile(r"^OM_FIELD_TYPED\((.*)\)\s*(//.*)?$")
TRACKED = re.compile(r"^TRACKED(?:_BRIDGED|_SCHEMA)?\((/[\w/]+),\s*(\w+)")
DERIVE = re.compile(r"^OM_DERIVE_FIELD\((/[\w/]+),\s*(\w+),\s*list\((.*)\)\)\s*(//.*)?$")
TIME = re.compile(r"^\d+(\.\d+)?( [A-Z]+)?$")


def is_atom(t):
    """A holder the engine arms an every() for: an atom at Initialize(), a plain datum at New() (lifeform_datum_new). A /datum/system arms its work from reactions()."""
    return t.startswith(ATOM_ROOTS) or (t.startswith("/datum") and not t.startswith("/datum/system"))


def ancestors_or_self(t, u):
    """Is u an ancestor of t, or t itself (type paths)?"""
    return t == u or t.startswith(u + "/")


def parse_expr(text, names):
    """`a || !b && (c)` over the identifiers `names` as a tree ("var", x) / ("not", e) / ("any", [e..]) / ("all", [e..]), or None."""
    toks = re.findall(r"\w+|\|\||&&|!|\(|\)|\S", text)
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else None

    def take():
        pos[0] += 1
        return toks[pos[0] - 1]

    def p_or():
        parts = [p_and()]
        while peek() == "||":
            take()
            parts.append(p_and())
        if None in parts:
            return None
        return parts[0] if len(parts) == 1 else ("any", parts)

    def p_and():
        parts = [p_not()]
        while peek() == "&&":
            take()
            parts.append(p_not())
        if None in parts:
            return None
        return parts[0] if len(parts) == 1 else ("all", parts)

    def p_not():
        t = peek()
        if t == "!":
            take()
            e = p_not()
            return None if e is None else ("not", e)
        if t == "(":
            take()
            e = p_or()
            if e is None or peek() != ")":
                return None
            take()
            return e
        if t is not None and t in names:
            take()
            return ("var", t)
        return None

    tree = p_or()
    return tree if tree is not None and pos[0] == len(toks) else None


def tree_text(tree):
    kind = tree[0]
    if kind == "var":
        return "nameof(%s)" % tree[1]
    if kind == "not":
        return "cond_not(%s)" % tree_text(tree[1])
    return "cond_%s(%s)" % (kind, ", ".join(tree_text(x) for x in tree[1]))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    sites = "--sites" in sys.argv
    why_out = "--why" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
        args = [a for a in args if a != only]
    if "--dirs" in sys.argv:
        args = []
    if "--files" in sys.argv:
        names = args
    else:
        names = subprocess.check_output(["git", "ls-files", "-z", "*.dm"]).decode("utf-8", "surrogateescape").split("\0")
        names = [n for n in names if n and not n.startswith(SKIP)]
    files = {}
    for rel in names:
        try:
            files[rel] = File(rel)
        except OSError:
            continue

    decls = []  # (kind, type, rel, line, parsed args)
    omfield = {}  # (type, field) -> (rel, idx, vt, default, channel)
    tracked = set()
    derive = {}  # (type, field) -> (rel, idx, [inputs])
    capblock = {}  # type -> (rel, idx)
    macro_mentions = defaultdict(list)  # "field" -> [(rel, idx, first_type)] col-0 macro lines that name it in a string
    for rel, f in files.items():
        for i, l in enumerate(f.lines):
            m = HEAD.match(l)
            if m:
                parts = split_args(m.group(2))
                decls.append((m.group(1), parts[0] if parts else "", rel, i, parts))
                continue
            m = OMF.match(l)
            if m:
                omfield[(m.group(1), m.group(2))] = (rel, i, None, m.group(3), m.group(4))
                continue
            m = OMF_TYPED.match(l)
            if m:
                p = split_args(m.group(1))
                if len(p) == 5:
                    omfield[(p[0], p[2])] = (rel, i, p[1], p[3], p[4])
                continue
            m = TRACKED.match(l)
            if m:
                tracked.add((m.group(1), m.group(2)))
                continue
            m = DERIVE.match(l)
            if m:
                derive[(m.group(1), m.group(2))] = (rel, i, re.findall(r'"(\w+)"', m.group(3)))
                continue
            m = re.match(r"^CAPABILITIES\((/[\w/]+)\)\s*(//.*)?$", l)
            if m:
                capblock[m.group(1)] = (rel, i)
            if l and re.match(r"^[A-Z][A-Z_]+\(", l):
                ft = re.match(r"^[A-Z_]+\((/[\w/]+)", l)
                for name in re.findall(r'"!?(\w+)"', l):
                    macro_mentions[name].append((rel, i, ft.group(1) if ft else None))

    # ---- procs: definitions by name, and who mentions which identifier outside definitions
    dre = re.compile(r"^(/[\w/]+?)/(?:proc/)?(\w+)\(([^)]*)\)\s*(//.*)?$")
    defs_by_name = defaultdict(list)
    mention_idx = defaultdict(set)
    tok = re.compile(r"(?<![\w./])[A-Za-z_]\w*")
    for rel, f in files.items():
        owner = ""
        for i, l in enumerate(f.lines):
            if l and l[0] == "/":
                dm = dre.match(l)
                if dm:
                    defs_by_name[dm.group(2)].append((dm.group(1), rel, i, dm.group(3)))
                    owner = dm.group(1)
                    continue
                dm0 = re.match(r"^(/[\w/]+?)/(?:proc/)?\w+\(", l)
                if dm0:
                    owner = dm0.group(1)
                    continue
            for w in tok.findall(strip_code(l)):
                mention_idx[w].add(owner)
    all_proc_names = set(defs_by_name)

    # Calls of periodic_step() on a receiver (`organ.periodic_step()`): the receiver's declared type, from a var declaration above the call or in the
    # file. A type related to one cannot be converted: something else drives its handler by name.
    call_types = set()
    call_dre = re.compile(r"(\w+(?:\(\))?)\.periodic_step\(")
    for rel, f in files.items():
        for i, l in enumerate(f.lines):
            if "periodic_step(" not in l or l.lstrip().startswith("//"):
                continue
            for m in call_dre.finditer(l):
                rcv = re.escape(m.group(1))
                ty = None
                for j in range(i, max(-1, i - 60), -1):
                    mm = re.search(r"(?:var/|[(,]\s*)((?:\w+/)+)" + rcv + r"\b", f.lines[j] or "")
                    if mm:
                        ty = mm.group(1)
                        break
                if not ty:
                    for j in range(len(f.lines)):
                        mm = re.search(r"var/((?:\w+/)+)" + rcv + r"\b", f.lines[j] or "")
                        if mm:
                            ty = mm.group(1)
                            break
                if ty:
                    call_types.add("/" + ty.replace("var/", "").strip("/"))
                else:
                    print("periodic_while: warning: %s:%d calls %s.periodic_step() on a receiver of unknown type (ignored)" % (rel, i + 1, m.group(1)), file=sys.stderr)

    by_type = defaultdict(list)
    for d in decls:
        by_type[d[1]].append(d)

    residue = {}
    plans = []
    om_rewrites = {}  # (rel, idx) -> new lines
    derive_deletes = set()  # (rel, idx)
    renames = {}  # (rel, idx) -> (sig text, delta used) for periodic_step definitions
    used_names = set()

    def field_plan(t, name, neg, own_decl_line):
        """The when-expression of one declared field and the rewrites it needs, or (None, reason)."""
        rewrites = []
        deletes = []

        def shared(fname, allowed_lines):
            for (r2, i2, ft) in macro_mentions.get(fname, []):
                if (r2, i2) in allowed_lines:
                    continue
                if ft is None or related(ft, t):
                    return True
            return False

        def tracked_here(fname):
            """TRACKED already, or an OM_FIELD on T or an ancestor that can become one: the rewrites, or None."""
            for u in sorted({u for (u, n) in tracked if n == fname and ancestors_or_self(t, u)}):
                return []
            hits = [(u, v) for (u, n), v in omfield.items() if n == fname and ancestors_or_self(t, u)]
            if len(hits) != 1:
                return None
            u, (rel, idx, vt, dflt, ch) = hits[0]
            if shared(fname, {(rel, idx), own_decl_line}):
                return None
            var_line = "%s/var/%s%s = %s" % (u, vt + "/" if vt else "", fname, dflt)
            macro = "TRACKED(%s, %s)" % (u, fname) if ch == "CHANGE_EXPLICIT" else "TRACKED_BRIDGED(%s, %s, %s)" % (u, fname, ch)
            return [((rel, idx), [var_line, macro])]

        r = tracked_here(name)
        if r is not None:
            return ("cond_not(nameof(%s))" if neg else "nameof(%s)") % name, r, []
        if (t, name) in derive:
            # A derived field is inlined as a condition tree when its proc is one `return` of the declared inputs joined by ||, && and !, and no related type
            # redefines it (a tree cannot dispatch on the instance); anything else is residue: a gate is a tracked var or a tree of them.
            rel, idx, inputs = derive[(t, name)]
            own_defs = [x for x in defs_by_name.get(name, []) if x[0] == t]
            if len(own_defs) != 1 or any(x[0] != t and related(x[0], t) for x in defs_by_name.get(name, [])):
                return None, "derived_expr", None
            if any(u != t and related(u, t) and (u, name) in derive for (u, n) in derive):
                return None, "derived_expr", None
            _ty, drel, didx, _params = own_defs[0]
            fb, lb = body_range(files[drel].lines, didx)
            stmts = [strip_code(x).strip() for x in files[drel].lines[fb : lb + 1] if x is not None and strip_code(x).strip()]
            if len(stmts) != 1 or not stmts[0].startswith("return "):
                return None, "derived_expr", None
            tree = parse_expr(stmts[0][len("return ") :], set(inputs))
            if tree is None:
                return None, "derived_expr", None
            if shared(name, {(rel, idx), own_decl_line}):
                return None, "field_shared", None
            for inp in inputs:
                ir = tracked_here(inp)
                if ir is None:
                    return None, "field_kind", None
                rewrites += ir
            expr = tree_text(tree)
            return ("cond_not(%s)" % expr if neg else expr), rewrites, [(rel, idx)]
        # an OM_FIELD that tracked_here refused is shared with another legacy form
        if any(n == name and ancestors_or_self(t, u) for (u, n) in omfield):
            return None, "field_shared", None
        return None, "field_kind", None

    def check_while(t, d):
        kind, _t, rel, i, parts = d
        if kind == "DECLARE_PERIODIC":
            # an ungated periodic: every() with no when, the work runs from init for the holder's life
            if len(parts) != 2:
                return "decl_form"
            cad, fields = parts[1], []
        elif kind == "DECLARE_PERIODIC_WHILE":
            if len(parts) != 3:
                return "decl_form"
            cad, fields = parts[1], [parts[2]]
        else:
            if len(parts) != 3 or not parts[2].startswith("list("):
                return "decl_form"
            cad, fields = parts[1], [x for x in split_args(parts[2][5:-1]) if x]
        if cad == "MACHINE_PIPELINE":
            return "machine_pipeline"
        if cad not in CADENCES:
            return "cadence"
        specs = []
        for fl in fields:
            m = re.match(r'^"(!?)(\w+)"$', fl)
            if not m:
                return "decl_form"
            specs.append((m.group(2), m.group(1) == "!"))
        if not specs and kind != "DECLARE_PERIODIC":
            return "decl_form"
        # handler
        hdefs = [x for x in defs_by_name.get("periodic_step", []) if x[0] == t]
        if len(hdefs) != 1:
            return "handler_shape"
        if any(x[0] != t and x[0] != "/datum" and t.startswith(x[0] + "/") for x in defs_by_name.get("periodic_step", [])):
            return "ancestor_handler"
        tree_defs = [x for x in defs_by_name.get("periodic_step", []) if ancestors_or_self(x[0], t)]
        if any(related(c, t) for c in call_types):
            return "handler_called"
        for owner in mention_idx.get("periodic_step", ()):
            if owner == "" or related(owner, t):
                return "handler_called"
        for owner in mention_idx.get("om_task_periodic", ()):
            if owner == "" or related(owner, t):
                return "manual_start"
        for (ty, r, idx, params) in tree_defs:
            fb, lb = body_range(files[r].lines, idx)
            body = "\n".join(strip_code(x) for x in files[r].lines[fb : lb + 1] if x is not None)
            if "PROCESS_KILL" in body or "sleep_until_" in body:  # a helper that leaves the old lane (sleep_until_mob_near) is a kill too
                return "handler_kill"
            if words_in(body, "A"):
                return "body_uses"
            ps = [p.strip() for p in params.split(",") if p.strip()]
            if len(ps) > 1 or (ps and "=" in ps[0]):
                return "handler_shape"
        plan_fields = []
        rewrites = []
        deletes = []
        for name, neg in specs:
            expr, rw, dl = field_plan(t, name, neg, (rel, i))
            if expr is None:
                return rw
            plan_fields.append(expr)
            rewrites += rw
            deletes += dl or []
        base = t.split("/")[-1]
        new_name = "%s_step" % base
        if new_name in all_proc_names or new_name in used_names:
            return "name_clash"
        when = None if not plan_fields else plan_fields[0] if len(plan_fields) == 1 else "cond_all(%s)" % ", ".join(plan_fields)
        return {"kind": "while", "decl": (rel, i), "type": t, "interval": CADENCES[cad], "proc": new_name, "when": when, "rewrites": rewrites, "deletes": deletes, "tree_defs": tree_defs}

    def check_repeat(t, d):
        kind, _t, rel, i, parts = d
        if len(parts) != 4:
            return "decl_form"
        delay, proc, field = parts[1], parts[2], parts[3]
        if not re.match(r"^\w+$", proc):
            return "decl_form"
        if TIME.match(delay):
            interval = delay
        else:
            m = re.match(r'^"(\w+)"$', delay)
            if m and any(ancestors_or_self(t, ty) for (ty, _r, _i, _p) in defs_by_name.get(m.group(1), [])):
                interval = "PROC_REF(%s)" % m.group(1)
            else:
                return "delay_var"
        param_edits = []  # (rel, idx, new parameter text, proc): the handler and a proc interval take one act parameter
        for (ty, r, idx, params) in defs_by_name.get(proc, []):
            if related(ty, t):
                fb, lb = body_range(files[r].lines, idx)
                body = "\n".join(strip_code(x) for x in files[r].lines[fb : lb + 1] if x is not None)
                if "REPEAT_STOP" in body:
                    return "repeat_stop"
                if params.strip():
                    return "handler_params"
                if words_in(body, "A"):
                    return "body_uses"
                param_edits.append((r, idx, "datum/act/timer/A", proc))
        if interval.startswith("PROC_REF("):
            dproc = interval[len("PROC_REF(") : -1]
            for (ty, r, idx, params) in defs_by_name.get(dproc, []):
                if related(ty, t):
                    if params.strip():
                        return "handler_params"
                    param_edits.append((r, idx, "datum/act/A", dproc))
        for other in decls:
            if other[0] == "DECLARE_REPEAT" and other is not d and len(other[4]) == 4 and other[4][2] == proc and related(other[1], t):
                return "related_decl"
        when = None
        rewrites = []
        deletes = []
        if field != "null":
            m = re.match(r'^"(!?)(\w+)"$', field)
            if not m:
                return "decl_form"
            expr, rw, dl = field_plan(t, m.group(2), m.group(1) == "!", (rel, i))
            if expr is None:
                return rw
            when = expr
            rewrites += rw
            deletes += dl or []
        return {"kind": "repeat", "decl": (rel, i), "type": t, "interval": interval, "proc": proc, "when": when, "rewrites": rewrites, "deletes": deletes, "tree_defs": [], "param_edits": param_edits}

    for t, ds in sorted(by_type.items()):
        if only and t != only:
            continue
        key_t = t
        for d in ds:
            kind = d[0]
            tag = "%s %s" % (kind, t) if kind != "DECLARE_REPEAT" else "DECLARE_REPEAT %s %s" % (t, d[4][2] if len(d[4]) == 4 else "?")
            if not is_atom(t):
                residue[tag] = "non_atom"
                continue
            if kind != "DECLARE_REPEAT":
                if d[4][1:2] == ["MACHINE_PIPELINE"]:
                    residue[tag] = "machine_pipeline"
                    continue
                if len([x for x in ds if x[0] != "DECLARE_REPEAT"]) != 1:
                    residue[tag] = "decl_form"
                    continue
                if any(u != t and related(u, t) and any(x[0] != "DECLARE_REPEAT" for x in by_type[u]) for u in by_type):
                    residue[tag] = "related_decl"
                    continue
                r = check_while(t, d)
            else:
                r = check_repeat(t, d)
            if isinstance(r, str):
                residue[tag] = r
                continue
            if r["kind"] == "while":
                used_names.add(r["proc"])
            plans.append(r)

    # --dirs a b ...: the whole tree is read, only declarations in these directories convert
    if "--dirs" in sys.argv:
        want = [x.rstrip("/") + "/" for x in sys.argv[sys.argv.index("--dirs") + 1 :] if not x.startswith("--")]
        plans = [pl for pl in plans if any(pl["decl"][0].replace(chr(92), "/").startswith(w) for w in want)]
    # Two plans that rewrite the same OM_FIELD (several declarations naming one field) rewrite it once.
    converted = len(plans)
    if not check:
        done_rewrites = set()
        done_derives = set()
        # group the every entries by type: one CAPABILITIES block gets all of them
        entries = defaultdict(list)
        for pl in plans:
            t = pl["type"]
            if pl["kind"] == "while":
                then = "then(PROC_REF(%s))" % pl["proc"]
                for (ty, r, idx, params) in pl["tree_defs"]:
                    f = files[r]
                    ps = [p.strip() for p in params.split(",") if p.strip()]
                    fb, lb = body_range(f.lines, idx)
                    body = "\n".join(strip_code(x) for x in f.lines[fb : lb + 1] if x is not None)
                    uses_delta = bool(ps) and words_in(body, ps[0])
                    sig = ("%s/proc/%s(datum/act/timer/A)" if ty == t else "%s/%s(datum/act/timer/A)") % (ty, pl["proc"])
                    f.lines[idx] = re.sub(r"^(/[\w/]+?)/(?:proc/)?periodic_step\([^)]*\)", lambda m: sig, f.lines[idx])
                    if uses_delta:
                        indent = "\t"
                        for k in range(fb, lb + 1):
                            if f.lines[k] and f.lines[k].strip():
                                indent = re.match(r"^[ \t]*", f.lines[k]).group(0)
                                break
                        # A.dt is the interval; the handlers/context_field lint does not model an every() context yet, so the constant is written out
                        f.lines[idx] = f.lines[idx] + "\n" + indent + "var/%s = %s" % (ps[0], pl["interval"])
                    f.dirty = True
            else:
                then = "then(PROC_REF(%s))" % pl["proc"]
                for (r, idx, ptext, pname) in pl["param_edits"]:
                    pat = r"^(/[\w/]+?/(?:proc/)?" + pname + r")\(\)"
                    files[r].lines[idx] = re.sub(pat, lambda m: m.group(1) + "(" + ptext + ")", files[r].lines[idx])
                    files[r].dirty = True
            interval = pl["interval"]
            entry = "every(%s, %s%s)" % (interval, then, ", when = %s" % pl["when"] if pl["when"] else "")
            # the comment lines directly above the declaration describe the work: they go above its entry
            drel, di = pl["decl"]
            above = []
            k = di - 1
            while k >= 0 and files[drel].lines[k] is not None and files[drel].lines[k].lstrip().startswith("//"):
                above.insert(0, files[drel].lines[k].strip())
                k -= 1
            for k2 in range(k + 1, di):
                files[drel].lines[k2] = None
            entry = "".join("// %s\n\t" % c.lstrip("/ ").strip() if not c.startswith("///") else "%s\n\t" % c for c in above) + entry
            entries[t].append((pl, entry))
            for (loc, new_lines) in pl["rewrites"]:
                if loc in done_rewrites:
                    continue
                done_rewrites.add(loc)
                rel, idx = loc
                files[rel].lines[idx] = "\n".join(new_lines)
                files[rel].dirty = True
            for loc in pl["deletes"]:
                if loc in done_derives:
                    continue
                done_derives.add(loc)
                files[loc[0]].lines[loc[1]] = None
                files[loc[0]].dirty = True
        for t, items in entries.items():
            block = capblock.get(t)
            if block:
                r, bi = block
                f = files[r]
                fb, lb = body_range(f.lines, bi)
                f.lines[lb] = f.lines[lb] + "".join("\n\t" + e for (_pl, e) in items)
                f.dirty = True
            first_decl = items[0][0]["decl"]
            for (pl, _e) in items:
                rel, i = pl["decl"]
                files[rel].lines[i] = None
                files[rel].dirty = True
            if not block:
                rel, i = first_decl
                files[rel].lines[i] = "CAPABILITIES(%s)" % t + "".join("\n\t" + e for (_pl, e) in items)
        for f in files.values():
            if f.dirty:
                f.save()
    by = defaultdict(list)
    for tag, why in residue.items():
        by[why].append(tag)
    n_while = sum(1 for p in plans if p["kind"] == "while")
    print("periodic_while: %d declarations converted (%d PERIODIC_WHILE, %d REPEAT)%s; residue %d" % (converted, n_while, converted - n_while, " (check)" if check else "", len(residue)))
    for why, ts in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print("    %-20s %4d" % (why, len(ts)))
        if sites or why_out:
            for tag in sorted(ts):
                print("        " + tag)
    return 1 if (check and plans) else 0


if __name__ == "__main__":
    sys.exit(main())
