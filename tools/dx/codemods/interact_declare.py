#!/usr/bin/env python3
r"""DECLARE_INTERACTIONS(T, INTERACT_USE / HAND / INSERT / ITEM ...) -> op(in_hand() / hand() / item(type)) entries
(doc/rewrite/codemod_rules.md, "DECLARE_INTERACTIONS").

    python tools/dx/codemods/interact_declare.py [--check] [--sites] [--only /type] [--files paths...]

One host type at a time. A type that does not match the rules exactly is residue with a code (--sites lists them). Idempotent. Run `analyze gen` afterwards.
"""
import os
import re
import subprocess
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ui_declare import File, SETTINGS, body_range, related, split_args, strip_code, words_in  # noqa: E402

SKIP = ("code/__defines/", "code/modules/unit_tests/", "code/tests/", "tools/", "code/modules/tgs/", "code/datums/interactions/")
KINDS = {"INTERACT_USE": "in_hand()", "INTERACT_HAND": "hand()", "INTERACT_ITEM": "item(/obj/item)", "INTERACT_INSERT": None}
HEAD = re.compile(r"^(DECLARE_INTERACTIONS|EXTEND_INTERACTIONS)\((/[\w/]+)\s*,")


def call_end(lines, i):
    """Index of the last line of the macro call that starts on line i (parentheses balanced, strings respected), or None."""
    depth = 0
    in_str = False
    j = i
    started = False
    while j < len(lines):
        l = lines[j]
        k = 0
        while k < len(l):
            c = l[k]
            if in_str:
                if c == chr(92):
                    k += 1
                elif c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
            elif c == "(":
                depth += 1
                started = True
            elif c == ")":
                depth -= 1
                if started and depth == 0:
                    return j
            k += 1
        j += 1
    return None


