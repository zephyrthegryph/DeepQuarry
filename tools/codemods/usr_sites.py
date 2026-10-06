#!/usr/bin/env python3
r"""Native input overrides that read `usr` -> input with an actor (doc/rewrite/final_api.html section 6 "Lifecycle forms", form 9;
code/engine/lifeforms/input.dm).

    python tools/codemods/usr_sites.py [--apply] [--sites] [--others] [--paths prefix ...]

  click/drag   `/T/Click(location, control, params)` or `/T/MouseDrop(over_object, ...)` whose body is one statement handing usr to a proc,
               `[return] x(usr, args...)`: the override goes, the type's CAPABILITIES block gets click_on(PROC_REF(x_input)) /
               drag_onto(PROC_REF(x_input)), and `x_input(datum/act/input/A)` calls x with A.actor and the native arguments
               (A.native["location"], A.over, ...).
  tooltip      a MouseEntered()/MouseExited() pair whose bodies are `openToolTip(usr, src, params, title = T, content = C[, theme = V])`
               (after an optional `. = ..()` and QDELETED guard, or a `flick()`) and `closeToolTip(usr, src)`: tooltip(PROC_REF(input_tooltip),
               theme = ...) with `input_tooltip(mob/user)` answering list(T, C); a flick() becomes hover(PROC_REF(input_hovered)).

The ALLOW(sys_usr_outside_verb) that kept the line goes with it. Run `analyze gen` afterwards.
"""
import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmlib import File, block_end, capabilities_index, dm_files, procs_in, statements, split_args, strip_code  # noqa: E402

ONE = re.compile(r"^(?:return\s+|\.\s*=\s*)?(\w+)\(\s*usr\s*(?:,(.*))?\)$")
OPEN_TIP = re.compile(r"^openToolTip\(\s*usr\s*,\s*src\s*,\s*params\s*,(.*)\)$")
CLOSE_TIP = re.compile(r"^closeToolTip\(\s*usr\s*,\s*src\s*\)$")
CLICK_NATIVE = {"location", "control", "params"}
DRAG_NATIVE = {"over_object", "src_location", "over_location", "src_control", "over_control", "params"}


def stmts_of(f, p):
    out = []
    for s in statements(f, p.start + 1, p.end):
        if s.first != s.last:
            return None
        s.code = f.lines[s.first].lstrip()[: len(s.code)]
        out.append(s)
    return out


CLICK_ORDER = ["location", "control", "params"]
DRAG_ORDER = ["over_object", "src_location", "over_location", "src_control", "over_control", "params"]


def native_arg(name, kind, params=None):
    """The context field of the native argument the proc named `name` (by its position in the native signature)."""
    if params is not None and name in params:
        order = CLICK_ORDER if kind == "click" else DRAG_ORDER
        i = params.index(name)
        if i < len(order):
            name = order[i]
    if kind == "drag" and name == "over_object":
        return "A.over"
    if name == "params":
        return "A.params"
    return 'A.native["%s"]' % name


