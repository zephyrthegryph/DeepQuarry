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
from ui_declare import File, SETTINGS, body_range, collect_vars, holder_vars_of, related, split_args, strip_code, words_in  # noqa: E402

# Questions at the head of a handler (rerun_ask) become asks() steps of the op (leading_asks.py, codemod_rules.md "rerun_ask and act_ask -> asks()").
# --asks / --no-asks override the default.
ASKS_DEFAULT = True
LA = None

TEST_DIRS = ("code/modules/unit_tests/", "code/tests/")
SKIP = ("code/__defines/", "code/modules/unit_tests/", "code/tests/", "tools/", "code/modules/tgs/", "code/datums/interactions/")
# The base shape of each compact spec, as the engine reads it (code/datums/interactions/compact.dm): the binding and the parts the op needs beside it.
#   in_hand() / hand() / item(T) / menu() as before; ALT is a hand() pinned to the alt-click gesture and never behind the hand gate (the old click_alt ran
#   no hand_gate()), DRAG an item() of the dragged thing's type pinned to the drag gesture (the dragged atom is A.held), TK a tk() binding.
KINDS = {
    "USE": "in_hand()",
    "SELF": "in_hand()",
    "HAND": "hand()",
    "HAND_UNGATED": "hand()",
    "ITEM": "item(/obj/item)",
    "INSERT": None,
    "VERB": "menu()",
    "ALT": "hand()",
    "DRAG": "item(/atom/movable)",
    "TK": "tk()",
}
# the macro's own name: INTERACT_<BASE><suffix>; _AS takes the stance as its first argument, _HOSTILE and _PEACEFUL fix it, _DEFAULT is the type's default for
# the input (tried after everything else it offers)
SPEC_NAME = re.compile(r"^INTERACT_(USE|SELF|HAND_UNGATED|HAND|ITEM|INSERT|DRAG|ALT|TK|VERB)(_AS|_HOSTILE|_PEACEFUL|_DEFAULT_AS|_DEFAULT)?$")
STANCE_LITERAL = re.compile(r"^I_(HELP|DISARM|GRAB|HURT)$")
FALLS_THROUGH = ("USE", "VERB")  # an effect whose return is ignored (always handled): every other kind falls through to the next candidate on a falsy return
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


def call_inner(text):
    """The text between the parentheses of the call that `text` starts with (an `op(` at its start), or None."""
    depth = 0
    in_str = False
    start = text.index("(")
    k = start
    while k < len(text):
        c = text[k]
        if in_str:
            if c == chr(92):
                k += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return (text[start + 1 : k], text[k + 1 :])
        k += 1
    return None


