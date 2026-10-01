"""sys_lint module: the reactive-proc rules of the DX framework (design review H4, H5, M3, M5).

Rules:

  dx_untracked_read (H4)
      A reactive proc reads ANOTHER object's var that nothing tracks. Reactive procs re-run only
      when their own object is marked changed(); a var of another object changes without marking
      this one, so the read goes stale (a missed redraw, a missed wake). Reactive procs are:
        - draw(datum/look/look), should_run(), hidden_verbs(), tgui_data() on any type;
        - draw/gate/ui_data/examine/hidden_verbs on a /datum/capability subtype;
        - any proc named by `needs = PROC_REF(x)` / `TYPE_PROC_REF(T, x)` somewhere in the tree.
      A read is fine when the var is declared `TRACKED(type, var)` (or TRACKED_BRIDGED) or registered with
      `SETTER(type, var)` somewhere (its setter calls changed()), or its root is a relation var
      declared with a watch (a REL* declaration or rel() call naming the var with WATCH / watch =).
      A proc merely named set_<var> doesn't count: only a registered setter is known to mark.
  dx_reactive_write (H5)
      A reactive proc (the same set) writes state: an assignment, compound assignment or ++/-- whose
      target is a var of src (`x = `, `src.x = `), a member of anything (`a.b = `, `a.b += `), or an
      index of something that isn't a local or a parameter; a list-mutating member call (Add, Cut,
      Remove, Insert, Swap, Splice, RemoveAll) on something that isn't; or a call to a state writer
      (changed, cap_set, timed_set/timed_cancel, own_*/rel_* writers, om_set, qdel, forceMove,
      set_light, set_<x>() on anything but the look builder, update_icon, add_fingerprint,
      to_chat, playsound). Allowed: locals and parameters (`data[k] = v` in ui_data), the return
      value (`. = ..()`, `.[k] = v`, `. += x`) and the look builder (`look.*`). This rule stands in
      for DreamChecker's SHOULD_BE_PURE, which these hooks can't carry: its purity is transitive over
      every write, and every capability lookup (caps_of/cap_of/cap_data) memoizes through a
      shared_cache, and every look.* call writes the builder.
  dx_caps_instance_read (M3)
      capabilities() reads an instance var (`src.x`, or a bare name that is a var of the type, its
      path ancestors or a DM builtin). capabilities() is built ONCE per type, so the first
      instance's value would apply to every instance. Per-instance settings are holder vars the
      capability reads at run time (design review H1).
  dx_timed_write (M5)
      A var passed to timed_set(D, nameof(v), ...) is written somewhere other than timed_set() or
      its own set_<v>() proc. A manual write between timed_set() and its revert is clobbered when
      the revert fires.

Static approximations (documented limits):
  - Types are unknown, so tracking is by VAR NAME: TRACKED(/obj/a, charge) also covers a read of
    `charge` on an unrelated type. SETTER(T, v) counts the same way.
  - Own reads: `src.x`, a bare var name, and `holder.x` inside a capability proc (the holder is the
    capability's own object: the dispatcher marks it), and reads through a local alias of either
    (`var/obj/machinery/M = holder` / `= src`). In `a.b.c`, b is own only when a is own; a bare
    `cell.charge` reads `charge` on another object.
  - Context roots are not state: user, held, callee (DM's proc reflection), look, entry, data, ui, state, world, global, GLOB (only
    its member after the global var), subsystem/define roots (SSx, ALL_CAPS of 3+ chars), and locals
    holding a capability flyweight or a per-type shared definition (typed /datum/capability/..., or
    `= cap_of(...)` / `= ladder_for(...)` / `= caps_all(...)`: config), and locals read off those.
    Locals holding the holder's capability state (`= cap_data(...)` / `= cap_data?[...]`) are own.
    `initial(x.y)` is a compile-time default, not a read.
  - Reads through `reagents` are fresh: the reagent holder marks its atom on every change (review 2
    M8). A watched relation var works the same way.
  - Chains after a call or an index (`get_area(src).power`, `L[1].x`) are not seen; `len`, `type`
    and `parent_type` are never state.
  - The core has no relation watch option yet, so until one ships no relation counts as watched.
  - M5 writes: a bare `v = ` counts only in procs of the timed type, its ancestors or subtypes
    (and not where v is a param or local); `X.v = ` counts anywhere (name-based).
One site per line. Baselines: tools/ci/sys_baseline/dx_reactive.txt; target 0.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _dx_dm as dm  # noqa: E402

RULES = {
    "dx_untracked_read": "declare the var TRACKED(type, var) (or give it a set_<var>()), or read it through a watched relation (design review H4)",
    "dx_reactive_write": "reactive procs (draw, should_run, hidden_verbs, tgui_data, a capability's draw/gate/ui_data/examine, needs procs) write nothing: move the write to the handler or setter that changes the state (design review H5)",
    "dx_caps_instance_read": "capabilities() is per type: read the instance var inside the capability at run time instead (design review M3, H1)",
    "dx_timed_write": "write this var only through timed_set() or its set_<var>() proc (design review M5)",
}

REACTIVE_ANY = {"should_run", "hidden_verbs", "tgui_data"}
REACTIVE_CAP = {"draw", "gate", "ui_data", "examine", "hidden_verbs"}
CONTEXT_ROOTS = {"src", "user", "held", "look", "entry", "data", "ui", "state", "world", "global",
                 "usr", "GLOB", "config", "callee"}
# Relation vars whose target marks its owner changed on every write (review 2 M8: the reagent
# holder calls changed(my_atom)), so a read through them stays fresh.
MARKING_RELATIONS = frozenset({"reagents"})
# Per-proc local classification (own_roots_of):
#   var/datum/capability/x/C ...                  a capability flyweight: per-type config (context)
#   var/T/C = cap_of(...) / = ladder_for(...)     a per-type shared definition (context)
#   var/T/X = C.anything...  (C context)          derived from config (context)
#   var/T/D = [holder.]cap_data(...) / ?[...]     the holder's own capability state (own)
#   var/T/R = [holder.]reagents                   a marking relation (reads through it are fresh)
CAP_TYPED = re.compile(r"\bvar/datum/capability(?:/\w+)*/(\w+)\b")
LOCAL_FROM = re.compile(r"\bvar/(?:[\w/]+/)?(\w+)\s*=\s*(.+)$")
CONFIG_CALLS = re.compile(r"^(?:cap_of|ladder_for|caps_of|caps_all)\s*\(")
CAP_DATA_EXPR = re.compile(r"^(?:(\w+)\s*\??\.\s*)?cap_data\s*(?:\(|\??\[)")
RELATION_EXPR = re.compile(r"^(?:(\w+)\s*\??\.\s*)?(\w+)\s*$")
INITIAL_CALL = re.compile(r"\binitial\s*\(")
NEVER_STATE = {"len", "type", "parent_type"}
# Subsystems (SSair) and defines (ALL_CAPS, 3+ chars); single-letter locals (M, C, H) are objects.
GLOBAL_ROOT = re.compile(r"^(?:SS[a-z]\w*|[A-Z][A-Z0-9_]{2,})$")

NEEDS = re.compile(r"\bneeds\s*=\s*(?:PROC_REF\(\s*(\w+)\s*\)|TYPE_PROC_REF\(\s*[/\w]+\s*,\s*(\w+)\s*\))")
TRACKED = re.compile(r"^\s*(?:TRACKED(?:_BRIDGED)?\(\s*/[\w/]+\s*,\s*(\w+)\s*[,)]|SETTER\(\s*/[\w/]+\s*,\s*(\w+)\s*\))")
ALIAS = re.compile(r"\bvar/(?:[\w/]+/)?(\w+)\s*=\s*(\w+)\s*$")
WATCH_REL = re.compile(r"^\s*REL\w*\(\s*/[\w/]+\s*,\s*(\w+)\b[^\n]*\bWATCH\w*|\brel\(\s*nameof\(\s*(?:[\w.]+\.|/[\w/]+::)?(\w+)\s*\)[^\n]*\bwatch\s*=")
CHAIN = re.compile(r"(?<![\w.\]\)\"'/:])([A-Za-z_]\w*)((?:\s*\??\.\s*[A-Za-z_]\w*)+)")
SEGMENT = re.compile(r"\??\.\s*([A-Za-z_]\w*)")
TIMED = re.compile(r"(?<![\w./:])timed_set\s*\(")
NAMEOF_VAR = re.compile(r"^\s*nameof\(\s*(?:[\w.]+\.|/[\w/]+::)?(\w+)\s*\)\s*$")
ASSIGN_OP = r"\s*(?:=(?!=)|\+=|-=|\*=|/=|\|=|&=|\^=|<<=|>>=|\+\+|--)"
HIDE_ARGS = re.compile(r"\b(?:nameof|PROC_REF|TYPE_PROC_REF|GLOBAL_PROC_REF|TYPE_VERB_REF|VERB_REF)\s*\(")


def is_reactive(proc, needs_names):
    if proc.path.startswith("/datum/capability"):
        return proc.name in REACTIVE_CAP or proc.name in needs_names
    if proc.name == "draw":
        return any("look" in p for p in proc.params)
    return proc.name in REACTIVE_ANY or proc.name in needs_names


def foreign_reads(text, own_roots, context=frozenset(), relations=frozenset()):
    """[var name] read on another object in one sanitized line. A var read through a relation that
    marks its reader (`reagents.total_volume`, a watched `area.power`) is not foreign."""
    out = []
    for m in CHAIN.finditer(text):
        root = m.group(1)
        segs = SEGMENT.findall(m.group(2))
        after = text[m.end():].lstrip()
        if after.startswith("("):
            segs = segs[:-1]  # the last segment is a proc call
        if not segs:
            continue
        if root == "GLOB" or root in own_roots:
            first_foreign = 1  # a global var, or an own var: only what is read THROUGH it is foreign
        elif GLOBAL_ROOT.match(root) or root in CONTEXT_ROOTS or root in context:
            continue  # subsystems/defines, context parameters and capability config are not state
        else:
            first_foreign = 0
        prev = root
        for k, name in enumerate(segs):
            if k >= first_foreign and name not in NEVER_STATE and prev not in relations:
                out.append(name)
            prev = name
    return out


def blank_calls(text, pattern):
    """text with the argument lists of the calls pattern matches blanked out."""
    chars = list(text)
    for m in pattern.finditer(text):
        end = dm.match_paren(text, m.end() - 1)
        if end > 0:
            for k in range(m.end(), end):
                chars[k] = " "
    return "".join(chars)


def caps_reads(proc, table):
    """(line, name) for each instance read in a capabilities() body."""
    own = dm.vars_of(table, proc.path)
    local = set(proc.params)
    for _n, text in proc.lines():
        for m in re.finditer(r"\bvar/(?:[\w/]+/)?(\w+)", text):
            local.add(m.group(1))
    out = []
    for number, text in proc.lines():
        text = blank_calls(text, HIDE_ARGS)
        hit = None
        for m in re.finditer(r"(?<![\w./:])(src\s*\??\.\s*)?([A-Za-z_]\w*)", text):
            name = m.group(2)
            if m.group(1):
                if not text[m.end():].lstrip().startswith("("):
                    hit = name
                    break
                continue
            if name == "src" or name in local or name not in own:
                continue
            rest = text[m.end():]
            if rest.lstrip().startswith("("):
                continue  # a call
            if re.match(r"\s*=(?!=)", rest) and text[:m.start()].count("(") > text[:m.start()].count(")"):
                continue  # a named argument key
            if text[:m.start()].rstrip().endswith("var"):
                continue
            hit = name
            break
        if hit:
            out.append((number, hit))
    return out


def timed_vars(procs_list, raw_lines_of):
    """{var name: set(type paths)} for every timed_set(D, nameof(v)) / timed_set(D, "v")."""
    out = {}
    for proc in procs_list:
        for number, text in proc.lines():
            for m in TIMED.finditer(text):
                args = dm.call_args(text, m.end() - 1)
                if not args or len(args) < 2:
                    continue
                name = None
                nm = NAMEOF_VAR.match(args[1])
                if nm:
                    name = nm.group(1)
                else:
                    raw = raw_lines_of(proc.rel)[number - 1]
                    lit = re.search(r"timed_set\s*\([^,]*,\s*\"(\w+)\"", raw)
                    name = lit.group(1) if lit else None
                if name:
                    out.setdefault(name, set()).add(proc.path)
    return out


def related(a, b):
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def timed_writes(proc, timed):
    """(line, name) for each write to a timed var outside timed_set/its setter."""
    out = []
    local = set(proc.params)
    for _n, text in proc.lines():
        for m in re.finditer(r"\bvar/(?:[\w/]+/)?(\w+)", text):
            local.add(m.group(1))
    for number, text in proc.lines():
        if TIMED.search(text):
            continue
        for name, paths in timed.items():
            if proc.name == "set_" + name:
                continue
            dotted = re.search(r"\??\.\s*" + name + r"\b" + ASSIGN_OP, text)
            bare = None
            if name not in local and any(related(proc.path, p) for p in paths):
                bare = re.search(r"(?<![\w.])" + name + r"\b" + ASSIGN_OP, text) or re.search(r"(?:\+\+|--)\s*" + name + r"\b", text)
                if bare and re.search(r"\bvar/(?:[\w/]+/)?" + name + r"\b", text):
                    bare = None
            if dotted or bare:
                out.append((number, name))
                break
    return out



WRITER_CALL = re.compile(r"(?<![\w./:])(?:changed|cap_set|timed_set|timed_cancel|own_set|own_add|own_put|own_take|own_take_all|own_take_member|own_remove|own_clear|own_transfer|own_move|rel_set|rel_add|rel_remove|rel_clear|om_set|qdel|forceMove|set_light|update_icon|add_fingerprint|to_chat|playsound|set_\w+)\s*\(")
MEMBER_WRITER = re.compile(r"(?<![\w.])([A-Za-z_]\w*|\.)((?:\s*\??\.\s*[A-Za-z_]\w*)*?)\s*\??\.\s*(set_\w+|forceMove|qdel|set_light|update_icon|add_fingerprint|Add|Cut|Remove|RemoveAll|Insert|Swap|Splice)\s*\(")
WRITE_OP = re.compile(r"(?<![=!<>+\-*/|&^%])(?:=(?!=)|\+=|-=|\*=|/=|\|=|&=|\^=|<<=|>>=)")
INCDEC = re.compile(r"(\+\+|--)\s*([A-Za-z_.][\w.?\[\]]*)|([A-Za-z_.][\w.?\[\]\"]*?)\s*(\+\+|--)")
LOCAL_DECL = re.compile(r"\bvar/(?:[\w/]+/)?(\w+)")


def top_level_ops(text):
    """Offsets of assignment operators outside parentheses/brackets (so named arguments and for()
    headers don't count)."""
    out = []
    depth = 0
    k = 0
    while k < len(text):
        c = text[k]
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        elif depth == 0:
            m = WRITE_OP.match(text, k)
            if m and (k == 0 or text[k - 1] not in "=!<>+-*/|&^%"):
                out.append(k)
                k = m.end()
                continue
        k += 1
    return out


def write_target_bad(target, locals_):
    """True when an assignment target is state (not a local, parameter, `.` or the look builder)."""
    target = target.strip()
    if not target or target.startswith("var/") or re.search(r"\bvar/", target):
        return False
    m = re.match(r"^(\.|[A-Za-z_]\w*)", target)
    if not m:
        return False
    root = m.group(1)
    rest = target[m.end():].strip()
    if root == "." or root == "look":
        return False
    if not rest:
        return root not in locals_  # a bare var: a src var unless it is a local or parameter
    if rest.startswith("["):
        return root not in locals_ and root != "src"  # an index of a local/param list is fine
    return True  # a member write: another object's (or src's) state


def reactive_writes(proc):
    """Line numbers where a reactive proc writes state."""
    declared = set()
    for _n, text in proc.lines():
        for m in LOCAL_DECL.finditer(text):
            declared.add(m.group(1))
    locals_ = declared | set(proc.params)
    # Member calls may mutate a local (a list built here), the output list and the builder only:
    # holder.set_x() or user.Add() mutate the holder / the user.
    mutable = declared | {".", "look", "data"}
    out = []
    for number, text in proc.lines():
        code = text
        bad = False
        for m in WRITER_CALL.finditer(code):
            bad = True
            break
        if not bad:
            for m in MEMBER_WRITER.finditer(code):
                root, through = m.group(1), m.group(2).strip()
                # `L.Add(x)` on a local list and `look.set_icon()` are fine; `holder.verbs.Remove()`
                # or `cell.set_charge()` mutate another object.
                if through or root not in mutable:
                    bad = True
                    break
        if not bad:
            stripped = code.strip()
            if not stripped.startswith(("var/", "for(", "for (")):
                for k in top_level_ops(code):
                    # the target is the text since the statement start (after `if(...)` etc.)
                    lhs = code[:k]
                    lhs = re.split(r"[;{]|\bin\b|^\s*(?:if|while|else if)\s*\(.*\)\s*", lhs)[-1]
                    if write_target_bad(lhs, locals_):
                        bad = True
                        break
        if not bad:
            for m in INCDEC.finditer(code):
                target = m.group(2) or m.group(3)
                if target and write_target_bad(target, locals_):
                    bad = True
                    break
        if bad:
            out.append(number)
    return out


def own_roots_of(proc, relations=MARKING_RELATIONS):
    """(own roots, context roots, relation roots) of a proc. Own: src, the holder (a capability
    proc's first parameter), local aliases of either, and locals holding the holder's capability
    state. Context: capability flyweights and per-type shared definitions (config, not state), and
    locals derived from them. Relations: locals aliasing a marking relation (`= holder.reagents`)."""
    roots = {"src"}
    context = set()
    rels = set()
    if proc.path.startswith("/datum/capability") and proc.params:
        roots.add(proc.params[0])
    for _n, text in proc.lines():
        for m in CAP_TYPED.finditer(text):
            context.add(m.group(1))
        m = LOCAL_FROM.search(text.rstrip())
        if not m:
            continue
        name, expr = m.group(1), m.group(2).strip()
        if expr in roots:
            roots.add(name)
        elif expr in context or expr in CONTEXT_ROOTS:
            context.add(name)  # `var/datum/interaction/capability/E = entry`: still context
        elif CAP_DATA_EXPR.match(expr) and (not CAP_DATA_EXPR.match(expr).group(1) or CAP_DATA_EXPR.match(expr).group(1) in roots):
            roots.add(name)
        elif CONFIG_CALLS.match(expr):
            context.add(name)
        elif re.match(r"^(\w+)\s*\??\.", expr) and re.match(r"^(\w+)", expr).group(1) in context:
            context.add(name)
        else:
            r = RELATION_EXPR.match(expr)
            if r and r.group(2) in relations and (not r.group(1) or r.group(1) in roots):
                rels.add(name)
    return roots, context, rels


def analyse(files):
    tree = dm.tree(files)
    cleaned, raw = tree.clean, tree.raw
    procs_list = tree.procs
    table = tree.type_vars
    needs_names, tracked, watched = set(), set(), set()
    for rel, clean in cleaned.items():
        for line in clean:
            if "needs" in line:
                for m in NEEDS.finditer(line):
                    needs_names.add(m.group(1) or m.group(2))
            if "TRACKED" in line or "SETTER(" in line:
                t = TRACKED.match(line)
                if t:
                    tracked.add(t.group(1) or t.group(2))
            if "REL" in line or "rel(" in line:
                w = WATCH_REL.search(line)
                if w:
                    watched.add(w.group(1) or w.group(2))
    out = {rule: [] for rule in RULES}
    for proc in procs_list:
        if is_reactive(proc, needs_names):
            relations = watched | MARKING_RELATIONS
            own_roots, context, local_rels = own_roots_of(proc, relations)
            relations = relations | local_rels
            for number, text in proc.lines():
                text = blank_calls(text, INITIAL_CALL)  # initial(x.y) is a compile-time default
                bad = [name for name in foreign_reads(text, own_roots, context, relations) if name not in tracked]
                if bad:
                    out["dx_untracked_read"].append((proc.rel, number))
            for number in reactive_writes(proc):
                out["dx_reactive_write"].append((proc.rel, number))
        if proc.name == "capabilities" and proc.path != "/atom":
            for number, _name in caps_reads(proc, table):
                out["dx_caps_instance_read"].append((proc.rel, number))
    timed = timed_vars(procs_list, lambda rel: raw[rel])
    if timed:
        for proc in procs_list:
            for number, _name in timed_writes(proc, timed):
                out["dx_timed_write"].append((proc.rel, number))
    return out


def scan(files):
    return analyse(files)


FIXTURE = """
/obj/cap_fixture/meter
	var/obj/item/cell/cell
	var/level = 1
	var/emp_disabled = FALSE

/obj/item/cell
	var/charge = 0
	var/maxcharge = 100
	var/rigged = FALSE
	var/sealed = FALSE
	var/label_text
TRACKED(/obj/item/cell, charge)
SETTER(/obj/item/cell, sealed)

/obj/item/cell/proc/set_label_text(value)
	label_text = value

/obj/cap_fixture/meter/draw(datum/look/look)
	..()
	look.gauge("charge", cell.charge / 100)
	look.overlay("rigged", when = cell.rigged)
	look.overlay("sealed", when = cell.sealed)
	look.overlay("label", when = cell.label_text)
	look.state(level ? "on" : "off")

/obj/cap_fixture/meter/should_run()
	return cell?.maxcharge > 0 && src.level

/obj/cap_fixture/meter/proc/has_cell(mob/user)
	return cell.rigged

/obj/cap_fixture/meter/proc/can_pour(mob/user, obj/item/held)
	var/datum/capability/meter/C = cap_of(src, /datum/capability/meter)
	var/datum/meter_data/D = cap_data?[C.key]
	var/datum/meter_data/E = src.cap_data?[C.key]
	if(E.pours)
		return FALSE
	if(held.force || C.max_pours <= D.pours)
		return FALSE
	var/datum/reagents/R = reagents
	var/datum/construction_ladder/built = ladder_for(src)
	var/datum/ladder_stage/stage = built.stage_named("x")
	for(var/datum/capability/K as anything in caps_all(src))
		if(K.cadence && stage.icon && R.total_volume && initial(cell.charge))
			return TRUE
	return reagents?.total_volume > 0

/obj/cap_fixture/meter/capabilities()
	. = ..()
	. += cap_slot(nameof(cell), /obj/item/cell, needs = PROC_REF(has_cell))
	. += cap_hand("Pour", PROC_REF(pour), needs = PROC_REF(can_pour))
	. += cap_gauge(level = level)
	. += cap_lock(access = src.req_access)
	. += cap_panel(name = "panel")
	var/list/extra = list()
	. += extra

/datum/capability/meter/draw(atom/holder, datum/look/look)
	var/obj/cap_fixture/meter/M = holder
	var/obj/item/cell/C = M.cell
	look.overlay("x", when = holder.level)
	look.overlay("y", when = M.level)
	look.overlay("z", when = "[holder.cell.charge]")
	look.overlay("w", when = C.rigged)

/datum/capability/meter/gate(atom/holder, mob/user, datum/interaction/entry)
	var/datum/interaction/capability/E = entry
	if(user.stat || entry.behind || E.cap)
		return "no"

/datum/capability/meter/ui_data(atom/holder, mob/user, list/data)
	var/list/rows = list()
	rows += "x"
	data["rows"] = rows
	for(var/i = 1, i <= 3, i++)
		rows[i] = i
	holder.last_ui = world.time
	last_holder = holder
	changed(holder)
	holder.verbs.Remove(/obj/proc/x)
	look_like(value = 1)
	rows.Cut(1, 2)
	holder.set_dir(NORTH)

/obj/cap_fixture/meter/tgui_data(mob/user)
	. = ..()
	.["level"] = level
	. += list("x" = 1)
	level++
	src.cell.set_charge(5)
	if(level == 2)
		return

/obj/cap_fixture/meter/proc/zap()
	timed_set(src, nameof(emp_disabled), TRUE, for_time = 10 SECONDS)
	emp_disabled = FALSE

/obj/cap_fixture/meter/proc/set_emp_disabled(value)
	emp_disabled = value

/obj/cap_fixture/meter/proc/other(obj/cap_fixture/meter/M)
	M.emp_disabled = TRUE
	var/emp_disabled = 3
	emp_disabled = 4
"""


def selftest():
    lines = FIXTURE.split("\n")
    got = analyse([("x.dm", lines)])
    by = {rule: sorted(n for _r, n in found) for rule, found in got.items()}

    def at(snippet, nth=0):
        hits = [k + 1 for k, line in enumerate(lines) if snippet in line]
        return hits[nth]

    # H4: cell.rigged in draw and in the needs proc, cell.label_text (set_label_text() is not a
    # registered setter), C.rigged in the capability draw (C is the holder's cell, not an alias).
    # cell.charge is TRACKED and cell.sealed has a SETTER; holder.level and M.level (M aliases the
    # holder) are own; holder.cell.charge is tracked; user./entry. are context.
    assert by["dx_untracked_read"] == sorted([at('when = cell.rigged'), at("when = cell.label_text"),
                                              at("return cell?.maxcharge"), at("return cell.rigged"),
                                              at("when = C.rigged")]), by
    # H5: ui_data writes holder.last_ui, its own var last_holder, calls changed() and mutates
    # holder.verbs; tgui_data's level++ and cell.set_charge(). Locals, the data param, `.`, loop
    # counters, named arguments and compares are fine.
    assert by["dx_reactive_write"] == sorted([at("holder.last_ui = world.time"), at("last_holder = holder"),
                                              at("changed(holder)"), at("holder.verbs.Remove"), at("holder.set_dir(NORTH)"),
                                              at("\tlevel++"), at("src.cell.set_charge(5)")]), by
    # M3: `level = level` reads level; src.req_access reads; nameof(cell)/PROC_REF(has_cell), the
    # named keys and the local `extra` do not.
    assert by["dx_caps_instance_read"] == sorted([at(". += cap_gauge(level = level)"), at("cap_lock(access = src.req_access)")]), by
    # M5: the bare write in zap(), and M.emp_disabled in other(); not the setter, not the local.
    assert by["dx_timed_write"] == sorted([at("\temp_disabled = FALSE"), at("M.emp_disabled = TRUE")]), by
    return "dx_reactive"
