"""sys_lint module: appearance outputs write no state and play no sounds (G12; doc/rewrite/look.md section 3).

draw(datum/look/look) is a reactive proc already: dx_reactive's dx_reactive_write flags a state write, a
to_chat() or a playsound() in it (tools/ci/sys_rules/dx_reactive.py). This module holds the legacy appearance
procs to the same rule: appearance_overlays() and any proc a DECLARE_APPEARANCE_PROC(...) row names build a look
outside draw(), run on every refresh (possibly more than once per change), and a write or a sound there repeats on
each redraw (vent_pump played its sounds from appearance_overlays()) or feeds the refresh back into itself.

Rule:
  dx_appearance_side_effect   an appearance proc writes state (an assignment to a var of src or of another
                              object, a list mutation on one), plays a sound, messages someone, or calls a state
                              writer (changed, cap_set, set_<x>(), qdel, forceMove, ...): the same test as
                              dx_reactive_write. Move the effect to the handler or setter that changes the state.
                              A plain write of the holder's own appearance vars (icon_state, icon, overlays,
                              underlays, color, alpha, layer, plane, transform, pixel offsets) is what a legacy
                              appearance proc is for and is not counted; draw() replaces all of them.

Baseline: tools/ci/sys_baseline/dx_look_side_effects.txt, the legacy offenders; shrink-only, target 0.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _dx_dm as dm  # noqa: E402
import dx_reactive as reactive  # noqa: E402

RULES = {
    "dx_appearance_side_effect": "appearance procs (appearance_overlays, DECLARE_APPEARANCE_PROC rows; draw() is dx_reactive_write's) write no state and play no sound: move it to the handler or setter that changes the state (G12)",
}

APPEARANCE_PROC_ROW = re.compile(r"\bDECLARE_APPEARANCE_PROC\s*\(\s*/[\w/]+\s*,\s*(?:TYPE_PROC_REF\(\s*[/\w]+\s*,\s*(\w+)\s*\)|PROC_REF\(\s*(\w+)\s*\))")
ALWAYS = {"appearance_overlays"}
# `icon_state = "x"` / `src.overlays += y`: the proc's own output, not a side effect (see the module doc).
APPEARANCE_WRITE = re.compile(r"^\s*(?:src\s*\.\s*)?(?:icon_state|icon|overlays|underlays|color|alpha|layer|plane|transform|pixel_x|pixel_y|pixel_w|pixel_z)\s*(?:=(?!=)|\+=|-=|\|=)")


def appearance_proc_names(cleaned):
    names = set(ALWAYS)
    for _rel, clean in cleaned.items():
        for line in clean:
            if "DECLARE_APPEARANCE_PROC" not in line:
                continue
            for m in APPEARANCE_PROC_ROW.finditer(line):
                names.add(m.group(1) or m.group(2))
    return names


def has_writer_call(text):
    return bool(reactive.WRITER_CALL.search(text) or reactive.MEMBER_WRITER.search(text))


def scan(files):
    out = {rule: [] for rule in RULES}
    tree = dm.tree(files)
    names = appearance_proc_names(tree.clean)
    for proc in tree.procs:
        if proc.name not in names or proc.path in ("/atom", "/datum"):
            continue
        lines = dict(proc.lines())
        for number in reactive.reactive_writes(proc):
            text = lines.get(number, "")
            if APPEARANCE_WRITE.match(text) and not has_writer_call(text):
                continue
            out["dx_appearance_side_effect"].append((proc.rel, number))
    return out


FIXTURE = """
/obj/machinery/vent/appearance_overlays()
	var/list/parts = list()
	parts += "on"
	icon_state = "vent"
	if(welded)
		playsound(src, 'sound/weld.ogg', 50)
	last_state = "on"
	return parts

/obj/machinery/quiet/appearance_overlays()
	var/list/parts = list()
	parts += "idle"
	return parts

DECLARE_APPEARANCE_PROC(/obj/machinery/custom, TYPE_PROC_REF(/obj/machinery/custom, custom_look), list())

/obj/machinery/custom/proc/custom_look()
	icon_state = "custom"
	on = TRUE
	return list()
"""


def selftest():
    lines = FIXTURE.split("\n")
    found = scan([("code/fixture.dm", lines)])["dx_appearance_side_effect"]
    got = sorted(number for _rel, number in found)
    bad = ("\t\tplaysound(src, 'sound/weld.ogg', 50)", "\tlast_state = \"on\"", "\ton = TRUE")
    want = sorted(lines.index(text) + 1 for text in bad)
    assert got == want, (got, want)
    return True