def binding_of(spec, h):
    """The binding text and the pinned gesture (or None) of one spec."""
    kind = spec["kind"]
    if spec["held"]:
        return "item(%s)" % spec["held"], None
    if kind == "DRAG":
        return "item(/%s)" % h["held_type"], "GESTURE_DRAG"
    if kind == "ALT":
        return KINDS[kind], "GESTURE_ALT"
    return KINDS[kind], None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    global LA
    check = "--check" in sys.argv
    sites = "--sites" in sys.argv
    asks_on = ("--no-asks" not in sys.argv) and (ASKS_DEFAULT or "--asks" in sys.argv)
    if asks_on:
        import leading_asks as LA_module  # noqa: E402

        LA = LA_module
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
        args = [a for a in args if a != only]
    tested = set()
    if "--files" in sys.argv:
        names = args
    else:
        names = subprocess.check_output(["git", "ls-files", "-z", "*.dm"]).decode("utf-8", "surrogateescape").split("\0")
        # a handler a unit test calls by name (the legacy signature: user, held, interaction) cannot change shape under it: the type is left to a hand conversion
        # that rewrites the test (residue handler_tested)
        for n in names:
            if n.startswith(TEST_DIRS) and n.endswith(".dm"):
                try:
                    tested.update(re.findall(r"[A-Za-z_]\w*", open(n, encoding="utf-8", errors="surrogateescape").read()))
                except OSError:
                    pass
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
    override_replacers = {u for u, rs in decls.items() if any(r[0] == "override" for r in rs)}
    # the text other code sees: no macro-call lines, no UI rows, no definitions
    def_re = re.compile(r"^/[\w/]+/(proc/)?\w+\(")
    tree_lines = []
    vars_by_type = collect_vars(files)
    # The ops the CAPABILITIES blocks already declare, per type: (binding, gesture) of each. A converted op that takes the same input as one of a related
    # type's would clash with it (ops accumulate down the tree), so the type is left to a hand conversion that orders them.
    ops_by_type = defaultdict(list)
    cap_head = re.compile(r"^CAPABILITIES\((/[\w/]+)\)")
    for rel, f in files.items():
        i = 0
        while i < len(f.lines):
            cm = cap_head.match(f.lines[i] or "")
            i += 1
            if not cm:
                continue
            block = []
            while i < len(f.lines) and (f.lines[i] is None or f.lines[i][:1] in (chr(9), " ") or f.lines[i] == ""):
                block.append(f.lines[i] or "")
                i += 1
            text = chr(10).join(block)
            for om in re.finditer(r'\bop\("[^"]+",', text):
                got = call_inner(text[om.start() :])
                if not got:
                    continue
                parts = split_args(got[0])
                binding = next((p for p in parts[1:] if re.match(r"^(in_hand|hand|tk|item|tool|stack|at_target|inside|remote|clicks|inputs|any_of_tools)\(", p)), None)
                gesture = next((p for p in parts[1:] if p.startswith("gesture(")), None)
                if binding:
                    ops_by_type[cm.group(1)].append((binding, gesture))
    mention_count = defaultdict(int)  # (identifier, owner type) -> how many lines of that owner's procs mention it
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
                mention_count[(w, owner)] += 1
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
        if len(rs) != 1:
            residue[t] = "interaction_forms"
            continue
        # DECLARE_INTERACTIONS replaces only the specs list (get_interactions) of its ancestors; an EXTEND_INTERACTIONS chain (declare_interactions
        # calling ..()) still reaches every descendant. So an EXTEND conflicts only with a descendant whose declare_interactions override drops the
        # chain (no ..()): ops would flow into it. A DECLARE conflicts with any related replacer: converted, it would inherit what it replaced.
        if rs[0][0] == "EXTEND_INTERACTIONS":
            if any(u != t and u.startswith(t + "/") for u in override_replacers):
                residue[t] = "interaction_related"
                continue
        elif any(related(t, u) for u in replacers if u != t):
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
            nm = SPEC_NAME.match(m.group(1)) if m else None
            if not nm:
                bad = "interaction_kind"
                break
            a = split_args(m.group(2))
            kind = nm.group(1)
            suffix = nm.group(2) or ""
            stance = None
            if suffix in ("_AS", "_DEFAULT_AS"):
                if not a or not STANCE_LITERAL.match(a[0]):
                    bad = "interaction_forms"
                    break
                stance, a = a[0], a[1:]
            elif suffix == "_HOSTILE":
                stance = "I_HURT"
            elif suffix == "_PEACEFUL":
                stance = "I_HELP"
            if kind == "INSERT":
                if len(a) != 3:
                    bad = "requires" if len(a) > 3 else "interaction_forms"
                    break
                held_type, effect, name = a
            else:
                carried = False
                if kind == "VERB" and len(a) == 3 and a[2] == "REQ_IN_INVENTORY":
                    a = a[:2]
                    carried = True
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
            specs.append({"kind": kind, "name": None if name == "null" else name, "proc": em.group(1) or em.group(2), "held": held_type, "carried": kind != "INSERT" and carried, "stance": stance, "default": suffix.startswith("_DEFAULT")})
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
            drel, di, params = hits[0]
            ps = [p.strip() for p in params.split(",")]
            if len(ps) != 3 or any("=" in p for p in ps):
                bad = "handler_shape"
                break
            f = files[drel]
            fb, lb = body_range(f.lines, di)
            body_lines = f.lines[fb : lb + 1]
            n_actor, n_held, n_inter = [p.split("/")[-1] for p in ps]
            # Questions at the head of the handler (a re-run: rerun_ask) become asks() steps of the op (leading_asks.py). The re-run's own call names the handler,
            # which is not another caller.
            asks = []
            if asks_on and any(LA.ASK_CALL.search(strip_code(l)) for l in body_lines):
                asks, why_ask = LA.parse_leading(f.lines, fb, lb, s["proc"], n_actor, ("rerun_ask",))
                if asks is None:
                    bad = why_ask
                    break
                if not asks:
                    bad = "ask_not_first"
                    break
                body_lines = LA.edited_lines(f.lines, fb, lb, asks)
                if any(LA.ASK_CALL.search(strip_code(l)) for l in body_lines):
                    bad = "ask_later"
                    break
            self_mentions = sum(len(words_in(strip_code(f.lines[k]), s["proc"])) for a in asks for k in a["remove"])
            outside = sum(mention_count[(s["proc"], o)] for o in mention_idx.get(s["proc"], ()) if o == "" or related(o, t))
            if others or outside - self_mentions > 0:
                bad = "handler_shared"
                break
            if s["proc"] in tested:
                bad = "handler_tested"
                break
            body = "\n".join(strip_code(l) for l in body_lines)
            # INTERACTION_HANDLED_PASS (handled, the input not used up) is read only as a return value: `return OP_PASS`; any other use of it is residue
            stray_pass = re.sub(r"\breturn\s+INTERACTION_HANDLED_PASS\b", "", body)
            if words_in(body, n_inter) or "INTERACTION_HANDLED_PASS" in stray_pass or re.search(r"\.\.\(", body) or words_in(body, "A"):
                bad = "body_uses"
                break
            if s["kind"] == "VERB" and words_in(body, n_held):
                bad = "body_uses"
                break
            if s["kind"] not in FALLS_THROUGH and not asks:
                # the old resolver let a falsy return fall through to the next candidate: a falsy return (FALSE, 0, null, bare) becomes OP_DECLINE, which the
                # op engine reads the same way; the handler must end on a return so a fall-off-the-end (falsy then, truthy now) cannot change meaning
                ret_ok = True
                last_stmt = None
                for bl in body.split("\n"):
                    t2 = bl.strip()
                    if not t2:
                        continue
                    last_stmt = t2
                    for rm in re.finditer(r"\breturn\b(.*)$", t2):
                        if rm.group(1).strip() not in ("", "TRUE", "FALSE", "0", "null", "INTERACTION_HANDLED_PASS"):
                            ret_ok = False
                    if re.match(r"^\.\s*=", t2):
                        ret_ok = False
                if not ret_ok or not re.match(r"^return\b", last_stmt or ""):
                    bad = "handler_returns"
                    break
            held_type = "obj/item"
            if s["kind"] == "DRAG":
                held_type = "atom/movable"
            if "/" in ps[1].replace("var/", ""):
                held_type = ps[1].replace("var/", "").rsplit("/", 1)[0]
            actor_type = "mob"
            if "/" in ps[0].replace("var/", ""):
                actor_type = ps[0].replace("var/", "").rsplit("/", 1)[0]
            handlers.append({"actor_type": actor_type, "spec": s, "rel": drel, "idx": di, "first": fb, "last": lb, "actor": n_actor, "held": n_held, "held_type": held_type, "body": body, "asks": asks})
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
        # the questions: each one's asks() part, and the helper procs its computed fields need
        holder_vars = holder_vars_of(vars_by_type, t)
        for h in handlers:
            h["ask_parts"] = []
            h["helpers"] = []
            for a in h["asks"]:
                text, helpers, why_ask = LA.build_ask(a, holder_vars, "%s_%s" % (h["spec"]["proc"], a["key"]), t, h["actor"], h["held"])
                if why_ask:
                    bad = why_ask
                    break
                for hp in helpers:
                    hname = re.match(r"^/[\w/]+/proc/(\w+)\(", hp).group(1)
                    if defs_by_name.get(hname) or re.search(r"\b" + hname + r"\b", tree_text):
                        bad = "name_clash"
                        break
                if bad:
                    break
                h["ask_parts"].append(text)
                h["helpers"] += helpers
            if bad:
                break
        if bad:
            residue[t] = bad
            continue
        for h in handlers:
            if h["spec"]["kind"] == "VERB" or h["spec"]["default"]:
                continue
            b0, g0 = binding_of(h["spec"], h)
            g0 = ("gesture(%s)" % g0) if g0 else None
            for u, ops in ops_by_type.items():
                if u != t and related(u, t) and any(b == b0 and g == g0 for b, g in ops):
                    bad = "interaction_clash"
        if bad:
            residue[t] = bad
            continue
        # two ops of one type that take the same input at the same tier for a stance in common are a build error (the clash rule); the old resolver took the
        # first one meant and fell through on a falsy return, so the order is the declaration's, which the engine keeps, but the pair has to say so by hand
        sigs = {}
        for h in handlers:
            sp = h["spec"]
            h["binding"], h["gesture"] = binding_of(sp, h)
            if sp["kind"] == "VERB":
                continue  # menu() ops are chosen by key, and keys are unique: they never clash
            sig = (h["binding"], h["gesture"], sp["default"])
            overlap = sigs.setdefault(sig, [])
            if any(o is None or sp["stance"] is None or o == sp["stance"] for o in overlap):
                bad = "interaction_overlap"
                break
            overlap.append(sp["stance"])
        if bad:
            residue[t] = bad
            continue
        plans[t] = {"type": t, "decl": rs[0], "handlers": handlers}
    # Ops of related types accumulate down the tree: two types of one hierarchy that both convert an op for the same input would clash in the descendant's
    # table, so the descendant stays (an ancestor's converted op beside a descendant's legacy entry resolves together at run time).
    claimed = defaultdict(list)  # (binding, gesture) -> the converted types that hold it
    for t in sorted(plans, key=lambda x: (x.count("/"), x)):
        mine = set()
        for h in plans[t]["handlers"]:
            if h["spec"]["kind"] == "VERB" or h["spec"]["default"]:
                continue
            key = (h["binding"], h["gesture"])
            mine.add(key)
            if any(related(u, t) for u in claimed.get(key, [])):
                residue[t] = "interaction_clash"
                break
        if residue.get(t) == "interaction_clash":
            del plans[t]
            continue
        for key in mine:
            claimed[key].append(t)
    converted_ops = sum(len(p["handlers"]) for p in plans.values())
    if not check:
        for t, plan in sorted(plans.items()):
            tre = re.escape(t)
            entries = []
            for h in plan["handlers"]:
                s = h["spec"]
                parts = ['op("%s"' % h["key"], h["binding"]]
                if s["kind"] in ("HAND_UNGATED", "ALT"):
                    parts.append("ungated()")
                if h["gesture"]:
                    parts.append("gesture(%s)" % h["gesture"])
                if s["stance"]:
                    parts.append("stance(%s)" % s["stance"])
                if s["default"]:
                    parts.append("priority(OP_PRIORITY_DEFAULT)")
                if s["name"]:
                    parts.append("label(%s)" % s["name"])
                if s.get("carried"):
                    parts.append("needs(carried())")
                parts += h["ask_parts"]
                parts.append("then(PROC_REF(%s))" % s["proc"])
                entries.append(", ".join(parts) + ")")
                f = files[h["rel"]]
                sig = t + "/proc/" + s["proc"] + "(datum/act/op/A)"
                if h["helpers"]:
                    sig = "\n\n".join(h["helpers"]) + "\n\n" + sig
                # the questions' statements and guards go; what they returned is a local read from the answered step
                for a in h["asks"]:
                    for k in a["remove"]:
                        f.lines[k] = None
                    for k, txt in a["rewrite"].items():
                        f.lines[k] = txt
                locals_ = []
                if words_in(h["body"], h["actor"]):
                    locals_.append("var/%s/%s = A.actor" % (h["actor_type"], h["actor"]))
                if words_in(h["body"], h["held"]):
                    locals_.append("var/%s/%s = A.held" % (h["held_type"], h["held"]))
                for a in h["asks"]:
                    if words_in(h["body"], a["name"]):
                        locals_.append(LA.answer_local(a))
                extra = ""
                if locals_:
                    after = h["idx"]
                    k = h["first"]
                    while k <= h["last"]:
                        st = strip_code(f.lines[k] or "").strip()
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
                        if f.lines[k2] and f.lines[k2].strip():
                            indent = re.match(r"^[ \t]*", f.lines[k2]).group(0)
                            break
                    block = "".join("\n" + indent + l for l in locals_)
                    if after == h["idx"]:
                        extra = block
                    else:
                        f.lines[after] = f.lines[after] + block
                for k3 in range(h["first"], h["last"] + 1):
                    if f.lines[k3] is None:
                        continue
                    if s["kind"] not in FALLS_THROUGH and not h["asks"]:
                        f.lines[k3] = re.sub(r"\breturn\b(?:\s+(?:FALSE|0|null))?(?=\s*(?://.*)?$)", "return OP_DECLINE", f.lines[k3])
                    f.lines[k3] = re.sub(r"\breturn\s+INTERACTION_HANDLED_PASS\b", "return OP_PASS", f.lines[k3])
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
    if "--why" in sys.argv:
        for t, why in sorted(residue.items()):
            print("WHY	%s	%s	%s" % (why, t, " ; ".join(r[0][:3] + ":" + r[4][:110] for r in decls[t])))
    for why, ts in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print("    %-20s %4d" % (why, len(ts)))
        if sites:
            for t in sorted(ts):
                print("        " + t)
    return 1 if (check and plans) else 0


if __name__ == "__main__":
    sys.exit(main())