def call_text(lines, i, j):
    return " ".join(l.rstrip().rstrip(chr(92)).strip() for l in lines[i : j + 1])


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    sites = "--sites" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
        args = [a for a in args if a != only]
    if "--files" in sys.argv:
        names = args
    else:
        names = subprocess.check_output(["git", "ls-files", "-z", "*.dm"]).decode("utf-8", "surrogateescape").split("\0")
        names = [n for n in names if n and not n.startswith(SKIP)]
    files = {}
    code_lines = {}
    for rel in names:
        try:
            files[rel] = File(rel)
        except OSError:
            continue
    # ---- every legacy declaration, with the lines of its macro call
    decls = defaultdict(list)  # type -> [(kind, rel, first, last, text)]
    span_lines = set()
    for rel, f in files.items():
        for i, l in enumerate(f.lines):
            m = HEAD.match(l)
            if m:
                j = call_end(f.lines, i)
                if j is None:
                    continue
                decls[m.group(2)].append((m.group(1), rel, i, j, call_text(f.lines, i, j)))
                for k in range(i, j + 1):
                    span_lines.add((rel, k))
            m2 = re.match(r"^(/[\w/]+)/(?:proc/)?(declare_interactions|get_interactions)\(", l)
            if m2:
                fb2, lb2 = body_range(f.lines, i)
                adds = any("..(" in strip_code(x) for x in f.lines[fb2 : lb2 + 1])
                decls[m2.group(1)].append(("override_adds" if adds else "override", rel, i, i, l))
    types = set(decls)
    # A type that REPLACES what it inherits (DECLARE_INTERACTIONS, a get_interactions/declare_interactions override) cannot share a hierarchy with a
    # converted one: the ops accumulate down the tree and the replacement would stop meaning anything. EXTEND_INTERACTIONS only adds, so it never blocks.
    replacers = {u for u, rs in decls.items() if any(r[0] in ("DECLARE_INTERACTIONS", "override") for r in rs)}
    # the text other code sees: no macro-call lines, no UI rows, no definitions
    def_re = re.compile(r"^/[\w/]+/(proc/)?\w+\(")
    tree_lines = []
    mention_idx = defaultdict(set)  # identifier -> the types whose procs mention it (outside macro calls and definitions)
    tok = re.compile(r"(?<![\w./])[A-Za-z_]\w*")
    dre0 = re.compile(r"^(/[\w/]+?)/(?:proc/)?\w+\(")
    for rel, f in files.items():
        owner = ""
        for i, l in enumerate(f.lines):
            tree_lines.append(l)
            dm0 = dre0.match(l)
            if dm0:
                owner = dm0.group(1)
            if (rel, i) in span_lines or dm0:
                continue
            for w in tok.findall(strip_code(l)):
                mention_idx[w].add(owner)
    tree_text = "\n".join(tree_lines)
    defs_by_name = defaultdict(list)
    dre = re.compile(r"^(/[\w/]+?)/(?:proc/)?(\w+)\(([^)]*)\)\s*(//.*)?$")
    for rel, f in files.items():
        for i, l in enumerate(f.lines):
            if l and l[0] == "/":
                dm = dre.match(l)
                if dm:
                    defs_by_name[dm.group(2)].append((dm.group(1), rel, i, dm.group(3)))
    op_keys = set(re.findall(r'\bop\("([^"]+)"', tree_text))
    residue = {}
    plans = {}
    for t, rs in sorted(decls.items()):
        if only and t != only:
            continue
        if len(rs) != 1 or rs[0][0] != "DECLARE_INTERACTIONS":
            residue[t] = "interaction_forms"
            continue
        if any(related(t, u) for u in replacers if u != t):
            residue[t] = "interaction_related"
            continue
        kind0, rel, first, last, text = rs[0]
        inner_start = text.index("(") + 1
        inner = text[inner_start : text.rindex(")")]
        parts = split_args(inner)
        if not parts or parts[0] != t:
            residue[t] = "interaction_forms"
            continue
        specs = []
        bad = None
        for p in parts[1:]:
            if not p:
                continue
            m = re.match(r"^(INTERACT_[A-Z_]+)\((.*)\)$", p, re.S)
            if not m or m.group(1) not in KINDS:
                bad = "interaction_kind"
                break
            a = split_args(m.group(2))
            kind = m.group(1)
            if kind == "INTERACT_INSERT":
                if len(a) != 3:
                    bad = "requires" if len(a) > 3 else "interaction_forms"
                    break
                held_type, effect, name = a
            else:
                if len(a) != 2:
                    bad = "requires" if len(a) > 2 else "interaction_forms"
                    break
                name, effect = a
                held_type = None
            if name != "null" and not re.match(r'^"[^"\\]*"$', name):
                bad = "interaction_forms"
                break
            em = re.match(r"^(?:PROC_REF\((\w+)\)|TYPE_PROC_REF\(" + re.escape(t) + r",\s*(\w+)\))$", effect)
            if not em:
                bad = "effect_expr"
                break
            if held_type is not None and not re.match(r"^/[\w/]+$", held_type):
                bad = "interaction_forms"
                break
            specs.append({"kind": kind, "name": None if name == "null" else name, "proc": em.group(1) or em.group(2), "held": held_type})
        if bad:
            residue[t] = bad
            continue
        if not specs:
            residue[t] = "interaction_forms"
            continue
        if len({s["proc"] for s in specs}) != len(specs):
            residue[t] = "handler_shared"
            continue
        tre = re.escape(t)
        handlers = []
        for s in specs:
            hits = [(r, i, prm) for (ty, r, i, prm) in defs_by_name.get(s["proc"], []) if ty == t]
            others = [1 for (ty, r, i, prm) in defs_by_name.get(s["proc"], []) if ty != t and related(ty, t)]
            if len(hits) != 1:
                bad = "handler_shape"
                break
            if others or any((o == "" or related(o, t)) for o in mention_idx.get(s["proc"], ())):
                bad = "handler_shared"
                break
            drel, di, params = hits[0]
            ps = [p.strip() for p in params.split(",")]
            if len(ps) != 3 or any("=" in p for p in ps):
                bad = "handler_shape"
                break
            f = files[drel]
            fb, lb = body_range(f.lines, di)
            body_lines = f.lines[fb : lb + 1]
            body = "\n".join(strip_code(l) for l in body_lines)
            n_actor, n_held, n_inter = [p.split("/")[-1] for p in ps]
            if words_in(body, n_inter) or "INTERACTION_HANDLED_PASS" in body or re.search(r"\.\.\(", body) or words_in(body, "A"):
                bad = "body_uses"
                break
            if s["kind"] != "INTERACT_USE":
                # the old resolver let a falsy return fall through to the next candidate: only a handler that always returns TRUE keeps that
                ret_ok = True
                last_stmt = None
                for bl in body.split("\n"):
                    t2 = bl.strip()
                    if not t2:
                        continue
                    last_stmt = t2
                    rm = re.match(r"^return\b\s*(.*)$", t2)
                    if rm and rm.group(1).strip() != "TRUE":
                        ret_ok = False
                    if re.match(r"^\.\s*=", t2):
                        ret_ok = False
                if not ret_ok or last_stmt != "return TRUE":
                    bad = "handler_returns"
                    break
            held_type = "obj/item"
            if "/" in ps[1].replace("var/", ""):
                held_type = ps[1].replace("var/", "").rsplit("/", 1)[0]
            handlers.append({"spec": s, "rel": drel, "idx": di, "first": fb, "last": lb, "actor": n_actor, "held": n_held, "held_type": held_type, "body": body})
        if bad:
            residue[t] = bad
            continue
        # keys
        used = set()
        for h in handlers:
            proc = h["spec"]["proc"]
            key = re.sub(r"^interaction_", "", proc) or proc
            if key in used or key in op_keys:
                key = proc
            if key in used or key in op_keys:
                bad = "key_clash"
                break
            used.add(key)
            h["key"] = key
        if bad:
            residue[t] = bad
            continue
        plans[t] = {"type": t, "decl": rs[0], "handlers": handlers}
    converted_ops = sum(len(p["handlers"]) for p in plans.values())
    if not check:
        for t, plan in sorted(plans.items()):
            tre = re.escape(t)
            entries = []
            for h in plan["handlers"]:
                s = h["spec"]
                binding = s["held"] and "item(%s)" % s["held"] or KINDS[s["kind"]]
                parts = ['op("%s"' % h["key"], binding]
                if s["name"]:
                    parts.append("label(%s)" % s["name"])
                parts.append("then(PROC_REF(%s))" % s["proc"])
                entries.append(", ".join(parts) + ")")
                f = files[h["rel"]]
                sig = t + "/proc/" + s["proc"] + "(datum/act/op/A)"
                locals_ = []
                if words_in(h["body"], h["actor"]):
                    locals_.append("var/mob/%s = A.actor" % h["actor"])
                if words_in(h["body"], h["held"]):
                    locals_.append("var/%s/%s = A.held" % (h["held_type"], h["held"]))
                extra = ""
                if locals_:
                    after = h["idx"]
                    k = h["first"]
                    while k <= h["last"]:
                        st = strip_code(f.lines[k]).strip()
                        if st == "":
                            k += 1
                            continue
                        if st.startswith(SETTINGS) and (("(" not in st) or st.endswith(")")):
                            after = k
                            k += 1
                            continue
                        break
                    indent = "\t"
                    for k2 in range(h["first"], h["last"] + 1):
                        if f.lines[k2].strip():
                            indent = re.match(r"^[ \t]*", f.lines[k2]).group(0)
                            break
                    block = "".join("\n" + indent + l for l in locals_)
                    if after == h["idx"]:
                        extra = block
                    else:
                        f.lines[after] = f.lines[after] + block
                f.lines[h["idx"]] = sig + extra
                f.dirty = True
            kind0, rel, first, last, text = plan["decl"]
            f = files[rel]
            block_at = None
            for r2, f2 in files.items():
                for i2, l2 in enumerate(f2.lines):
                    if l2 is not None and re.match(r"^CAPABILITIES\(" + tre + r"\)\s*(//.*)?$", l2):
                        block_at = (r2, i2)
            for k in range(first, last + 1):
                f.lines[k] = None
            if block_at:
                br, bi = block_at
                bf = files[br]
                fb, lb = body_range(bf.lines, bi)
                bf.lines[lb] = bf.lines[lb] + "".join("\n\t" + e for e in entries)
                bf.dirty = True
            else:
                f.lines[first] = "CAPABILITIES(%s)" % t + "".join("\n\t" + e for e in entries)
            f.dirty = True
        for f in files.values():
            if f.dirty:
                f.save()
    by = defaultdict(list)
    for t, why in residue.items():
        by[why].append(t)
    print("interact_declare: %d types converted (%d ops)%s; residue %d types" % (len(plans), converted_ops, " (check)" if check else "", len(residue)))
    for why, ts in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print("    %-20s %4d" % (why, len(ts)))
        if sites:
            for t in sorted(ts):
                print("        " + t)
    return 1 if (check and plans) else 0


if __name__ == "__main__":
    sys.exit(main())