def add_entries(get, cap_idx, rel, ty, entries, f, at):
    where = cap_idx.get(ty)
    lines = ["\t" + e for e in entries]
    if where:
        g = get(where[0])
        hdr = next(k for k, l in enumerate(g.lines) if l.startswith("CAPABILITIES(%s)" % ty))
        end = block_end(g, hdr)
        g.lines[end:end] = lines
        g.dirty = True
        return 0
    f.lines[at:at] = ["CAPABILITIES(%s)" % ty] + lines + [""]
    cap_idx[ty] = (rel, at)
    return len(lines) + 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--sites", action="store_true")
    ap.add_argument("--others", action="store_true")
    ap.add_argument("--paths", nargs="*", default=["code/", "maps/"])
    a = ap.parse_args()
    counts = collections.Counter()
    cap_idx = capabilities_index()
    opened = {}

    def get(rel):
        if rel not in opened:
            opened[rel] = File(rel)
        return opened[rel]

    for rel in dm_files(a.paths, others=a.others):
        if rel.startswith(("code/engine/", "code/__defines/", "code/modules/unit_tests/")):
            continue
        f = get(rel)
        if "usr" not in "\n".join(f.lines):
            continue
        procs = [p for p in procs_in(f) if p.kind is None and p.name in ("Click", "MouseDrop", "MouseEntered", "MouseExited")]
        by_type = collections.defaultdict(dict)
        for p in procs:
            by_type[p.type][p.name] = p
        plans = []  # (start index, [procs to delete], type, entries, new procs)
        for ty, natives in by_type.items():
            # click / drag
            for name, kind in (("Click", "click"), ("MouseDrop", "drag")):
                p = natives.get(name)
                if not p:
                    continue
                st = stmts_of(f, p)
                params = p.params() or []
                if not st or len(st) != 1:
                    continue
                m = ONE.match(st[0].code)
                if not m:
                    continue
                target = m.group(1)
                rest = [x.strip() for x in split_args(m.group(2) or "") if x.strip()]
                if any(not re.fullmatch(r"\w+", x) or x not in params for x in rest):
                    continue
                call = "%s(A.actor%s)" % (target, "".join(", " + native_arg(x, kind, params) for x in rest))
                handler = "%s_input" % name.lower()
                entry = ("click_on(PROC_REF(%s))" if kind == "click" else "drag_onto(PROC_REF(%s))") % handler
                body = ["/// The native %s's actor and arguments, handed over by the engine (%s, code/engine/lifeforms/input.dm)." % (name, entry.split("(")[0] + "()"),
                        "%s/proc/%s(datum/act/input/A)" % (ty, handler), "\treturn %s" % call]
                plans.append((p.start, [p], ty, [entry], body))
                counts[kind] += 1
                if a.sites:
                    print("%s\t%s:%d\t%s" % (kind, rel, p.start + 1, call))
            # tooltip
            pe, px = natives.get("MouseEntered"), natives.get("MouseExited")
            if pe and px:
                se, sx = stmts_of(f, pe), stmts_of(f, px)
                if se and sx:
                    codes = [s.code for s in se]
                    flick = None
                    tip = None
                    ok = True
                    for c in codes:
                        if c in (". = ..()", "..()") or c.startswith("if(QDELETED(src))") or c == "return":
                            continue
                        if c.startswith("if(!QDELETED(src))"):
                            continue
                        if c.startswith("flick("):
                            flick = c
                            continue
                        mt = OPEN_TIP.match(c)
                        if mt:
                            tip = mt.group(1)
                            continue
                        ok = False
                    xcodes = [s.code for s in sx if s.code not in ("return ..()", "..()", ". = ..()")]
                    if ok and tip and len(xcodes) == 1 and CLOSE_TIP.match(xcodes[0]):
                        named = {}
                        for part in split_args(tip):
                            k, _, v = part.partition("=")
                            named[k.strip()] = v.strip()
                        if set(named) <= {"title", "content", "theme"} and "content" in named:
                            entries = []
                            theme = named.get("theme")
                            if theme and re.fullmatch(r"\w+", theme):
                                entries.append("tooltip(PROC_REF(input_tooltip), theme = nameof(%s))" % theme)
                            elif theme:
                                entries.append("tooltip(PROC_REF(input_tooltip), theme = %s)" % theme)
                            else:
                                entries.append("tooltip(PROC_REF(input_tooltip))")
                            body = ["/// The tooltip the hovering mob sees (tooltip(), code/engine/lifeforms/input.dm).",
                                    "%s/proc/input_tooltip(mob/user)" % ty, "\treturn list(%s, %s)" % (named.get("title", "name"), named["content"])]
                            if flick:
                                entries.append("hover(PROC_REF(input_hovered))")
                                body += ["", "/// Plays its hover animation when the mouse enters (hover(), code/engine/lifeforms/input.dm).",
                                         "%s/proc/input_hovered(datum/act/input/A)" % ty, "\tif(A.entered)", "\t\t" + flick]
                            plans.append((min(pe.start, px.start), [pe, px], ty, entries, body))
                            counts["tooltip"] += 1
                            if a.sites:
                                print("tooltip\t%s:%d\t%s" % (rel, pe.start + 1, ty))
        if not a.apply or not plans:
            continue
        # Bottom-up: delete the natives, write the handlers where the first one was, then the block entries.
        for start, dead, ty, entries, body in sorted(plans, key=lambda x: -x[0])[:1]:  # one per file per pass: rerun until nothing is left
            for p in sorted(dead, key=lambda p: -p.start):
                s0 = p.start
                if s0 > 0 and "ALLOW(sys_usr_outside_verb)" in f.lines[s0 - 1] and f.lines[s0 - 1].lstrip().startswith("//"):
                    s0 -= 1
                e0 = p.end
                while e0 < len(f.lines) and f.lines[e0].strip() == "":
                    e0 += 1
                f.lines[s0:e0] = []
            at = min(p.start for p in dead)
            f.lines[at:at] = body + [""]
            add_entries(get, cap_idx, rel, ty, entries, f, at)
        f.dirty = True
    if a.apply:
        for g in opened.values():
            g.save()
    print("usr_sites: %s" % dict(counts.most_common()))


if __name__ == "__main__":
    main()
