#!/usr/bin/env python3
r"""Lowers datum interactions to the compact spec form, so tools/dx/codemods/interact_declare.py can convert them to ops.

    python tools/codemods/interaction_datums.py [--check] [--sites] [--dirs code/game/objects ...]

The unit is one `T/declare_interactions(list/into)` override that ends in `..()` (an extension: what EXTEND_INTERACTIONS
expands to) and whose statements are only

    into += list(/datum/interaction/<entry>/<x>, ...)          each a simple entry datum (below)
    into += dq_interaction_from_spec(type, INTERACT_...(...))  a compact spec, kept as it is
    ..()

It becomes `EXTEND_INTERACTIONS(T, <specs in the same order>)` and the datum types are deleted. A datum lowers when it is
only `id`, `name`, `effect`, `held_type`, `stance`, `requires`, `also_requires` over one of the entry bases:

    entry_hand            -> INTERACT_HAND(name, PROC_REF(effect), reqs...)           (_AS(stance, ...) with a stance)
    entry_hand/ungated    -> INTERACT_HAND_UNGATED(...)
    entry_item            -> INTERACT_ITEM(name, PROC_REF(effect), reqs...); with held_type INTERACT_INSERT(held, PROC_REF(effect), name, reqs...)
    entry_alt             -> INTERACT_ALT(...)
    entry_drag            -> INTERACT_DRAG(...)

`requires` replaces the base's REQ_INTERACTION_REACH: it lowers only when it still lists it (the rest become the spec's own
requirements, as `also_requires` does). The compact builder (code/datums/interactions/compact.dm) builds the same datum from
the spec: the same entry, category, default action, gate and base requirement; the id is generated (ids are not player-visible).

Residue: no_super (the override drops the chain: a replacement), statement (any other statement), datum_field (a field
above not named), datum_base (another base), datum_used (the datum type is named elsewhere), effect_owner (the effect is
not a proc of T or an ancestor), requires_reach (a `requires` without the base reach).
"""
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _excl import excluded  # noqa: E402

