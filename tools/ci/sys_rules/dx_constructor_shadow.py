"""sys_lint module: type procs that shadow a capability constructor (framework review 2, H7).

Inside capabilities(), a bare call binds to src's own proc before the global one, so a type proc
named like a constructor silently replaces it on that type (airlocks have lock(), machinery has
powered()). Every library constructor is therefore named cap_<noun>, and no type proc or verb may
reuse such a name:

    /obj/machinery/door/airlock/proc/cap_lock()      // shadows /proc/cap_lock inside capabilities()

Rule:
  dx_constructor_shadow   a proc or verb defined on a type (a new proc, a verb or an override) whose
                          name is a global /proc/cap_* in the tree, or a capability preset name
                          (PRESETS below, plus every global proc defined in a library presets file,
                          code/datums/capabilities/library/preset*.dm).

The baseline (tools/ci/sys_baseline/dx_constructor_shadow.txt) holds the legacy sites; target 0.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _dx_dm as dm  # noqa: E402

RULES = {
    "dx_constructor_shadow": "rename the type proc: it shadows a global capability constructor or preset inside capabilities() (framework review 2, H7)",
}

# The design's preset names (final_design.md §2), reserved before the presets land.
PRESETS = {"machine_basics", "wall_machine", "floor_machine", "computer"}
PRESET_FILES = "code/datums/capabilities/library/preset"


def reserved_names(procs_list):
    names = set(PRESETS)
    for proc in procs_list:
        if proc.is_global() and (proc.name.startswith("cap_") or proc.rel.startswith(PRESET_FILES)):
            names.add(proc.name)
    return names


def scan_procs(procs_list):
    names = reserved_names(procs_list)
    return [(p.rel, p.line) for p in procs_list if not p.is_global() and p.name in names]


def scan(files):
    return {"dx_constructor_shadow": scan_procs(dm.tree(files).procs)}


FIXTURE = """
/proc/cap_lock(list/access, behind = NONE)
	return
/proc/cap_has(atom/A, bits)
	return
/obj/machinery/door/airlock/proc/cap_lock()
	return
/obj/machinery/door/airlock/cap_has(bits)
	return
/obj/machinery/door/airlock/verb/cap_lock_verb()
	set name = "Lock"
/atom/proc/cap_cover_toggle(mob/user)
	return
/obj/item/barcodescanner/proc/computer() as /obj/machinery/librarycomp
	return
/obj/machinery/door/airlock/proc/lock(forced = 0)
	return
"""


def selftest():
    lines = FIXTURE.split("\n")
    got = sorted(n for _r, n in scan_procs(dm.procs([("x.dm", lines)])))

    def at(snippet):
        return [k + 1 for k, line in enumerate(lines) if snippet in line][0]
    # cap_lock and cap_has are global cap_* procs; computer is a preset name. cap_cover_toggle has
    # no global twin, cap_lock_verb is another name, lock() is no longer a constructor.
    assert got == sorted([at("airlock/proc/cap_lock()"), at("airlock/cap_has(bits)"),
                          at("barcodescanner/proc/computer()")]), got
    return "dx_constructor_shadow"
