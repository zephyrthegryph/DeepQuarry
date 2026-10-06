#!/usr/bin/env python3
r"""Machinery residue -> ops, in one step (rewrite/machinery-2).

    MSYS_NO_PATHCONV=1 python tools/codemods/machine_ops.py [--check] [--prefix /obj/machinery] [--only /type ...] [--files f.dm ...]

What the earlier codemods (interaction_datums.py, then interact_declare.py) left on machine types: a `T/declare_interactions(list/into)`
override listing machine datum interactions (`/datum/interaction/machine_hand|machine_hand/ungated|machine_item|machine_alt|machine_drag|
machine_verb/<x>`) and/or compact specs, or an `EXTEND_INTERACTIONS(T, specs...)` row. Each interaction becomes an op of `CAPABILITIES(T)`
(made where the declaration stood when T has none):

    datum / spec                         op
    machine_hand, INTERACT_HAND          op("key", hand(), ...)
    machine_hand/ungated, _HAND_UNGATED  op("key", hand(), ungated(), ...)
    machine_item (+held_type), _ITEM,    op("key", item(/obj/item | held_type), ...)
      _INSERT(held_type, ...)
    machine_alt, INTERACT_ALT            op("key", hand(), ungated(), gesture(GESTURE_ALT), ...)
    machine_drag, INTERACT_DRAG          op("key", item(<the handler's 2nd parameter type, /atom/movable>), gesture(GESTURE_DRAG), ...)
    machine_verb, INTERACT_VERB          op("key", menu(), ..., needs(req_adjacent(), req_capable(), ...))
    INTERACT_USE                         op("key", in_hand(), ...)
    INTERACT_SILICON                     op("key", remote(), ...)
    INTERACT_ROBOT                       op("key", remote(), when(req(/mob/living/silicon/robot, of = ON_ACTOR)), ...)

Every converted op carries priority(OP_PRIORITY_DEFAULT - 1 - n) (the legacy interactions ran after the ops a type already had:
intended_changes.md "Leftovers"); n counts the earlier interactions of the type on the same input, so the declaration order (the old resolver's
order, a falsy return falling through to the next) is the tier order. The requirement clauses go through interact_declare.translate_req()
(the same wrappers the op codemod writes). The handler `h(mob/u, obj/item/w, datum/interaction/i)` becomes `h(datum/act/op/A)` with the locals
it reads; for every kind but USE and VERB (whose returns were ignored) a falsy return is `return OP_DECLINE`, `return TRUE`/`1` is `return OP_OK`,
`INTERACTION_HANDLED_PASS` is `OP_PASS`, and a handler that can fall off its end gets a final `return OP_DECLINE` (it answered null before).

A type is left alone (and reported) when any part does not fit: another statement in the override, an override with no `..()`, a datum with
a field or proc not named above, a handler defined elsewhere than once or called from anywhere else, a handler that reads the interaction,
uses `..()`, a local `A`, or returns an expression. Observer specs (INTERACT_OBSERVER) wait for the observe provider.
"""
import os
import re
import sys
from collections import defaultdict, OrderedDict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "dx", "codemods"))
import interact_declare as ID  # noqa: E402

DATUM_BASES = OrderedDict([
    ("machine_hand/ungated", "HAND_UNGATED"),
    ("machine_hand", "HAND"),
    ("machine_item", "ITEM"),
    ("machine_alt", "ALT"),
    ("machine_drag", "DRAG"),
    ("machine_verb", "VERB"),
])
DATUM_FIELDS = {"id", "name", "effect", "held_type", "requires", "also_requires", "offered_when", "category", "consumes_input", "stance"}
SPEC_KINDS = {"USE", "SELF", "HAND", "HAND_UNGATED", "ITEM", "INSERT", "ALT", "DRAG", "VERB", "SILICON", "ROBOT"}
RETURN_IGNORED = {"USE", "VERB"}
SHARED = {
    "/datum/interaction/machine_hand/open_ui": ("HAND", '"Use"', "/atom/proc/interaction_open_ui"),
    "/datum/interaction/machine_hand/ungated/open_ui": ("HAND_UNGATED", '"Use"', "/atom/proc/interaction_open_ui"),
    "/datum/interaction/machine_item/part_replacement": ("INSERT", '"Replace parts"', "/obj/machinery/proc/interaction_part_replacement", "/obj/item/storage/part_replacer"),
}
SHARED_OPS = {"open_ui", "open_ui_fingerprint", "open_ui_powered", "open_ui_powered_fingerprint", "interact", "swallow", "as_touch", "fingerprint", "part_replacement", "pass"}


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def dm_files():
    for base, dirs, files in os.walk(os.path.join(ROOT, "code")):
        for f in files:
            if f.endswith(".dm"):
                yield os.path.join(base, f)


def read(p):
    with open(p, encoding="utf-8", errors="replace", newline="") as fh:
        return fh.read()


def strip_code(l):
    return ID.strip_code(l)


