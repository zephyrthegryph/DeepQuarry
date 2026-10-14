#!/usr/bin/env python3
r"""DECLARE_APPEARANCE_PROC(T, TYPE_PROC_REF(/atom, appearance_overlays), list()) -> /T/draw(datum/look/look)
(doc/rewrite/codemod_rules.md, "DECLARE_APPEARANCE_PROC -> draw(look)").

    python tools/dx/codemods/appearance_draw.py [--check] [--sites] [--no-track] [--skip-file F] [--files paths...]

Per appearance proc. Phase 1 turns the provider into a draw(): `. = list()` goes, `. += x` becomes look.overlay(x), `icon_state = x` look.state(x), `color`/`alpha`/... look.color,
`..()` is the first statement. Phase 2 (the rule "the vars a draw reads are TRACKED and their writers use setters"): every var of the holder the draw reads that is not tracked
already becomes TRACKED(U, var) (SETTER(U, var) when the type has its own set_<var>()) and every write to it in the tree becomes a setter call; a var whose writes cannot all be
rewritten (its name is declared on unrelated types, a write sits in a macro or in an expression, a builtin var) is residue and the proc keeps its old form. Idempotent.
Run `analyze gen` afterwards. `--skip-file F` lists types (one per line) that stay as they are (the converge driver's list: what the lints refused after a run).
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import os
import re
import subprocess
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ui_declare import File, body_range, related, split_args, strip_code, words_in  # noqa: E402

SKIP = ("code/__defines/", "code/modules/unit_tests/", "code/tests/", "tools/", "code/modules/tgs/")
HEAD = re.compile(r"^DECLARE_APPEARANCE_PROC\((/[\w/]+),\s*TYPE_PROC_REF\(/atom,\s*appearance_overlays\),\s*list\(\)\)\s*(//.*)?$")
LEGACY_APPEARANCE = re.compile(r"^(APPEARANCE_TEMPLATE|APPEARANCE_LEVEL|APPEARANCE_EMISSIVE|APPEARANCE_SLOT|APPEARANCE_NONE|DECLARE_APPEARANCE)\((/[\w/]+)")
LOOK_VARS = ("color", "alpha", "layer", "plane", "dir", "icon", "transform")
CONTROL = re.compile(r"^(if\(|else\b|switch\(|for\(|while\(|do\b|break\b|continue\b|var/|//|/\*)")
BUILTIN_VARS = {
    "name", "desc", "icon", "icon_state", "color", "alpha", "layer", "plane", "dir", "density", "opacity", "anchored", "invisibility", "pixel_x", "pixel_y", "pixel_w", "pixel_z",
    "light_range", "light_power", "light_color", "overlays", "underlays", "loc", "x", "y", "z", "contents", "mouse_opacity", "blend_mode", "appearance", "transform", "glide_size",
    "luminosity", "verbs", "vis_contents", "maptext", "key", "ckey", "stat", "gender", "health", "maxhealth", "list", "src", "usr", "world", "null", "TRUE", "FALSE",
}
ASSIGN = re.compile(r"^(?P<lhs>[A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)\s*(?P<op>=(?!=)|\+=|-=|\|=|&=|\*=|/=|\^=|<<=|>>=)\s*(?P<rhs>.*)$")
INCDEC = re.compile(r"^(?P<lhs>[A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)\s*(?P<op>\+\+|--)\s*$")
KEYWORDS = {"if", "else", "for", "while", "do", "switch", "return", "var", "in", "to", "step", "as", "new", "del", "null", "src", "usr", "TRUE", "FALSE", "list", "istype", "initial", "locate", "text", "num", "round", "min", "max", "abs", "length", "isnull", "ispath", "image", "icon", "world", "GLOB", "look", "break", "continue", "sleep", "spawn", "set", "global", "proc", "verb", "tmp", "static", "const", "call", "typesof", "get_turf", "get_dir", "get_step", "get_dist", "prob", "rand", "pick", "findtext", "copytext", "replacetext", "lowertext", "uppertext", "ismob", "isobj", "isturf", "isliving", "ishuman"}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    sites = "--sites" in sys.argv
    track = "--no-track" not in sys.argv
    skip_types = set()
    if "--skip-file" in sys.argv:
        sf = sys.argv[sys.argv.index("--skip-file") + 1]
        args = [a for a in args if a != sf]
        if os.path.exists(sf):
            skip_types = {l.strip() for l in open(sf) if l.strip()}
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

    dre = re.compile(r"^(/[\w/]+?)/(?:proc/)?(\w+)\(([^)]*)\)\s*(//.*)?$")
    hre = re.compile(r"^(/[\w/]+?)/(?:proc/)?(\w+)\(")
    decls = []
    appearance_defs = defaultdict(list)  # type -> [(rel, idx)]
    legacy_types = set()
    procs_named = defaultdict(list)  # proc name -> [(type, rel, idx, params)]
    var_decls = defaultdict(list)  # (type, var) -> [(rel, idx)]
    omfield = {}  # (type, var) -> (rel, idx, vt, default, channel)
    macro_mentions = defaultdict(list)
    tracked = set()  # (type, var): TRACKED / SETTER / OM_FIELD / relation
    owner_of_line = {}  # (rel, idx) -> (kind, type, procname, params): "proc" | "block"
    for rel, f in files.items():
        header = None
        for i, l in enumerate(f.lines):
            if l is None:
                continue
            if l and l[0] not in " \t":
                m = HEAD.match(l)
                if m:
                    decls.append((m.group(1), rel, i, m.group(2) or ""))
                    header = None
                    continue
                m = LEGACY_APPEARANCE.match(l)
                if m:
                    legacy_types.add(m.group(2))
                if l.startswith("DECLARE_APPEARANCE_PROC("):
                    m = re.match(r"^DECLARE_APPEARANCE_PROC\((/[\w/]+)", l)
                    if m:
                        legacy_types.add(m.group(1))
                m = re.match(r"^(TRACKED|TRACKED_BRIDGED|TRACKED_SCHEMA|SETTER)\((/[\w/]+),\s*(\w+)", l)
                if m:
                    tracked.add((m.group(2), m.group(3)))
                mo = re.match(r"^OM_FIELD\((/[\w/]+),\s*(\w+),\s*(.*),\s*(CHANGE_\w+)\)\s*(//.*)?$", l)
                if mo:
                    omfield[(mo.group(1), mo.group(2))] = (rel, i, None, mo.group(3), mo.group(4))
                mt = re.match(r"^OM_FIELD_TYPED\((.*)\)\s*(//.*)?$", l)
                if mt:
                    tp = split_args(mt.group(1))
                    if len(tp) == 5:
                        omfield[(tp[0], tp[2])] = (rel, i, tp[1], tp[3], tp[4])
                if re.match(r"^[A-Z][A-Z_]+\(", l):
                    ft = re.match(r"^[A-Z_]+\((/[\w/]+)", l)
                    for nm in re.findall(r'"!?(\w+)"', l):
                        macro_mentions[nm].append((rel, i, ft.group(1) if ft else None))
                dm = dre.match(l)
                hm = hre.match(l)
                if hm:
                    header = ("proc", hm.group(1), hm.group(2), dm.group(3) if dm else "", i)
                    procs_named[hm.group(2)].append((hm.group(1), rel, i, dm.group(3) if dm else ""))
                    if dm and dm.group(2) == "appearance_overlays":
                        appearance_defs[dm.group(1)].append((rel, i))
                    owner_of_line[(rel, i)] = header
                    continue
                vm = re.match(r"^(/[\w/]+)/var/(?:(?:tmp|static|global|const|final)/)*(?:[\w/]+/)?(\w+)\s*(=.*)?(//.*)?$", l)
                if vm:
                    var_decls[(vm.group(1), vm.group(2))].append((rel, i))
                    header = None
                    continue
                if re.match(r"^/[\w/]+\s*(//.*)?$", l):
                    header = ("block", l.split("//")[0].strip(), None, "", i)
                else:
                    header = None
                continue
            if header:
                owner_of_line[(rel, i)] = header
                if header[0] == "block":
                    vm = re.match(r"^\s+var/(?:(?:tmp|static|global|const|final)/)*(?:[\w/]+/)?(\w+)\s*(=.*)?(//.*)?$", l)
                    if vm:
                        var_decls[(header[1], vm.group(1))].append((rel, i))
                    rm = re.match(r"^\s+(?:owns_one|ref_one|owns_many|ref_many|link\w*)\(nameof\((\w+)\)", l)
                    if rm:
                        tracked.add((header[1], rm.group(1)))
        # relation entries live in CAPABILITIES(T) blocks: their owner is the CAPABILITIES type
        header = None
        for i, l in enumerate(f.lines):
            if l is None:
                continue
            if l and l[0] not in " \t":
                m = re.match(r"^CAPABILITIES\((/[\w/]+)\)", l)
                header = m.group(1) if m else None
                continue
            if header:
                rm = re.match(r"^\s+(?:owns_one|ref_one|owns_many|ref_many|link\w*)\(nameof\((\w+)\)", l)
                if rm:
                    tracked.add((header, rm.group(1)))

    derived_types = {u for (u, _r, _i, _p) in procs_named.get("derived", [])}
    set_procs = {(u, name[4:]) for name, defs_ in procs_named.items() if name.startswith("set_") for (u, _r, _i, _p) in defs_}
    declaring_types = defaultdict(set)
    for (u, v) in list(var_decls) + list(omfield):
        declaring_types[v].add(u)

    residue = {}
    plans = {}

    def classify_body(t, rel, idx):
        """The rewritten body lines of one appearance proc and the vars it reads, or a residue code."""
        f = files[rel]
        fb, lb = body_range(f.lines, idx)
        raw = [x for x in f.lines[fb : lb + 1]]
        body_text = "\n".join(strip_code(x) for x in raw if x is not None)
        if words_in(body_text, "look"):
            return "name_clash"
        if re.search(r"(?<![\w./])(icon_state|overlays|underlays)(?![\w])", re.sub(r"initial\(icon_state\)", "", re.sub(r"^\s*icon_state\s*=(?!=)", "", body_text, flags=re.M))):
            return "reads_icon_state"
        locals_ = set(re.findall(r"\bvar/(?:[\w/]+/)?(\w+)", body_text))
        images = set(re.findall(r"\bvar/(?:image|mutable_appearance)/(\w+)", body_text)) | set(re.findall(r"\bvar/(\w+)\s*=\s*(?:image|mutable_appearance)\(", body_text))
        out = []
        saw_super = False
        for x in raw:
            if x is None:
                continue
            code = strip_code(x)
            if not code.strip():
                out.append(x)
                continue
            indent = re.match(r"^[ \t]*", x).group(0)
            kept = strip_code(x, keep=True)
            comment = x[len(kept.rstrip()) :]
            stmt = kept.strip()
            if stmt == ". = list()" and not any(strip_code(y).strip() for y in out):
                continue
            if stmt in ("..()", ". = ..()", ". += ..()"):
                if saw_super or any(strip_code(y).strip() for y in out):
                    return "super_late"
                saw_super = True
                out.append(indent + "..()" + comment)
                continue
            if re.search(r"(?<![\w.])\.\.\(", stmt):
                return "super_late"
            if stmt in ("return", "return ."):
                out.append(indent + "return" + comment)
                continue
            if stmt.startswith("return"):
                return "returns_value"
            if CONTROL.match(stmt):
                if re.search(r"(?<![\w./])\.(?![\w.])", code.strip()) and not stmt.startswith("//"):
                    return "dot_use"
                out.append(x)
                continue
            m = re.match(r"^\.\s*\+=\s*(.*)$", stmt)
            if m:
                expr = m.group(1)
                if re.search(r"(?<![\w.])\.(?![\w.])", strip_code(expr)):
                    return "dot_use"
                calls = None
                lm = re.match(r"^list\((.*)\)$", expr)
                if lm:
                    calls = [c for c in split_args(lm.group(1)) if c]
                elif re.match(r'^"[^"]*"$', expr) or re.match(r"^(image|mutable_appearance|overlay_image|emissive_appearance)\(", expr) or re.match(r"^GLOB\.\w+\.\w+\(", expr) or re.match(r'^"[^"]*\[', expr):
                    calls = [expr]
                elif re.match(r"^[A-Za-z_]\w*$", expr) and expr in images:
                    calls = [expr]
                if not calls or any(re.match(r"^[A-Za-z_]\w*$", c) and c not in images for c in calls):
                    return "overlay_expr"
                for c in calls:
                    out.append(indent + "look.overlay(%s)" % c + (comment if c is calls[-1] else ""))
                continue
            if re.match(r"^\.\s*[-|&]?=", stmt) or stmt == ".":
                return "dot_use"
            am = ASSIGN.match(stmt)
            if am:
                lhs = am.group("lhs").replace(" ", "")
                if lhs == "icon_state" and am.group("op") == "=":
                    out.append(indent + "look.state(%s)" % am.group("rhs") + comment)
                    continue
                if lhs in LOOK_VARS and am.group("op") == "=":
                    out.append(indent + "look.%s = %s" % (lhs, am.group("rhs")) + comment)
                    continue
                if (lhs.split(".")[0] in locals_ and "." not in lhs) or lhs.startswith("look."):
                    out.append(x)
                    continue
                return "writes_state"
            im = INCDEC.match(stmt)
            if im:
                if im.group("lhs") in locals_:
                    out.append(x)
                    continue
                return "writes_state"
            return "side_effect"
        if not saw_super:
            first = next((y for y in out if y.strip()), "\t")
            ind = re.match(r"^[ \t]*", first).group(0) or "\t"
            at = next((k for k, y in enumerate(out) if y.strip()), 0)
            out.insert(at, ind + "..()")
        return out

    def vars_read(t, body):
        """The vars of T (or an ancestor) a draw body reads: identifiers not a call, a member, a local or a keyword that some ancestor-or-self declares as a var."""
        text = "\n".join(strip_code(x) for x in body)
        locals_ = set(re.findall(r"\bvar/(?:[\w/]+/)?(\w+)", text)) | set(re.findall(r"\bfor\(var/(?:[\w/]+/)?(\w+)", text))
        found = set()
        hops = set()
        for m in re.finditer(r"(?<![\w./\"])([A-Za-z_]\w*)(?![\w\(])", text):
            name = m.group(1)
            if name in KEYWORDS or name in locals_ or name == "look":
                continue
            rest = text[m.end() :].lstrip()
            if rest.startswith("("):
                continue
            found.add(name)
            if re.match(r"\??\.\s*[A-Za-z_]", rest):
                hops.add(name)
        result = {}
        for name in sorted(found):
            owners = [u for (u, v) in list(var_decls) + list(omfield) if v == name and (t == u or t.startswith(u + "/"))]
            if owners:
                result[name] = max(owners, key=len)
        return result, {h for h in hops if h in result}

    for t, rel, i, comment in decls:
        if t in skip_types:
            residue[t] = "skipped"
            continue
        if not t.startswith(("/obj", "/turf", "/mob", "/area", "/atom")):
            residue[t] = "non_atom"
            continue
        defs = appearance_defs.get(t, [])
        if len(defs) != 1:
            residue[t] = "handler_shape"
            continue
        if any(t == u or t.startswith(u + "/") for u in legacy_types):
            residue[t] = "appearance_other"
            continue
        if any(t == u or t.startswith(u + "/") for u in derived_types):
            residue[t] = "derived_declared"  # a type with a derived() declares its draw's reads there (drawn_from): that is the declaration form this rule replaces, by hand
            continue
        body = classify_body(t, defs[0][0], defs[0][1])
        if isinstance(body, str):
            residue[t] = body
            continue
        reads, hops = vars_read(t, body)
        if hops:
            residue[t] = "hop_read"
            continue
        plans[t] = {"type": t, "decl": (rel, i), "def": defs[0], "body": body, "reads": reads}

    # related definitions convert together or not at all
    changed = True
    while changed:
        changed = False
        for t in list(plans):
            rel_defs = [u for u in appearance_defs if u != t and related(t, u)]
            if any(u not in plans for u in rel_defs):
                residue[t] = "related_def"
                del plans[t]
                changed = True

    # ---- phase 2: tracking
    var_plan = {}  # (U, var) -> {"ok": bool, "why": code, "decl": (rel, idx), "setter": bool, "writes": [(rel, idx, new text)]}
    write_re_cache = {}

    def writes_of(var):
        """Every statement-level write to `var` in the tree as (rel, idx, new_text), or a code when one cannot be rewritten."""
        if var in write_re_cache:
            return write_re_cache[var]
        rewrites = []
        bad = None
        pat_any = re.compile(r"(?<![\w.])(?:(?:[\w]+(?:\[[^\]]*\])?\s*\.\s*)*)" + re.escape(var) + r"\s*(?:=(?!=)|\+=|-=|\|=|&=|\*=|/=|\^=|<<=|>>=|\+\+|--)")
        for rel, f in files.items():
            for i, l in enumerate(f.lines):
                if l is None or var not in l:
                    continue
                if not pat_any.search(strip_code(l)):
                    continue
                own = owner_of_line.get((rel, i))
                if own is None or own[0] != "proc":
                    continue  # a default in a type block, a macro row at column 0, a declaration
                code = strip_code(l, keep=True)
                stmt = code.strip()
                comment = l[len(code.rstrip()) :]
                indent = re.match(r"^[ \t]*", l).group(0)
                am = ASSIGN.match(stmt)
                im = INCDEC.match(stmt)
                m_ = am or im
                if not m_:
                    # the write is inside a larger statement (an if(...) var = x, a for header, a macro): not mechanical
                    if re.search(r"\b" + re.escape(var) + r"\s*(?:=(?!=)|\+=|-=|\|=|&=)", strip_code(l)):
                        bad = bad or "write_form"
                    continue
                lhs = m_.group("lhs").replace(" ", "")
                parts = lhs.split(".")
                if parts[-1] != var:
                    continue
                recv = ".".join(parts[:-1])
                if recv == "":
                    # a bare write: the holder's own var, unless the proc has a local or a parameter of that name, or the proc is not on a type that has the var
                    ptype, pname = own[1], own[2]
                    prm = [p.strip().split("/")[-1].split("=")[0].strip() for p in own[3].split(",") if p.strip()]
                    fb, lb = body_range(f.lines, next(k for k in range(i, -1, -1) if f.lines[k] is not None and f.lines[k][:1] not in (" ", "\t") and f.lines[k][:1] != ""))
                    body_vars = set(re.findall(r"\bvar/(?:[\w/]+/)?(\w+)", "\n".join(strip_code(x) for x in f.lines[fb : lb + 1] if x)))
                    if var in prm or var in body_vars:
                        continue
                    if own[2] in ("set_" + var,):
                        continue
                    if not any(ptype == u or ptype.startswith(u + "/") for (u, v) in var_decls if v == var):
                        continue
                    recv_text = ""
                elif recv == "src":
                    recv_text = ""
                else:
                    recv_text = recv + "."
                if own[2] == "set_" + var:
                    continue
                if am:
                    op = am.group("op")
                    rhs = am.group("rhs")
                    if op == "=":
                        new = "%sset_%s(%s)" % (recv_text, var, rhs)
                    else:
                        binop = op[:-1]
                        cur = "%s%s" % (recv_text, var)
                        new = "%sset_%s(%s %s %s)" % (recv_text, var, cur, binop, ("(%s)" % rhs) if re.search(r"[\s+\-*/|&<>=!?]", rhs) else rhs)
                else:
                    cur = "%s%s" % (recv_text, var)
                    new = "%sset_%s(%s %s 1)" % (recv_text, var, cur, "+" if im.group("op") == "++" else "-")
                rewrites.append((rel, i, indent + new + comment))
        write_re_cache[var] = (bad, rewrites)
        return write_re_cache[var]

    def plan_var(u, var):
        key = (u, var)
        if key in var_plan:
            return var_plan[key]
        res = {"ok": False, "why": None, "decl": None, "setter": False, "writes": []}
        var_plan[key] = res
        if (u, var) in tracked or any((a, var) in tracked and (u == a or u.startswith(a + "/")) for (a, _v) in list(tracked) if _v == var):
            res["ok"] = True
            res["why"] = "already"
            return res
        om = omfield.get((u, var))
        if om:
            # an OM_FIELD is not what the lints count as tracked: it becomes the var line plus TRACKED (its writes already go through set_<var>)
            for (r2, i2, ft) in macro_mentions.get(var, []):
                if (r2, i2) != (om[0], om[1]) and (ft is None or related(ft, u)):
                    res["why"] = "field_shared"
                    return res
            res["ok"] = True
            res["why"] = "om_field"
            res["om"] = om
            return res
        if var in BUILTIN_VARS:
            res["why"] = "builtin_var"
            return res
        owners = declaring_types[var]
        if any(o != u and not (o.startswith(u + "/")) for o in owners):
            res["why"] = "shared_name"
            return res
        decl = var_decls.get((u, var))
        if not decl or len(decl) != 1:
            res["why"] = "decl_shape"
            return res
        bad, rewrites = writes_of(var)
        if bad:
            res["why"] = bad
            return res
        res["ok"] = True
        res["decl"] = decl[0]
        res["setter"] = any(related(d[0], u) for d in procs_named.get("set_" + var, []))
        res["writes"] = rewrites
        return res

    if track:
        for t in list(plans):
            for var, u in plans[t]["reads"].items():
                r = plan_var(u, var)
                if not r["ok"]:
                    residue[t] = "var:%s:%s" % (r["why"], var)
                    del plans[t]
                    break

    converted = len(plans)
    if not check:
        done_vars = set()
        done_writes = set()
        for t, pl in plans.items():
            rel, i = pl["decl"]
            files[rel].lines[i] = None
            files[rel].dirty = True
            drel, di = pl["def"]
            f = files[drel]
            fb, lb = body_range(f.lines, di)
            f.lines[di] = re.sub(r"^(/[\w/]+?)/(?:proc/)?appearance_overlays\(\)", lambda m: m.group(1) + "/draw(datum/look/look)", f.lines[di])
            for k in range(fb, lb + 1):
                f.lines[k] = None
            f.lines[fb] = "\n".join(pl["body"]) if pl["body"] else None
            f.dirty = True
            if not track:
                continue
            for var, u in pl["reads"].items():
                r = var_plan.get((u, var))
                if not r or r["why"] == "already" or (u, var) in done_vars:
                    continue
                done_vars.add((u, var))
                if r["why"] == "om_field":
                    orel, oidx, ovt, odefault, och = r["om"]
                    macro = "TRACKED(%s, %s)" % (u, var) if och == "CHANGE_EXPLICIT" else "TRACKED_BRIDGED(%s, %s, %s)" % (u, var, och)
                    files[orel].lines[oidx] = "%s/var/%s%s = %s" % (u, (ovt + "/") if ovt else "", var, odefault) + chr(10) + macro
                    files[orel].dirty = True
                    continue
                drel2, didx = r["decl"]
                line = "SETTER(%s, %s)" % (u, var) if r["setter"] else "TRACKED(%s, %s)" % (u, var)
                df = files[drel2]
                owner = owner_of_line.get((drel2, didx))
                if df.lines[didx] and df.lines[didx][:1] not in (" ", "\t"):
                    df.lines[didx] = df.lines[didx] + "\n" + line
                else:
                    # inside a type block: the macro goes after the block
                    hdr = didx
                    while hdr >= 0 and (df.lines[hdr] is None or df.lines[hdr][:1] in (" ", "\t", "")):
                        hdr -= 1
                    bfb, blb = body_range(df.lines, hdr)
                    df.lines[blb] = df.lines[blb] + "\n" + line
                df.dirty = True
                for (wrel, widx, new) in r["writes"]:
                    if (wrel, widx) in done_writes:
                        continue
                    done_writes.add((wrel, widx))
                    files[wrel].lines[widx] = new
                    files[wrel].dirty = True
        for f in files.values():
            if f.dirty:
                f.save()
    by = defaultdict(list)
    for t, why in residue.items():
        by[why.split(":")[0] if why.startswith("var:") else why].append(t if not why.startswith("var:") else "%s (%s)" % (t, why[4:]))
    print("appearance_draw: %d procs converted%s; residue %d" % (converted, " (check)" if check else "", len(residue)))
    for why, ts in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print("    %-18s %4d" % (why, len(ts)))
        if sites:
            for t in sorted(ts):
                print("        " + t)
    n_tracked = len({k for k, r in var_plan.items() if r["ok"] and r["why"] != "already"}) if track else 0
    print("appearance_draw: %d vars tracked, %d writes rewritten" % (n_tracked, sum(len(r["writes"]) for k, r in var_plan.items() if r["ok"] and r["why"] != "already")) if track else "")
    return 1 if (check and plans) else 0


if __name__ == "__main__":
    sys.exit(main())
