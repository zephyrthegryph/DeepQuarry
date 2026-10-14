#!/usr/bin/env python3
r"""DECLARE_INTERACTIONS(T, INTERACT_USE / HAND / INSERT / ITEM ...) -> op(in_hand() / hand() / item(type)) entries
(doc/rewrite/codemod_rules.md, "DECLARE_INTERACTIONS").

    python tools/dx/codemods/interact_declare.py [--check] [--sites] [--only /type] [--files paths...]

One host type at a time. A type that does not match the rules exactly is residue with a code (--sites lists them). Idempotent. Run `analyze gen` afterwards.
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import os
import re
import subprocess
import sys
from collections import defaultdict

# the hand-conversion list of the items/structures wave (tools/codemods/exclusions.txt, "interact" lines)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "codemods"))
from _excl import excluded  # noqa: E402

EXCLUDED = excluded("interact")

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
    # a silicon's use (the old attack_ai/attack_robot adapter): the interface binding, reach as far as the silicon sees
    "SILICON": "remote()",
    "ROBOT": "remote()",
}
# the macro's own name: INTERACT_<BASE><suffix>; _AS takes the stance as its first argument, _HOSTILE and _PEACEFUL fix it, _DEFAULT is the type's default for
# the input (tried after everything else it offers)
SPEC_NAME = re.compile(r"^INTERACT_(USE|SELF|HAND_UNGATED|HAND|ITEM|INSERT|DRAG|ALT|TK|VERB|SILICON|ROBOT)(_AS|_HOSTILE|_PEACEFUL|_DEFAULT_AS|_DEFAULT)?$")
STANCE_LITERAL = re.compile(r"^I_(HELP|DISARM|GRAB|HURT)$")
FALLS_THROUGH = ("USE", "VERB")
# the shared effects with a shared op handler (code/datums/interactions/shared_effects.dm: interaction_<name> -> op_<name>)
SHARED_OPS = {"open_ui", "open_ui_fingerprint", "open_ui_powered", "open_ui_powered_fingerprint", "interact", "swallow", "as_touch", "fingerprint", "part_replacement"}  # an effect whose return is ignored (always handled): every other kind falls through to the next candidate on a falsy return
HEAD = re.compile(r"^(DECLARE_INTERACTIONS|EXTEND_INTERACTIONS)\((/[\w/]+)\s*,")


REQ_PROC_CLAUSE = re.compile(r"^(?:REQ_TARGET_STATE\((/[\w/]+?)/proc/(\w+)\)|REQ_ON\(PRED_TARGET,\s*(/[\w/]+?)/proc/(\w+),\s*(\"[^\"\\]*\"|null)\)|REQ_PROC\(/proc/(\w+),\s*(\"[^\"\\]*\"|null)\))$")
REQ_FIELD_CLAUSE = re.compile(r"^(?:REQ_BECAUSE\()?REQ_FIELD(_NOT)?\(\"(\w+)\"\)(?:,\s*(\"[^\"\\]*\")\))?$")


def translate_req(clause, t, kind):
    """One legacy requirement clause of a spec -> (the needs() part, [helper proc texts]); None when it has no translation (residue `requires`).

    The old clause procs take (actor, target, held) and answer TRUE to pass, or FALSE / a text reason to refuse (code/datums/properties/predicates.dm);
    the op's requirement is a pure `x(datum/act/op/A)` answering TRUE/FALSE with a reason proc beside it, so each proc gets two thin wrappers that call it
    as the old evaluator did (the target is the holder: src)."""
    clause = clause.strip()
    # a datum interaction's offered_when (tools/codemods/interaction_datums.py): the op is not offered unless it holds -> when(), no refusal
    om = re.match(r"^OFFERED_WHEN\((.*)\)$", clause, re.S)
    if om:
        inner = om.group(1).strip()
        am = re.match(r"^REQ_ON\(PRED_ACTOR,\s*(/[\w/]+?)/proc/(\w+),\s*(\"[^\"\\]*\"|null)\)$", inner)
        if am:  # a proc of the type, asked of the actor
            inner = "REQ_ON(PRED_TARGET, %s/proc/%s, %s)" % (am.group(1), am.group(2), am.group(3))
        got = translate_req(inner, t, kind)
        if got is None or not got[0].startswith("req(PROC_REF("):
            return None
        holds = re.match(r"^req\(PROC_REF\((\w+)\)", got[0]).group(1)
        return ("@when req(PROC_REF(%s))" % holds, got[1][:1])  # only the holds wrapper: nothing refuses
    if clause in ("REQ_INTERACTION_REACH", "REQ_SELF_USE_REACH"):
        return ("", [])  # the binding's own reach (hand() / in_hand())
    if clause == "REQ_REACH_ADJACENT":
        return ("req_adjacent()", [])
    fm = REQ_FIELD_CLAUSE.match(clause)
    if fm:
        value = "FALSE" if fm.group(1) else "TRUE"
        if not fm.group(3):
            return ("req_is(nameof(%s), %s, because = /datum/msg/req_failed)" % (fm.group(2), value), [])  # a req_is needs a reason
        # a reason is a message type, never text (a text `because` is read as a proc name)
        text = fm.group(3).strip('"')
        msg = "%s/%s" % (t.split("/")[-1], fm.group(2))
        sentence = text[:1].upper() + text[1:] + ("" if text.endswith((".", "!", "?")) else ".")
        return ("req_is(nameof(%s), %s, because = MSG(%s))" % (fm.group(2), value, msg), ['MSG_DEF_SELF(%s, "%s")' % (msg, sentence)])
    pm = REQ_PROC_CLAUSE.match(clause)
    if not pm:
        return None
    if pm.group(2):
        owner, proc, fallback, call = pm.group(1), pm.group(2), "null", "%s(A.actor, src, A.held)" % pm.group(2)
    elif pm.group(4):
        owner, proc, fallback, call = pm.group(3), pm.group(4), pm.group(5), "%s(A.actor, src, A.held)" % pm.group(4)
    else:
        owner, proc, fallback, call = None, pm.group(6), pm.group(7), "%s(A.actor, src, A.held)" % pm.group(6)
    if owner and not (owner == t or t.startswith(owner + "/")):
        return None
    holds = "%s_holds" % proc
    why = "%s_refusal" % proc
    reason = fallback if fallback != "null" else "/datum/msg/req_failed"
    helpers = [
        "/// Requirement (was REQ_* %s): the legacy check answers TRUE to pass.\n%s/proc/%s(datum/act/op/A)\n\tvar/answer = %s\n\treturn !istext(answer) && !!answer" % (proc, t, holds, call),
        "/// Why %s refuses: the legacy check's text, else the clause's own reason.\n%s/proc/%s(datum/act/op/A)\n\tvar/answer = %s\n\treturn istext(answer) ? answer : %s" % (holds, t, why, call, reason),
    ]
    return ("req(PROC_REF(%s), because = PROC_REF(%s))" % (holds, why), helpers)


CONVERTED_NAMES = {"item": "Use", "hand": "Use", "self": "Use", "alt": "Alternate use", "drag": "Drop onto"}


def legacy_name(spec, vars_by_type):
    """dq_interaction_name_from_effect() / dq_interaction_insert_name() of a spec with a null name, or None when it cannot be known here."""
    if spec["kind"] == "INSERT":
        held = spec["held"]
        parts = held.split("/")
        name = None
        for n in range(len(parts), 1, -1):
            v = vars_by_type.get("/".join(parts[:n]))
            if v:
                name = v
                break
        if not name:
            return None
        name = name.strip().strip('"')
        if "\\" in name or "[" in name:
            return None
        article = "an" if name[:1].lower() in "aeiou" else "a"
        return "Insert %s %s" % (article, name)
    tail = spec["proc"]
    marker = tail.rfind("interaction_")
    if marker != -1 and (marker == 0 or tail[marker - 1] == "_"):
        conv = CONVERTED_NAMES.get(tail[marker + len("interaction_") :])
        if conv:
            return conv
    tail = tail.replace("_", " ")
    return tail[:1].upper() + tail[1:]


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
    tested_calls = defaultdict(set)  # handler name -> the receiver types a unit test calls it on (None: unknown)
    tested_sites = defaultdict(list)
    test_rewrites = []
    if "--files" in sys.argv:
        names = args
    else:
        names = subprocess.check_output(["git", "ls-files", "-z", "*.dm"]).decode("utf-8", "surrogateescape").split("\0")
        # a handler a unit test calls by name (the legacy signature: user, held, interaction) cannot change shape under it: the type is left to a hand conversion
        # that rewrites the test (residue handler_tested)
        # A call is attributed to the receiver's declared type (`var/T/x` or a `T/x` parameter above it); an unresolved receiver or a name in a
        # string (hascall(M, "name")) could be anything and counts for every type.
        for n in names:
            if n.startswith(TEST_DIRS) and n.endswith(".dm"):
                try:
                    tlines = open(n, encoding="utf-8", errors="surrogateescape").read().splitlines()
                except OSError:
                    continue
                for ti, tl in enumerate(tlines):
                    for cm in re.finditer(r"\b(\w+)\s*\.\s*(\w+)\s*\(", tl):
                        recv, pname = cm.group(1), cm.group(2)
                        rtype = None
                        for k in range(ti, max(-1, ti - 200), -1):
                            vm = re.search(r"(?:var/|[(,]\s*)(/?[\w/]+)/" + re.escape(recv) + r"\b", tlines[k])
                            if vm:
                                rtype = "/" + vm.group(1).lstrip("/")
                                break
                        tested_calls[pname].add(rtype)
                        tested_sites[pname].append("%s:%d" % (n, ti + 1))
                    for sm in re.finditer(r'(?:\b\w+\((\w+),\s*)?"(\w+)"', tl):
                        recv, pname = sm.group(1), sm.group(2)
                        rtype = None
                        for k in range(ti, max(-1, ti - 200), -1) if recv else ():
                            vm = re.search(r"(?:var/|[(,]\s*)(/?[\w/]+)/" + re.escape(recv) + r"\b", tlines[k])
                            if vm:
                                rtype = "/" + vm.group(1).lstrip("/")
                                break
                        tested_calls[pname].add(rtype)
                        tested_sites[pname].append("%s:%d" % (n, ti + 1))
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
    # type -> its `name = "..."` (the insert names the legacy menu derived from the held type)
    type_names = {}
    for _f in files.values():
        _cur = None
        for _l in _f.lines:
            if not _l:
                continue
            if _l[0] == "/":
                _hm = re.match(r"^(/[\w/]+)\s*(//.*)?$", _l)
                _cur = _hm.group(1) if _hm else None
            elif _cur and _l.startswith(chr(9) + "name = "):
                _nm = re.match(r'^	name = "([^"]*)"', _l)
                if _nm:
                    type_names.setdefault(_cur, _nm.group(1))
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
    # A type-level line names its own type's procs: the entries of a CAPABILITIES(T) block, and a macro whose first
    # argument is the type (DECLARE_EMAG(T, PROC_REF(x)), DAMAGE_REACTION(T, ...)) mention x of T, not of any type.
    cap_owner = re.compile(r"^(?:CAPABILITIES|STATE_GRAPH)\((/[\w/]+)\)")
    macro_owner = re.compile(r"^[A-Z][A-Z0-9_]+\((/[\w/]+)\s*[,)]")
    for rel, f in files.items():
        if rel.replace("\\", "/").startswith("tools/"):
            continue  # codemod fixtures are not the tree
        owner = ""
        block_owner = None
        for i, l in enumerate(f.lines):
            tree_lines.append(l)
            dm0 = dre0.match(l)
            if dm0:
                owner = dm0.group(1)
                block_owner = None
            line_owner = owner
            if l and l[0] not in "\t /":
                block_owner = None
            cm0 = cap_owner.match(l or "")
            if cm0:
                block_owner = cm0.group(1)
            mm0 = macro_owner.match(l or "")
            if block_owner and (cm0 or (l and l[0] in "\t ")):
                line_owner = block_owner
            elif mm0 and not cm0:
                line_owner = mm0.group(1)
            if (rel, i) in span_lines or dm0:
                continue
            for w in tok.findall(strip_code(l)):
                mention_idx[w].add(line_owner)
                mention_count[(w, line_owner)] += 1
    tree_text = "\n".join(tree_lines)
    # a handler called on a receiver (`jets.toggle_rockets_effect(wearer)` from a rig module) is called from outside, whatever the caller's type
    qualified_calls = set(re.findall(r"\.\s*(\w+)\s*\(", "\n".join(strip_code(l) for l in tree_lines if l)))
    defs_by_name = defaultdict(list)
    dre = re.compile(r"^(/[\w/]+?)/(?:proc/)?(\w+)\(([^)]*)\)\s*(//.*)?$")
    for rel, f in files.items():
        for i, l in enumerate(f.lines):
            if l and l[0] == "/":
                dm = dre.match(l)
                if dm:
                    defs_by_name[dm.group(2)].append((dm.group(1), rel, i, dm.group(3)))
    # op keys by the type whose CAPABILITIES block declares them: a key must be unique in a type tree, not in the world
    op_keys_by_type = defaultdict(set)
    for _rel, _f in files.items():
        _owner = None
        for _l in _f.lines:
            _cm = re.match(r"^CAPABILITIES\((/[\w/]+)\)", _l or "")
            if _cm:
                _owner = _cm.group(1)
                continue
            if _l and _l[0] not in "\t ":
                _owner = None
            if _owner:
                for _k in re.findall(r'\bop\("([^"]+)"', _l or ""):
                    op_keys_by_type[_owner].add(_k)

    def key_taken(key, t):
        # the type, its ancestors (path prefixes) and its descendants
        parts = t.split("/")
        for n in range(2, len(parts) + 1):
            if key in op_keys_by_type.get("/".join(parts[:n]), ()):
                return True
        return any(key in ks for u, ks in op_keys_by_type.items() if u.startswith(t + "/"))
    residue = {}
    plans = {}
    for t, rs in sorted(decls.items()):
        if only and t != only:
            continue
        if t in EXCLUDED:
            residue[t] = "excluded"
            continue
        extra_decls = []
        # a DECLARE and an EXTEND on the same type: both lists reached the type (get_interactions and the declare chain), so the ops are both
        # lists' specs; the DECLARE's replacement rule decides the conflicts
        if len(rs) == 2 and sorted(r[0] for r in rs) == ["DECLARE_INTERACTIONS", "EXTEND_INTERACTIONS"]:
            dec = next(r for r in rs if r[0] == "DECLARE_INTERACTIONS")
            ext = next(r for r in rs if r[0] == "EXTEND_INTERACTIONS")
            d_inner = dec[4][dec[4].index("(") + 1 : dec[4].rindex(")")]
            e_parts = split_args(ext[4][ext[4].index("(") + 1 : ext[4].rindex(")")])
            merged = d_inner.rstrip().rstrip(",") + ", " + ", ".join(x for x in e_parts[1:] if x)
            rs = [(dec[0], dec[1], dec[2], dec[3], "DECLARE_INTERACTIONS(" + merged + ")")]
            extra_decls = [ext]
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
            carried = False
            req_parts, req_helpers = [], []
            if kind == "INSERT":
                if len(a) < 3:
                    bad = "interaction_forms"
                    break
                held_type, effect, name = a[:3]
                extra = a[3:]
            else:
                if len(a) < 2:
                    bad = "interaction_forms"
                    break
                name, effect = a[:2]
                extra = a[2:]
                held_type = None
            for clause in extra:
                if clause == "REQ_IN_INVENTORY":
                    carried = True
                    continue
                got_req = translate_req(clause, t, kind)
                if got_req is None:
                    bad = "requires"
                    break
                rp, rh = got_req
                if rp:
                    req_parts.append(rp)
                req_helpers += rh
            if bad:
                break
            if name != "null" and not re.match(r'^"[^"\\]*"$', name):
                bad = "interaction_forms"
                break
            em = re.match(r"^(?:PROC_REF\((\w+)\)|TYPE_PROC_REF\(" + re.escape(t) + r",\s*(\w+)\))$", effect)
            # the shared "handled, the input not used up" effect (code/datums/interactions/shared_effects.dm): an op with passes() and no then()
            passes_only = re.match(r"^TYPE_PROC_REF\(/atom,\s*interaction_pass\)$", effect)
            # another shared effect: the op's then() is its shared op handler (op_<name>, beside it in shared_effects.dm); no handler is rewritten
            shared_m = re.match(r"^TYPE_PROC_REF\((/atom|/obj/machinery),\s*interaction_(\w+)\)$", effect)
            shared_op = None
            if shared_m and not passes_only and shared_m.group(2) in SHARED_OPS and (t == shared_m.group(1) or t.startswith(shared_m.group(1) + "/")):
                shared_op = (shared_m.group(1), "op_" + shared_m.group(2))
            if not em and not passes_only and not shared_op:
                bad = "effect_expr"
                break
            if passes_only:
                em = re.match(r"^(interaction_pass)$", "interaction_pass")
            if shared_op:
                em = re.match(r"^(\w+)$", "interaction_" + shared_m.group(2))
            if held_type is not None and not re.match(r"^/[\w/]+$", held_type):
                bad = "interaction_forms"
                break
            specs.append({"kind": kind, "name": None if name == "null" else name, "proc": em.group(1) or em.group(2), "held": held_type, "carried": carried, "stance": stance, "default": suffix.startswith("_DEFAULT"), "req_parts": req_parts, "req_helpers": req_helpers, "shared": shared_op})
        if bad:
            residue[t] = bad
            continue
        if not specs:
            residue[t] = "interaction_forms"
            continue
        # specs that share one handler and differ only in their input (a hand and an item doing the same thing) are one op with inputs(...)
        merged_specs = []
        for sp in specs:
            twin = None if (sp["proc"] == "interaction_pass" or sp.get("shared")) else next((m for m in merged_specs if m["proc"] == sp["proc"]), None)
            if twin is None:
                sp["extra_kinds"] = []
                merged_specs.append(sp)
                continue
            same = all(twin.get(k) == sp.get(k) for k in ("name", "stance", "default", "carried", "req_parts"))
            if same and twin["name"] is None and "INSERT" in (sp["kind"], twin["kind"]):
                same = False  # an unnamed insert's label is its item's ("Insert a mop"): two of them are two labels
            if not same or sp["kind"] in ("VERB", "DRAG", "ALT", "SILICON", "ROBOT", "USE", "SELF") or twin["kind"] in ("VERB", "DRAG", "ALT", "SILICON", "ROBOT", "USE", "SELF"):
                merged_specs = None
                break
            twin["extra_kinds"].append(sp)
        if merged_specs is None:
            residue[t] = "handler_shared"
            continue
        specs = merged_specs
        tre = re.escape(t)
        handlers = []
        for s in specs:
            if s["proc"] == "interaction_pass":
                handlers.append({"actor_type": "mob", "spec": s, "rel": None, "idx": None, "first": None, "last": None, "actor": None, "held": None, "held_type": "obj/item", "body": "", "asks": [], "pass": True})
                continue
            if s.get("shared"):
                handlers.append({"actor_type": "mob", "spec": s, "rel": None, "idx": None, "first": None, "last": None, "actor": None, "held": None, "held_type": "obj/item", "body": "", "asks": [], "shared": s["shared"]})
                continue
            hits = [(r, i, prm) for (ty, r, i, prm) in defs_by_name.get(s["proc"], []) if ty == t]
            others = [1 for (ty, r, i, prm) in defs_by_name.get(s["proc"], []) if ty != t and related(ty, t) and not ty.startswith(t + "/")]
            # overrides of the handler below T (a subtype that runs its parent's handler first, tools/codemods/parent_call_override.py): they
            # change shape with it, so each must take the three legacy parameters and use none of the interaction's
            overrides = []
            for (ty, r, i, prm) in defs_by_name.get(s["proc"], []):
                if ty == t or not ty.startswith(t + "/"):
                    continue
                ops_ = [x.strip() for x in prm.split(",")]
                if len(ops_) != 3 or any("=" in x for x in ops_):
                    others.append(1)
                    continue
                ofb, olb = body_range(files[r].lines, i)
                obody = chr(10).join(strip_code(x) for x in files[r].lines[ofb : olb + 1] if x is not None)
                if words_in(obody, ops_[2].split("/")[-1]) or words_in(obody, "A") or re.search(r"\.\s*==|==\s*\.(?!\w)", obody):
                    others.append(1)
                    continue
                overrides.append((ty, r, i, ofb, olb, [x.split("/")[-1] for x in ops_], ["mob" if "/" not in ops_[0] else ops_[0].replace("var/", "").rsplit("/", 1)[0], "obj/item" if "/" not in ops_[1] else ops_[1].replace("var/", "").rsplit("/", 1)[0]], obody))
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
            if others or outside - self_mentions > 0 or s["proc"] in qualified_calls:
                # a Use or verb effect the type also calls itself (an older verb, a hotkey): the proc stays as it is, and the op's effect is a thin
                # one that calls it the way the old resolver did (its return was never read)
                wbody = chr(10).join(strip_code(l) for l in body_lines)
                if not others and s["kind"] in FALLS_THROUGH and not asks and "open_request(" not in wbody and not words_in(wbody, n_inter):
                    wrapper = "%s_op" % s["proc"]
                    if defs_by_name.get(wrapper) or re.search(r"\b" + wrapper + r"\b", tree_text):
                        bad = "name_clash"
                        break
                    helper = "/// The %s op: the verb's effect, as the old resolver ran it.%s%s/proc/%s(datum/act/op/A)%s%s(A.actor, A.held, null)%sreturn OP_OK" % (
                        s["proc"], chr(10), t, wrapper, chr(10) + chr(9), s["proc"], chr(10) + chr(9))
                    handlers.append({"actor_type": "mob", "spec": s, "rel": None, "idx": None, "first": None, "last": None, "actor": None, "held": None, "held_type": "obj/item", "body": "", "asks": [], "wrap": wrapper, "wrap_helper": helper})
                    continue
                bad = "handler_shared"
                break
            # a test that calls the handler on an unknown receiver blocks; one that calls it on a related type is rewritten to the driver by hand
            # (--sites lists them under "test caller")
            callers_t = tested_calls.get(s["proc"], set())
            if None in callers_t:
                bad = "handler_tested"
                break
            if any(related(rt, t) for rt in callers_t):
                test_rewrites.extend("%s/%s <- %s" % (t, s["proc"], site) for site in tested_sites[s["proc"]])
            body = "\n".join(strip_code(l) for l in body_lines)
            # INTERACTION_HANDLED_PASS (handled, the input not used up) is read only as a return value: `return OP_PASS`; any other use of it is residue
            stray_pass = re.sub(r"\breturn\s+INTERACTION_HANDLED_PASS\b", "", body)
            if words_in(body, n_inter) or "INTERACTION_HANDLED_PASS" in stray_pass or re.search(r"\.\.\(", body) or words_in(body, "A"):
                bad = "body_uses"
                break
            # a question opened from the handler is an asks() step of the op (sys/dx_review request_in_effect): by hand
            if "open_request(" in body:
                bad = "request_in_effect"
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
            handlers.append({"actor_type": actor_type, "spec": s, "rel": drel, "idx": di, "first": fb, "last": lb, "actor": n_actor, "held": n_held, "held_type": held_type, "body": body, "asks": asks, "overrides": overrides})
        if bad:
            residue[t] = bad
            continue
        # keys
        used = set()
        for h in handlers:
            proc = h["spec"]["proc"]
            key = re.sub(r"^interaction_", "", proc) or proc
            if h.get("shared"):
                key = re.sub(r"^op_", "", h["shared"][1])
                n = 2
                while key in used:
                    key = "%s_%d" % (re.sub(r"^op_", "", h["shared"][1]), n)
                    n += 1
            if h.get("pass"):
                key = "pass_%s" % h["spec"]["kind"].lower()
                n = 2
                while key in used:
                    key = "pass_%s_%d" % (h["spec"]["kind"].lower(), n)
                    n += 1
            if key in used or key_taken(key, t):
                key = proc
            if key in used or key_taken(key, t):
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
        # the requirement wrappers (translate_req): one per proc per type, emitted before the first handler that needs it
        emitted = set()
        for h in handlers:
            for hp in h["spec"].get("req_helpers", []):
                hm = re.search(r"^/[\w/]+/proc/(\w+)\(", hp, re.M) or re.search(r"^MSG_DEF\w*\(([\w/]+),", hp)
                hname = hm.group(1)
                if hname in emitted:
                    continue
                if defs_by_name.get(hname) or re.search(r"\b" + hname + r"\b", tree_text):
                    bad = "name_clash"
                    break
                emitted.add(hname)
                h["helpers"].append(hp)
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
        plans[t] = {"type": t, "decl": rs[0], "handlers": handlers, "extra": extra_decls}
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
    # --dirs a b ...: the whole tree is read (callers, tests, related types), but only declarations in these directories convert
    if "--dirs" in sys.argv:
        want = [d.rstrip("/") + "/" for d in sys.argv[sys.argv.index("--dirs") + 1 :] if not d.startswith("--")]
        for t in list(plans):
            if not any(plans[t]["decl"][1].replace("\\", "/").startswith(d) for d in want):
                del plans[t]
        residue = {t: why for t, why in residue.items() if any(decls[t][0][1].replace("\\", "/").startswith(d) for d in want)}
    # --prefix /type: only declarations of that type or below it
    if "--prefix" in sys.argv:
        pfx = sys.argv[sys.argv.index("--prefix") + 1]
        for t in list(plans):
            if not (t == pfx or t.startswith(pfx + "/")):
                del plans[t]
        residue = {t: why for t, why in residue.items() if t == pfx or t.startswith(pfx + "/")}
    converted_ops = sum(len(p["handlers"]) for p in plans.values())
    if not check:
        for t, plan in sorted(plans.items()):
            tre = re.escape(t)
            entries = []
            wrap_helpers = []
            for h in plan["handlers"]:
                s = h["spec"]
                extra_b = [binding_of(x, h)[0] for x in s.get("extra_kinds", [])]
                parts = ['op("%s"' % h["key"], ("inputs(%s)" % ", ".join([h["binding"]] + extra_b)) if extra_b else h["binding"]]
                if s["kind"] in ("HAND_UNGATED", "ALT"):
                    parts.append("ungated()")
                if s["kind"] == "ROBOT":
                    parts.append("when(req(/mob/living/silicon/robot, of = ON_ACTOR))")
                if h["gesture"]:
                    parts.append("gesture(%s)" % h["gesture"])
                if s["stance"]:
                    parts.append("stance(%s)" % s["stance"])
                if s["default"]:
                    parts.append("priority(OP_PRIORITY_DEFAULT)")
                if s["name"]:
                    parts.append("label(%s)" % s["name"])
                else:
                    # the name the legacy menu derived (code/datums/interactions/compact.dm): kept, so the pinned rows do not change wording
                    derived = legacy_name(s, type_names)
                    if derived:
                        parts.append('label("%s")' % derived)
                needs_parts = (["carried()"] if s.get("carried") else []) + [x for x in s.get("req_parts", []) if not x.startswith("@when ")]
                for x in s.get("req_parts", []):
                    if x.startswith("@when "):
                        parts.append("when(%s)" % x[len("@when ") :])
                if s["kind"] == "VERB" and not s.get("carried"):
                    # the legacy verb entry's base requirements (code/datums/interactions/entries.dm entry_verb): reach and an actor who can act;
                    # a menu() binding brings neither, so a ghost or an actor across the room would get the verb
                    needs_parts = ["req_adjacent()", "req_capable()"] + needs_parts
                if needs_parts:
                    parts.append("needs(%s)" % ", ".join(needs_parts))
                parts += h["ask_parts"]
                if h.get("pass"):
                    parts.append("passes()")
                    entries.append(", ".join(parts) + ")")
                    continue
                if h.get("shared"):
                    parts.append("then(TYPE_PROC_REF(%s, %s))" % h["shared"])
                    entries.append(", ".join(parts) + ")")
                    continue
                if h.get("wrap"):
                    parts.append("then(PROC_REF(%s))" % h["wrap"])
                    entries.append(", ".join(parts) + ")")
                    wrap_helpers.extend((t, hp) for hp in h["helpers"])  # its requirement wrappers: no rewritten handler carries them
                    wrap_helpers.append((t, h["wrap_helper"]))
                    continue
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
                # the overrides below T: the same signature, the same locals, the same returns; a bare return after `. = ..()` keeps `.`
                for (oty, orel, oi, ofb, olb, onames, otypes, obody) in h.get("overrides", []):
                    of = files[orel]
                    keeps_dot = bool(re.search(r"(^|\s)\.\s*=\s*\.\.\(\)", obody, re.M))
                    for k4 in range(ofb, olb + 1):
                        if of.lines[k4] is None:
                            continue
                        if keeps_dot:
                            of.lines[k4] = re.sub(r"\breturn(?=\s*(?://.*)?$)", "return .", of.lines[k4])
                            of.lines[k4] = re.sub(r"\breturn\s+(?:FALSE|0|null)(?=\s*(?://.*)?$)", "return OP_DECLINE", of.lines[k4])
                        elif s["kind"] not in FALLS_THROUGH:
                            of.lines[k4] = re.sub(r"\breturn\b(?:\s+(?:FALSE|0|null))?(?=\s*(?://.*)?$)", "return OP_DECLINE", of.lines[k4])
                        of.lines[k4] = re.sub(r"\breturn\s+INTERACTION_HANDLED_PASS\b", "return OP_PASS", of.lines[k4])
                    olocals = []
                    if words_in(obody, onames[0]):
                        olocals.append(chr(9) + "var/%s/%s = A.actor" % (otypes[0], onames[0]))
                    if words_in(obody, onames[1]):
                        olocals.append(chr(9) + "var/%s/%s = A.held" % (otypes[1], onames[1]))
                    of.lines[oi] = "%s/%s(datum/act/op/A)" % (oty, s["proc"]) + "".join(chr(10) + x for x in olocals)
                    of.dirty = True
            kind0, rel, first, last, text = plan["decl"]
            f = files[rel]
            block_at = None
            for r2, f2 in files.items():
                for i2, l2 in enumerate(f2.lines):
                    if l2 is not None and re.match(r"^CAPABILITIES\(" + tre + r"\)\s*(//.*)?$", l2):
                        block_at = (r2, i2)
            for k in range(first, last + 1):
                f.lines[k] = None
            for (_k, xrel, xfirst, xlast, _x) in plan.get("extra", []):
                for k in range(xfirst, xlast + 1):
                    files[xrel].lines[k] = None
                files[xrel].dirty = True
            if block_at:
                br, bi = block_at
                bf = files[br]
                fb, lb = body_range(bf.lines, bi)
                bf.lines[lb] = bf.lines[lb] + "".join("\n\t" + e for e in entries)
                bf.dirty = True
                if wrap_helpers:
                    f.lines[first] = "\n\n".join(hp for _t, hp in wrap_helpers)
            else:
                f.lines[first] = "CAPABILITIES(%s)" % t + "".join("\n\t" + e for e in entries)
                if wrap_helpers:
                    f.lines[first] += "\n\n" + "\n\n".join(hp for _t, hp in wrap_helpers)
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
    if sites:
        for tr in sorted(set(test_rewrites)):
            if tr.split(" <- ")[0].rsplit("/", 1)[0] in plans:
                print("    test caller to rewrite: " + tr)
    for why, ts in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print("    %-20s %4d" % (why, len(ts)))
        if sites:
            for t in sorted(ts):
                print("        " + t)
    return 1 if (check and plans) else 0


if __name__ == "__main__":
    sys.exit(main())