def no_comment(l):
    """The line without a trailing // comment; string text kept."""
    q = False
    i = 0
    while i < len(l):
        c = l[i]
        if c == "\\" and q:
            i += 2
            continue
        if c == '"':
            q = not q
        elif not q and l.startswith("//", i):
            return l[:i]
        i += 1
    return l


def words_in(text, w):
    return ID.words_in(text, w)


def split_args(s):
    return ID.split_args(s)


def related(a, b):
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def is_under(t, anc):
    return anc in ("/atom", "/obj") and t.startswith(anc + "/") or anc == "/atom" or t == anc or t.startswith(anc + "/")


class F:
    def __init__(self, path):
        self.path = path
        self.text = read(path)
        self.nl = "\r\n" if "\r\n" in self.text else "\n"
        self.lines = self.text.split(self.nl)
        self.dirty = False

    def save(self):
        out = [l for l in self.lines if l is not None]
        with open(self.path, "w", encoding="utf-8", newline="") as fh:
            fh.write(self.nl.join(out))


def body_end(lines, i):
    """Last line index of the column-0 block starting at i (its indented and blank lines; trailing blanks excluded)."""
    j = i + 1
    last = i
    while j < len(lines):
        l = lines[j]
        if l is None:
            j += 1
            continue
        if l.strip() == "":
            j += 1
            continue
        if l[0] in "\t ":
            last = j
            j += 1
            continue
        break
    return last


def joined_macro(lines, i):
    """A column-0 macro call starting at line i, possibly continued with backslashes or open parens: (text, last index)."""
    text = ""
    depth = 0
    j = i
    while j < len(lines):
        l = lines[j]
        s = strip_code(l)
        t = l.rstrip()
        if t.endswith("\\"):
            t = t[:-1]
        text += t + "\n"
        for ch in s:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
        if depth <= 0 and not l.rstrip().endswith("\\"):
            return text, j
        j += 1
    return text, j