# a type the interaction codemod leaves is not lowered either: the lowered spec would only move its legacy lines
EXCLUDED = {**excluded("lower"), **excluded("interact")}

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASES = {
    "entry_hand": "HAND",
    "entry_hand/ungated": "HAND_UNGATED",
    "entry_item": "ITEM",
    "entry_alt": "ALT",
    "entry_drag": "DRAG",
}
FIELDS = {"id", "name", "effect", "held_type", "stance", "requires", "also_requires", "offered_when"}


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def read(p):
    with open(p, "r", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        return fh.read()


def write(p, text):
    with open(p, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(text)


def block_end(lines, i):
    j = i + 1
    last = i
    while j < len(lines):
        if lines[j].strip() == "":
            j += 1
            continue
        if lines[j][0] in "\t ":
            last = j
            j += 1
            continue
        break
    return last


def split_top(s):
    """Split on top-level commas."""
    out, depth, cur, in_str = [], 0, "", False
    i = 0
    while i < len(s):
        c = s[i]
        if in_str:
            cur += c
            if c == "\\":
                cur += s[i + 1]
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            cur += c
        elif c in "([":
            depth += 1
            cur += c
        elif c in ")]":
            depth -= 1
            cur += c
        elif c == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    if cur.strip():
        out.append(cur.strip())
    return out


def list_items(expr):
    m = re.match(r"^list\((.*)\)$", expr.strip(), re.S)
    if not m:
        return None
    return split_top(m.group(1))


def main(argv):
    check = "--check" in argv
    sites = "--sites" in argv
    dirs = []
    if "--dirs" in argv:
        dirs = [d.rstrip("/") + "/" for d in argv[argv.index("--dirs") + 1:] if not d.startswith("--")]
    files = {}
    for base, _d, fs in os.walk(os.path.join(ROOT, "code")):
        _d[:] = [d for d in _d if d != "_generated"]  # build output (analyze gen), not source
        for f in fs:
            if f.endswith(".dm"):
                p = os.path.join(base, f)
                files[p] = read(p)
    all_text = "\n".join(files.values())

    # every datum interaction type: path -> (file, start, end, base, fields)
    datums = {}
    for p, t in files.items():
        lines = t.splitlines()
        for i, l in enumerate(lines):
            m = re.match(r"^/datum/interaction/((?:entry_hand/ungated|entry_\w+|\w+))/(\w+)\s*(//.*)?$", l)
            if not m:
                continue
            end = block_end(lines, i)
            fields = {}
            ok = True
            j = i + 1
            while j <= end:
                fl = lines[j]
                if fl.strip() == "" or fl.strip().startswith("//"):
                    j += 1
                    continue
                fm = re.match(r"^\t(\w+)\s*=\s*(.*?)\s*(//.*)?$", fl)
                if not fm:
                    ok = False
                    break
                val = fm.group(2)
                # a multi-line value
                while val.count("(") > val.count(")") and j < end:
                    j += 1
                    val += " " + lines[j].strip()
                fields[fm.group(1)] = val
                j += 1
            path = "/datum/interaction/%s/%s" % (m.group(1), m.group(2))
            datums[path] = (p, i, end, m.group(1), fields if ok else None)

    results = []
    for p, t in files.items():
        if dirs and not any(rel(p).startswith(d) for d in dirs):
            continue
        lines = t.splitlines()
        for i, l in enumerate(lines):
            m = re.match(r"^(/[\w/]+)/declare_interactions\(list/into\)\s*$", l)
            if not m:
                continue
            T = m.group(1)
            end = block_end(lines, i)
            body = []
            k = i + 1
            while k <= end:
                s = lines[k].strip()
                if s and not s.startswith("//"):
                    stmt = s
                    while stmt.count("(") > stmt.count(")") and k < end:
                        k += 1
                        stmt += " " + lines[k].strip()
                    body.append(stmt)
                k += 1
            why = None
            if T in EXCLUDED:
                why = "excluded"
            specs = []
            used_datums = []
            if not why and (not body or body[-1] != "..()"):
                why = "no_super"
            for stmt in body[:-1] if not why else []:
                sm = re.match(r"^into\s*\+=\s*(.*)$", stmt)
                if not sm:
                    why = "statement"
                    break
                expr = sm.group(1).strip()
                fm = re.match(r"^dq_interaction_from_spec\(type,\s*(.*)\)$", expr, re.S)
                if fm:
                    specs.append(fm.group(1).strip())
                    continue
                items = list_items(expr)
                if items is None:
                    items = [expr] if re.match(r"^/datum/interaction/[\w/]+$", expr) else None
                if items is None:
                    why = "statement"
                    break
                for it in items:
                    d = datums.get(it)
                    if not d:
                        why = "statement"
                        break
                    dp, di, de, base, fields = d
                    if fields is None or set(fields) - FIELDS:
                        why = "datum_field"
                        break
                    if base not in BASES:
                        why = "datum_base"
                        break
                    if len(re.findall(re.escape(it) + r"\b", all_text)) != 2:  # its definition and this list
                        why = "datum_used"
                        break
                    em = re.match(r"^(/[\w/]+?)/proc/(\w+)$", fields.get("effect", ""))
                    if not em or not (em.group(1) == T or T.startswith(em.group(1) + "/")):
                        why = "effect_owner"
                        break
                    reqs = []
                    if "requires" in fields:
                        rl = list_items(fields["requires"])
                        if rl is None or "REQ_INTERACTION_REACH" not in rl:
                            why = "requires_reach"
                            break
                        reqs += [r for r in rl if r != "REQ_INTERACTION_REACH"]
                    if "also_requires" in fields:
                        rl = list_items(fields["also_requires"])
                        if rl is None:
                            why = "datum_field"
                            break
                        reqs += rl
                    if "offered_when" in fields:
                        # not offered at all unless these hold: interact_declare.py makes each a when() of the op, never a refusal
                        rl = list_items(fields["offered_when"])
                        if rl is None:
                            why = "datum_field"
                            break
                        reqs += ["OFFERED_WHEN(%s)" % r for r in rl]
                    kind = BASES[base]
                    name = fields.get("name", "null")
                    eff = "PROC_REF(%s)" % em.group(2)
                    stance = fields.get("stance")
                    held = fields.get("held_type")
                    if held and kind != "ITEM":
                        why = "datum_field"
                        break
                    if held:
                        args = [held, eff, name] + reqs
                        kind = "INSERT"
                    else:
                        args = [name, eff] + reqs
                    if stance:
                        args = [stance] + args
                        kind += "_AS"
                    specs.append("INTERACT_%s(%s)" % (kind, ", ".join(args)))
                    used_datums.append(it)
                if why:
                    break
            results.append((p, i, end, T, why, specs, used_datums))

    conv = [r for r in results if not r[4]]
    resid = [r for r in results if r[4]]
    print("interaction_datums: %d overrides lower (%d datums)%s; residue %d" % (len(conv), sum(len(r[6]) for r in conv), " (check)" if check else "", len(resid)))
    by = defaultdict(list)
    for r in resid:
        by[r[4]].append(r[3])
    for why, ts in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print("    %-16s %d" % (why, len(ts)))
        if sites:
            for t in ts:
                print("        " + t)
    if check:
        return 0
    edits = defaultdict(list)  # path -> (start, end, new lines)
    for p, i, end, T, _w, specs, used in conv:
        new = ["EXTEND_INTERACTIONS(%s, \\" % T] + ["\t%s, \\" % s for s in specs] + [")"]
        edits[p].append((i, end, new))
        for it in used:
            dp, di, de, _b, _f = datums[it]
            # the datum and the doc comment lines right above it
            s = di
            dl = files[dp].splitlines()
            while s - 1 >= 0 and dl[s - 1].startswith("///"):
                s -= 1
            edits[dp].append((s, de, None))
    for p, es in edits.items():
        text = files[p]
        nl = "\r\n" if "\r\n" in text else "\n"
        trailing = text.endswith(("\n", "\r\n"))
        lines = text.splitlines()
        for s, e, new in sorted(es, key=lambda x: x[0], reverse=True):
            if new is None:
                # drop one blank line after a deleted datum
                e2 = e
                if e2 + 1 < len(lines) and lines[e2 + 1].strip() == "":
                    e2 += 1
                lines[s : e2 + 1] = []
            else:
                lines[s : e + 1] = new
        write(p, nl.join(lines) + (nl if trailing else ""))
        print("    wrote " + rel(p))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