def main(argv):
    check = "--check" in argv
    prefix = argv[argv.index("--prefix") + 1] if "--prefix" in argv else "/obj/machinery"
    only = []
    if "--only" in argv:
        k = argv.index("--only") + 1
        while k < len(argv) and not argv[k].startswith("--"):
            only.append(argv[k])
            k += 1
    want_files = []
    if "--files" in argv:
        k = argv.index("--files") + 1
        while k < len(argv) and not argv[k].startswith("--"):
            want_files.append(argv[k].replace("\\", "/"))
            k += 1
    skip_dirs = ("code/game/objects/", "code/modules/unit_tests/", "code/tests/", "code/__defines/", "code/engine/", "code/datums/interactions/")

    files = {}
    for p in dm_files():
        files[rel(p)] = F(p)

    # ---- definitions: procs by name, datum types, declarations ----
    proc_defs = defaultdict(list)  # name -> [(type, rel, idx, params)]
    datums = {}  # path -> {base, fields{}, rel, first, last, procs[]}
    decls = defaultdict(list)  # type -> [("override"|"extend", rel, first, last, text)]
    caps_blocks = {}  # type -> (rel, idx)
    op_keys = defaultdict(set)  # type -> keys of its CAPABILITIES block
    for r, f in files.items():
        cur_caps = None
        for i, l in enumerate(f.lines):
            if not l or l[0] in "\t ":
                if cur_caps and l:
                    for m in re.finditer(r'\bop\("([\w.]+)"', l):
                        op_keys[cur_caps].add(m.group(1))
                continue
            cur_caps = None
            m = re.match(r"^CAPABILITIES\((/[\w/]+)\)\s*(//.*)?$", l)
            if m:
                caps_blocks[m.group(1)] = (r, i)
                cur_caps = m.group(1)
                continue
            m = re.match(r"^(/[\w/]+?)/(?:proc/)?(\w+)\((.*)\)\s*(//.*)?$", l)
            if m and not l.startswith("/datum/interaction/"):
                proc_defs[m.group(2)].append((m.group(1), r, i, m.group(3)))
            m = re.match(r"^(/obj/machinery[\w/]*)/declare_interactions\(list/into\)\s*$", l)
            if m:
                decls[m.group(1)].append(("override", r, i, body_end(f.lines, i), None))
                continue
            m = re.match(r"^EXTEND_INTERACTIONS\((/[\w/]+)\s*,", l)
            if m:
                text, last = joined_macro(f.lines, i)
                decls[m.group(1)].append(("extend", r, i, last, text))
                continue
            m = re.match(r"^(/datum/interaction/[\w/]+)\s*(//.*)?$", l)
            if m:
                path = m.group(1)
                base = None
                for b in DATUM_BASES:
                    if path.startswith("/datum/interaction/" + b + "/") and "/" not in path[len("/datum/interaction/" + b + "/"):]:
                        base = b
                        break
                last = body_end(f.lines, i)
                fields = {}
                k = i + 1
                bad = None
                while k <= last:
                    s = f.lines[k]
                    st = no_comment(s).strip()
                    if not st:
                        k += 1
                        continue
                    fm = re.match(r"^(\w+)\s*=\s*(.*)$", st)
                    if not fm:
                        bad = "datum_statement"
                        break
                    val, k2 = fm.group(2), k
                    depth = val.count("(") - val.count(")")
                    while depth > 0 and k2 < last:
                        k2 += 1
                        nxt = no_comment(f.lines[k2]).strip()
                        val += " " + nxt
                        depth += nxt.count("(") - nxt.count(")")
                    fields[fm.group(1)] = val.strip().rstrip(",")
                    k = k2 + 1
                datums[path] = {"base": base, "fields": fields, "rel": r, "first": i, "last": last, "bad": bad}
            m = re.match(r"^(/datum/interaction/[\w/]+)/(?:proc/)?(\w+)\(", l)
            if m and m.group(1) in datums:
                datums[m.group(1)].setdefault("procs", []).append(m.group(2))
            elif m:
                # a proc of a datum declared later in the file: recorded after the pass
                pass
    for r, f in files.items():
        for i, l in enumerate(f.lines):
            m = re.match(r"^(/datum/interaction/[\w/]+)/(?:proc/)?(\w+)\(", l or "")
            if m and m.group(1) in datums:
                datums[m.group(1)]["has_proc"] = True

    # every mention of a word in the tree, with the type whose block the line sits in (handler callers)
    tree_text = {r: "\n".join(strip_code(l) for l in f.lines) for r, f in files.items()}
    line_owner = {}
    for r, f in files.items():
        owners = []
        cur = None
        for l in f.lines:
            if l and l[0] not in "\t ":
                m = re.match(r"^(?:EXTEND_INTERACTIONS|DECLARE_INTERACTIONS|CAPABILITIES)\((/[\w/]+)", l) or re.match(r"^(/[\w/]+?)(?:/(?:proc|verb)/\w+|/\w+\(|$)", l)
                cur = m.group(1) if m else None
                if cur and cur.startswith("/datum/interaction/"):
                    cur = "@datum"
            owners.append(cur)
        line_owner[r] = owners

    def mentions(word, t, datum_effects):
        """Mentions of `word` in lines owned by a type related to t, or by no type (globals, tests)."""
        out = []
        for r, txt in tree_text.items():
            if word not in txt:
                continue
            f = files[r]
            for i, l in enumerate(f.lines):
                if word not in l:
                    continue
                n = len(words_in(strip_code(l), word))
                if not n:
                    continue
                o = line_owner[r][i]
                if o == "@datum":
                    em = re.search(r"effect\s*=\s*(/[\w/]+?)/proc/" + word + r"\b", l)
                    if em and not related(em.group(1), t):
                        continue
                    if em:
                        datum_effects.append((r, i))
                elif o and not related(o, t) and o != "/atom" and not t.startswith(o + "/"):
                    continue
                out.append((r, n))
        return out

    # the names items declare (the legacy menu's "Insert a <name>")
    type_names = {}
    for r, f in files.items():
        cur = None
        for l in f.lines:
            if l and l[0] not in "	 ":
                m = re.match(r"^(/[\w/]+)\s*(//.*)?$", l)
                cur = m.group(1) if m else None
                continue
            if cur:
                m = re.match(r'^	name\s*=\s*("[^"]*")', l or "")
                if m:
                    type_names[cur] = m.group(1)

    # ---- plan each type ----
    plans = {}
    residue = {}
    detail = {}
    types = sorted(t for t in decls if is_under(t, prefix))
    if only:
        types = [t for t in types if t in only]
    for t in types:
        ds = decls[t]
        if want_files and not any(d[1] in want_files for d in ds):
            continue
        if any(d[1].startswith(skip_dirs) for d in ds):
            residue[t] = "skip_dir"
            continue
        why = None
        items = []  # (kind, name, effect, held, req_clauses, when_clauses, stance, origin)
        for (form, r, first, last, text) in ds:
            f = files[r]
            if form == "extend":
                inner = text[text.index("(") + 1 : text.rindex(")")]
                parts = [p for p in split_args(inner)][1:]
                for p in parts:
                    if not p:
                        continue
                    got = parse_spec(p)
                    if isinstance(got, str):
                        why = got
                        break
                    items.append(got)
            else:
                has_super = False
                k = first + 1
                body = []
                while k <= last:
                    st = no_comment(f.lines[k]).strip()
                    body.append(st)
                    k += 1
                stmts = " ".join(body)
                # into += list(a, b, ...) and into += dq_interaction_from_spec(type, SPEC)
                rest = stmts
                for m in re.finditer(r"into\s*\+=\s*list\(([^)]*)\)", stmts):
                    for p in [x.strip() for x in m.group(1).split(",") if x.strip()]:
                        if p in SHARED:
                            sh = SHARED[p]
                            items.append({"kind": sh[0], "name": sh[1], "effect": sh[2], "held": sh[3] if len(sh) > 3 else None, "reqs": [], "whens": [], "stance": None, "id": None})
                            continue
                        d = datums.get(p)
                        if not d:
                            why = "datum_unknown"
                            break
                        got = datum_item(p, d)
                        if isinstance(got, str):
                            why = got
                            break
                        items.append(got)
                    rest = rest.replace(m.group(0), "")
                    if why:
                        break
                for m in re.finditer(r"into\s*\+=\s*dq_interaction_from_spec\(type,\s*(INTERACT_.*?\))\)\s*(?=into|\.\.\(\)|$)", stmts):
                    got = parse_spec(m.group(1))
                    if isinstance(got, str):
                        why = got
                        break
                    items.append(got)
                    rest = rest.replace(m.group(0), "")
                if "..()" in rest:
                    has_super = True
                    rest = rest.replace("..()", "")
                if rest.strip():
                    why = why or "override_statement"
                if not has_super:
                    why = why or "override_no_super"
            if why:
                break
        if why:
            residue[t] = why
            continue
        if not items:
            plans[t] = {"handlers": [], "helpers": [], "decls": ds}
            continue
        # handlers
        handlers = []
        for it in items:
            em = re.match(r"^(?:PROC_REF\((\w+)\)|TYPE_PROC_REF\((/[\w/]+),\s*(\w+)\)|(/[\w/]+?)/proc/(\w+))$", it["effect"])
            if not em:
                why = "effect_expr"
                break
            pname = em.group(1) or em.group(3) or em.group(5)
            owner = em.group(2) or em.group(4)
            if owner and not is_under(t, owner):
                why = "effect_owner"
                break
            sm = re.match(r"^interaction_(\w+)$", pname)
            if sm and sm.group(1) in SHARED_OPS and owner in ("/atom", "/obj/machinery", None) and not any(ty == t for (ty, _r, _i, _p) in proc_defs.get(pname, [])):
                shared = sm.group(1)
                if shared == "open_ui" and type_has_interface(t, caps_blocks, files):
                    it["drop"] = True
                    handlers.append({"item": it, "shared": None})
                    continue
                owner2 = "/obj/machinery" if shared in ("open_ui_powered", "open_ui_powered_fingerprint", "part_replacement") else "/atom"
                handlers.append({"item": it, "shared": (owner2, "op_" + shared)})
                continue
            defs = [d for d in proc_defs.get(pname, []) if related(d[0], t)]
            own = [d for d in defs if d[0] == t or (is_under(t, d[0]))]
            below = [d for d in defs if d[0] != t and is_under(d[0], t)]
            if len(own) != 1:
                why = "handler_defs"
                break
            (dty, dr, di, params) = own[0]
            if dty != t:
                # an inherited handler: other types may share it
                why = "handler_inherited"
                break
            ps = [x.strip() for x in params.split(",")]
            if len(ps) != 3 or any("=" in x for x in ps):
                why = "handler_shape"
                break
            # every mention: its definition, the declaration that names it, overrides below
            de = []
            n_mentions = sum(n for (_r, n) in mentions(pname, t, de))
            expected = 1 + len(below) + sum(1 for it2 in items if re.search(r"\b%s\b" % pname, it2["effect"]))
            if n_mentions > expected:
                why = "handler_called"
                break
            hf = files[dr]
            last = body_end(hf.lines, di)
            body_lines = list(range(di + 1, last + 1))
            body = "\n".join(strip_code(hf.lines[k]) for k in body_lines)
            names = [x.replace("var/", "").split("/")[-1] for x in ps]
            types_ = [x.replace("var/", "").rsplit("/", 1)[0] if "/" in x.replace("var/", "") else None for x in ps]
            if words_in(body, names[2]) or words_in(body, "A") or re.search(r"\.\.\(", body):
                why = "handler_body"
                break
            if "open_request(" in body:
                why = "request_in_effect"
                break
            if it["kind"] == "VERB" and words_in(body, names[1]):
                why = "verb_reads_held"
                break
            for (bt, br, bi, bp) in below:
                bps = [x.strip() for x in bp.split(",")]
                if len(bps) != 3:
                    why = "override_shape"
                    break
                bbody = "\n".join(strip_code(files[br].lines[k]) for k in range(bi + 1, body_end(files[br].lines, bi) + 1))
                if words_in(bbody, bps[2].split("/")[-1]) or words_in(bbody, "A") or "open_request(" in bbody:
                    why = "override_body"
                    break
            if why:
                break
            if it["kind"] not in RETURN_IGNORED:
                for k in body_lines:
                    for rm in re.finditer(r"\breturn\b(.*)$", strip_code(hf.lines[k])):
                        if rm.group(1).strip() not in ("", "TRUE", "FALSE", "0", "1", "null", "INTERACTION_HANDLED_PASS", "OP_DECLINE", "OP_OK", "OP_PASS"):
                            why = "handler_returns"
                    if re.match(r"^\s*\.\s*=", strip_code(hf.lines[k])):
                        why = "handler_dot"
                if why:
                    break
            handlers.append({"item": it, "proc": pname, "rel": dr, "idx": di, "last": last, "names": names, "types": types_, "body": body, "below": below})
        if why:
            residue[t] = why
            continue
        # keys
        used = set()
        anc_keys = set()
        for u, ks in op_keys.items():
            if related(u, t):
                anc_keys |= ks
        for h in handlers:
            it = h["item"]
            if it.get("drop"):
                continue
            if h.get("shared"):
                base = h["shared"][1][3:]
            else:
                base = it.get("id") or re.sub(r"^interaction_", "", h["proc"])
            key = base
            n = 2
            while key in used or key in anc_keys:
                key = "%s_%d" % (base, n)
                n += 1
            used.add(key)
            h["key"] = key
        # requirements
        helpers = []
        emitted = set()
        for h in handlers:
            it = h["item"]
            if it.get("drop"):
                continue
            needs, whens = [], []
            for c in it["reqs"]:
                got = translate(c, t, it["kind"])
                if got is None:
                    why = "requires"
                    detail[t] = c
                    break
                if got[0].startswith("@when "):
                    whens.append(got[0][6:])
                elif got[0]:
                    needs.append(got[0])
                for hp in got[1]:
                    hm = re.search(r"^/[\w/]+/proc/(\w+)\(", hp, re.M) or re.search(r"^MSG_DEF\w*\(([\w/]+),", hp)
                    hn = hm.group(1)
                    if hn in emitted:
                        continue
                    if any(related(d[0], t) for d in proc_defs.get(hn, [])):
                        if hn.endswith("_holds") or hn.endswith("_refusal"):
                            continue  # an ancestor's wrapper: inherited
                        why = "name_clash"
                        break
                    emitted.add(hn)
                    helpers.append(hp)
                if why:
                    break
            for c in it["whens"]:
                got = ID.translate_req("OFFERED_WHEN(%s)" % c, t, it["kind"])
                if got is None:
                    why = "offered_when"
                    break
                whens.append(got[0][6:])
                for hp in got[1]:
                    hn = re.search(r"^/[\w/]+/proc/(\w+)\(", hp, re.M).group(1)
                    if hn in emitted or any(related(d[0], t) for d in proc_defs.get(hn, [])):
                        continue
                    emitted.add(hn)
                    helpers.append(hp)
            if why:
                break
            h["needs"], h["whens"] = needs, whens
        if why:
            residue[t] = why
            continue
        plans[t] = {"handlers": handlers, "helpers": helpers, "decls": ds}

    # ---- write ----
    if not check:
        rewritten = set()
        for t, plan in sorted(plans.items()):
            entries = []
            seen_inputs = defaultdict(int)
            for h in plan["handlers"]:
                it = h["item"]
                if it.get("drop"):
                    continue
                kind = it["kind"]
                held_t = it.get("held")
                if kind == "DRAG":
                    ht = (h.get("types") or [None, None])[1] if not h.get("shared") else None
                    binding = ("item(%s)" % held_t) if held_t else ("item(/%s)" % ht if ht else "item(/atom/movable)")
                    lm = re.match(r"^list\((.*)\)$", (held_t or "").strip(), re.S)
                    if lm:
                        binding = "inputs(%s)" % ", ".join("item(%s)" % x.strip() for x in split_args(lm.group(1)) if x.strip())
                elif kind in ("ITEM",):
                    binding = "item(/obj/item)"
                elif kind == "INSERT":
                    lm = re.match(r"^list\((.*)\)$", held_t.strip(), re.S)
                    if lm:
                        binding = "inputs(%s)" % ", ".join("item(%s)" % x.strip() for x in split_args(lm.group(1)) if x.strip())
                    else:
                        binding = "item(%s)" % held_t
                elif kind in ("HAND", "HAND_UNGATED", "ALT"):
                    binding = "hand()"
                elif kind in ("USE", "SELF"):
                    binding = "in_hand()"
                elif kind == "VERB":
                    binding = "menu()"
                else:
                    binding = "remote()"
                parts = ['op("%s"' % h["key"], binding]
                if kind in ("HAND_UNGATED", "ALT"):
                    parts.append("ungated()")
                if kind == "ALT":
                    parts.append("gesture(GESTURE_ALT)")
                if kind == "DRAG":
                    parts.append("gesture(GESTURE_DRAG)")
                if kind == "ROBOT":
                    parts.append("when(req(/mob/living/silicon/robot, of = ON_ACTOR))")
                if it.get("stance"):
                    parts.append("stance(%s)" % it["stance"])
                if kind != "VERB":
                    sig = (binding, kind in ("ALT",), kind == "DRAG")
                    n = seen_inputs[sig]
                    seen_inputs[sig] += 1
                    parts.append("priority(OP_PRIORITY_DEFAULT - %d)" % (1 + n))
                if it.get("name") and it["name"] != "null":
                    parts.append("label(%s)" % it["name"])
                else:
                    spec = {"kind": "INSERT" if kind == "INSERT" else kind, "held": held_t, "proc": h.get("proc") or (h.get("shared") or ("", ""))[1].replace("op_", "interaction_")}
                    derived = ID.legacy_name(spec, type_names) if not (kind == "INSERT" and held_t and held_t.startswith("list(")) else None
                    if derived:
                        parts.append('label("%s")' % derived)
                for w in h["whens"]:
                    parts.append("when(%s)" % w)
                needs = list(h["needs"])
                if kind == "VERB":
                    needs = ["req_adjacent()", "req_capable()"] + needs
                if needs:
                    parts.append("needs(%s)" % ", ".join(needs))
                if it.get("passes"):
                    parts.append("passes()")
                if h.get("shared"):
                    if h["shared"][1] == "op_pass":
                        parts.append("passes()")
                    else:
                        parts.append("then(TYPE_PROC_REF(%s, %s))" % h["shared"])
                else:
                    parts.append("then(PROC_REF(%s))" % h["proc"])
                entries.append(", ".join(parts) + ")")
                if h.get("shared"):
                    continue
                if (h["rel"], h["idx"]) in rewritten:
                    continue
                rewritten.add((h["rel"], h["idx"]))
                rewrite_handler(files, h, kind)
                for (bt, br, bi, bp) in h["below"]:
                    rewrite_override(files, bt, br, bi, bp, h["proc"], kind)
            # delete the declarations and their datums
            for (form, r, first, last, text) in plan["decls"]:
                f = files[r]
                for k in range(first, last + 1):
                    f.lines[k] = None
                f.dirty = True
            for h in plan["handlers"]:
                p = h["item"].get("datum")
                if p and p in datums:
                    d = datums[p]
                    still = any(re.search(re.escape(p) + r"\b", tree_text[r]) and r != d["rel"] for r in tree_text) or len(re.findall(re.escape(p) + r"\b", tree_text[d["rel"]])) > 2
                    if not still:
                        df = files[d["rel"]]
                        for k in range(d["first"], d["last"] + 1):
                            df.lines[k] = None
                        # a doc comment right above it goes too
                        k = d["first"] - 1
                        while k >= 0 and df.lines[k] is not None and df.lines[k].startswith("///"):
                            df.lines[k] = None
                            k -= 1
                        df.dirty = True
            first_decl = plan["decls"][0]
            f = files[first_decl[1]]
            block = caps_blocks.get(t)
            helper_text = "".join("\n\n" + hp for hp in plan["helpers"])
            if block:
                bf = files[block[0]]
                end = body_end(bf.lines, block[1])
                while bf.lines[end] is None:
                    end -= 1
                bf.lines[end] = bf.lines[end] + "".join("\n\t" + e for e in entries)
                bf.dirty = True
                if helper_text:
                    f.lines[first_decl[2]] = helper_text.lstrip("\n")
            else:
                f.lines[first_decl[2]] = "CAPABILITIES(%s)" % t + "".join("\n\t" + e for e in entries) + helper_text
            f.dirty = True
        for f in files.values():
            if f.dirty:
                # collapse runs of blank lines a deletion left
                out = []
                for l in "\n".join(x for x in f.lines if x is not None).split("\n"):
                    if l.strip() == "" and out and out[-1].strip() == "":
                        continue
                    out.append(l)
                f.lines = out
                f.save()
    by = defaultdict(list)
    for t, w in residue.items():
        by[w].append(t)
    print("machine_ops: %d types%s; residue %d" % (len(plans), " (check)" if check else "", len(residue)))
    for t in sorted(plans):
        print("    ok %s (%d)" % (t, len([h for h in plans[t]["handlers"] if not h["item"].get("drop")])))
    for w, ts in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print("    %-20s %d" % (w, len(ts)))
        for t in sorted(ts):
            print("        " + t + (("    [" + detail[t][:150] + "]") if t in detail else ""))
    return 0


def msg_for(t, key, text):
    """A MSG_DEF_SELF for a refusal text, named after the type's last path segment: (MSG(...) text, the def line)."""
    path = "%s/%s" % (t.split("/")[-1], key)
    return "MSG(%s)" % path, 'MSG_DEF_SELF(%s, "%s")' % (path, text.replace('"', '\\"'))


def translate(clause, t, kind, reason=None):
    """One legacy requirement clause -> (needs() part, [helpers]) like interact_declare.translate_req(), plus the field, anchored, panel,
    actor-type and actor-side forms; `reason` is a REQ_BECAUSE's text."""
    c = clause.strip()
    m = re.match(r'^REQ_BECAUSE\((.*),\s*("(?:[^"\\]|\\.)*")\)$', c, re.S)
    if m:
        return translate(m.group(1), t, kind, m.group(2)[1:-1])
    m = re.match(r'^REQ_FIELD(_NOT)?\("(\w+)"(?:,\s*("(?:[^"\\]|\\.)*"))?\)$', c)
    if m:
        text = reason or (m.group(3)[1:-1] if m.group(3) else None)
        value = "FALSE" if m.group(1) else "TRUE"
        if not text:
            return ("req_is(nameof(%s), %s, because = /datum/msg/req_failed)" % (m.group(2), value), [])
        mref, mdef = msg_for(t, m.group(2) if m.group(1) else "no_" + m.group(2), text)
        return ("req_is(nameof(%s), %s, because = %s)" % (m.group(2), value, mref), [mdef])
    if c == "REQ_ANCHORED":
        if not reason:
            return ("req_is(nameof(anchored), TRUE, because = /datum/msg/req_failed)", [])
        mref, mdef = msg_for(t, "unanchored", reason)
        return ("req_is(nameof(anchored), TRUE, because = %s)" % mref, [mdef])
    m = re.match(r"^REQ_PANEL\((TRUE|FALSE)\)$", c)
    if m:
        if not reason:
            return ("req_is(nameof(panel_open), %s, because = /datum/msg/req_failed)" % m.group(1), [])
        mref, mdef = msg_for(t, "panel", reason)
        return ("req_is(nameof(panel_open), %s, because = %s)" % (m.group(1), mref), [mdef])
    m = re.match(r"^REQ_TYPE\(PRED_ACTOR,\s*(list\([^)]*\)|/[\w/]+)\)$", c)
    if m:
        types = m.group(1)
        lm = re.match(r"^list\((/[\w/]+)\)$", types)
        if lm:
            types = lm.group(1)
        if not reason:
            return ("req(%s, of = ON_ACTOR)" % types, [])
        mref, mdef = msg_for(t, "actor_type", reason)
        return ("req(%s, of = ON_ACTOR, because = %s)" % (types, mref), [mdef])
    m = re.match(r"^REQ_ON\(PRED_ACTOR,\s*(/[\w/]+?)/proc/(\w+),\s*(\"[^\"\\]*\"|null)\)$", c)
    if m and (m.group(1) == t or t.startswith(m.group(1) + "/")):
        # a proc of the machine asked of the actor: hascall() never found it on a mob, so it always refused; asked of the machine, as meant
        c = "REQ_ON(PRED_TARGET, %s/proc/%s, %s)" % (m.group(1), m.group(2), m.group(3))
    m = re.match(r"^REQ_TARGET_STATE\((/[\w/]+?)/proc/(\w+)\)$", c)
    if m and reason:
        c = 'REQ_ON(PRED_TARGET, %s/proc/%s, "%s")' % (m.group(1), m.group(2), reason)
    return ID.translate_req(c, t, kind)


def type_has_interface(t, caps_blocks, files):
    parts = t.split("/")
    for n in range(len(parts), 2, -1):
        u = "/".join(parts[:n])
        if u in caps_blocks:
            r, i = caps_blocks[u]
            f = files[r]
            end = body_end(f.lines, i)
            if any(l and re.search(r"\binterface\(", l) for l in f.lines[i : end + 1]):
                return True
    return False


def parse_spec(p):
    m = re.match(r"^(INTERACT_[A-Z_]+)\((.*)\)$", p.strip(), re.S)
    if not m:
        return "spec_expr"
    nm = re.match(r"^INTERACT_(USE|SELF|HAND_UNGATED|HAND|ITEM|INSERT|DRAG|ALT|VERB|SILICON|ROBOT|OBSERVER|TK)(_AS|_HOSTILE|_PEACEFUL|_DEFAULT_AS|_DEFAULT)?$", m.group(1))
    if not nm:
        return "spec_kind"
    kind = nm.group(1)
    if kind in ("OBSERVER", "TK"):
        return "spec_" + kind.lower()
    a = split_args(m.group(2))
    stance = None
    suffix = nm.group(2) or ""
    if suffix.startswith("_DEFAULT"):
        return "spec_default"
    if suffix == "_AS":
        stance, a = a[0], a[1:]
    elif suffix == "_HOSTILE":
        stance = "I_HURT"
    elif suffix == "_PEACEFUL":
        stance = "I_HELP"
    if kind == "INSERT":
        if len(a) < 3:
            return "spec_args"
        held, effect, name = a[:3]
        extra = a[3:]
    else:
        if len(a) < 2:
            return "spec_args"
        name, effect = a[:2]
        held = None
        extra = a[2:]
    if name != "null" and not re.match(r'^"[^"\\]*"$', name):
        return "spec_name"
    reqs, whens = [], []
    for c in extra:
        c = c.strip()
        if not c:
            continue
        om = re.match(r"^OFFERED_WHEN\((.*)\)$", c, re.S)
        if om:
            whens.append(om.group(1).strip())
        elif c == "REQ_IN_INVENTORY":
            return "spec_carried"
        elif c in ("REQ_PROC(/proc/dq_actor_can_act, \"you can't do that right now\")", "REQ_INTERACTION_REACH"):
            continue
        else:
            reqs.append(c)
    return {"kind": kind, "name": name if name != "null" else None, "effect": effect.strip(), "held": held, "reqs": reqs, "whens": whens, "stance": stance, "id": None}


def datum_item(path, d):
    if d.get("bad"):
        return d["bad"]
    if d.get("has_proc"):
        return "datum_proc"
    if not d["base"]:
        return "datum_base"
    f = d["fields"]
    extra = set(f) - DATUM_FIELDS
    if extra:
        return "datum_field:" + ",".join(sorted(extra))
    kind = DATUM_BASES[d["base"]]
    held = f.get("held_type")
    if kind == "ITEM" and held:
        kind = "INSERT"
    reqs = []
    if "requires" in f:
        lm = re.match(r"^list\((.*)\)$", f["requires"], re.S)
        if not lm:
            return "datum_requires"
        rs = [x.strip() for x in split_args(lm.group(1)) if x.strip()]
        if rs and "REQ_INTERACTION_REACH" not in rs and "REQ_REACH_ADJACENT" not in rs:
            return "requires_reach"
        rs = [x for x in rs if x not in ("REQ_INTERACTION_REACH", "REQ_REACH_ADJACENT", "REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null)", 'REQ_PROC(/proc/dq_actor_can_act, "you can\'t do that right now")')]
        reqs += rs
    if "also_requires" in f:
        lm = re.match(r"^list\((.*)\)$", f["also_requires"], re.S)
        if not lm:
            return "datum_requires"
        reqs += [x.strip() for x in split_args(lm.group(1)) if x.strip()]
    whens = []
    if "offered_when" in f:
        lm = re.match(r"^list\((.*)\)$", f["offered_when"], re.S)
        whens = [x.strip() for x in split_args(lm.group(1)) if x.strip()] if lm else [f["offered_when"]]
    passes = f.get("consumes_input", "TRUE") in ("FALSE", "0")
    name = f.get("name")
    if name and not re.match(r'^"[^"\\]*"$', name):
        return "datum_name"
    return {"kind": kind, "name": name, "effect": f.get("effect", ""), "held": held, "reqs": reqs, "whens": whens, "stance": f.get("stance"), "id": (f.get("id") or "").strip('"') or None, "datum": path, "passes": passes}


def rewrite_returns(line, kind):
    if kind not in RETURN_IGNORED:
        line = re.sub(r"\breturn\b(?:\s+(?:FALSE|0|null))?(?=\s*(?://.*)?$)", "return OP_DECLINE", line)
        line = re.sub(r"\breturn\s+(?:TRUE|1)(?=\s*(?://.*)?$)", "return OP_OK", line)
    line = re.sub(r"\breturn\s+INTERACTION_HANDLED_PASS\b", "return OP_PASS", line)
    return line


def ends_in_return(lines, first, last):
    """Whether the last top-level statement of the body is a return (so the handler cannot fall off its end)."""
    k = last
    while k > first:
        s = strip_code(lines[k] or "")
        if s.strip():
            break
        k -= 1
    s = lines[k] or ""
    return re.match(r"^\treturn\b", s) is not None


def rewrite_handler(files, h, kind):
    f = files[h["rel"]]
    names, types_ = h["names"], h["types"]
    locals_ = []
    body = h["body"]
    if words_in(body, names[0]):
        locals_.append("\tvar/%s/%s = A.actor" % (types_[0] or "mob", names[0]))
    if words_in(body, names[1]):
        ht = types_[1] or ("atom/movable" if kind == "DRAG" else "obj/item")
        locals_.append("\tvar/%s/%s = A.held" % (ht, names[1]))
    typ = re.match(r"^(/[\w/]+?)/(?:proc/)?\w+\(", f.lines[h["idx"]])
    head = f.lines[h["idx"]]
    head = re.sub(r"\(.*\)", "(datum/act/op/A)", head, count=1)
    for k in range(h["idx"] + 1, h["last"] + 1):
        if f.lines[k] is not None:
            f.lines[k] = rewrite_returns(f.lines[k], kind)
    falls = kind not in RETURN_IGNORED and not ends_in_return(f.lines, h["idx"], h["last"])
    if falls:
        f.lines[h["last"]] = f.lines[h["last"]] + "\n\treturn OP_DECLINE"
    f.lines[h["idx"]] = head + "".join("\n" + l for l in locals_)
    f.dirty = True


def rewrite_override(files, bt, br, bi, bp, proc, kind):
    f = files[br]
    last = body_end(f.lines, bi)
    bps = [x.strip() for x in bp.split(",")]
    names = [x.replace("var/", "").split("/")[-1] for x in bps]
    types_ = [x.replace("var/", "").rsplit("/", 1)[0] if "/" in x.replace("var/", "") else None for x in bps]
    body = "\n".join(strip_code(f.lines[k]) for k in range(bi + 1, last + 1))
    locals_ = []
    if words_in(body, names[0]):
        locals_.append("\tvar/%s/%s = A.actor" % (types_[0] or "mob", names[0]))
    if words_in(body, names[1]):
        locals_.append("\tvar/%s/%s = A.held" % (types_[1] or "obj/item", names[1]))
    for k in range(bi + 1, last + 1):
        if f.lines[k] is not None:
            f.lines[k] = rewrite_returns(f.lines[k], kind)
    f.lines[bi] = re.sub(r"\(.*\)", "(datum/act/op/A)", f.lines[bi], count=1) + "".join("\n" + l for l in locals_)
    f.dirty = True


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
