"""sys_lint module: type procs that shadow a capability constructor or bundle (framework review 2, H7).

Inside capabilities(), a bare call binds to src's own proc before the global one, so a type proc
named like a constructor or bundle silently replaces it on that type (airlocks have lock(),
machinery has powered()). Constructors are named cap_<noun>; bundles are plain nouns
(machine_basics, console, ...). No type proc or verb may reuse either name:

    /obj/machinery/door/airlock/proc/cap_lock()      // shadows /proc/cap_lock inside capabilities()

Rule:
  dx_constructor_shadow   a proc or verb defined on a type (a new proc, a verb or an override) whose
                          name is a global /proc/cap_* in the tree, a global proc of a library
                          presets file (code/datums/capabilities/library/preset*.dm), or a bundle:
                          a global proc under code/datums/capabilities/ that builds a capability
                          (`new /datum/capability...`, or a call to a proc that does). Only procs
                          of atom types count: capabilities() is an atom proc.

The baseline (tools/ci/sys_baseline/dx_constructor_shadow.txt) holds the legacy sites; target 0.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _dx_dm as dm  # noqa: E402

RULES = {
    "dx_constructor_shadow": "rename the type proc: it shadows a global capability constructor or bundle inside capabilities() (framework review 2, H7)",
}

PRESET_FILES = "code/datums/capabilities/library/preset"
CAPS_DIR = "code/datums/capabilities/"
NEW_CAP = re.compile(r"\bnew\s+/datum/capability\b|\bvar/datum/capability[\w/]*\s*=\s*new\b")
CALL = re.compile(r"(?<![\w./:])([A-Za-z_]\w*)\s*\(")


def reserved_names(procs_list):
    """cap_* globals, presets-file globals, and every global in code/datums/capabilities/ that builds
    a capability: directly (`new /datum/capability...`) or by calling one that does (a fixpoint, so
    bundles of bundles count and helpers such as cap_of()/wires_of() don't)."""
    names = set()
    candidates = {}
    for proc in procs_list:
        if not proc.is_global():
            continue
        if proc.name.startswith("cap_") or proc.rel.startswith(PRESET_FILES):
            names.add(proc.name)
        if proc.name.startswith("cap_") or proc.rel.startswith(CAPS_DIR):
            candidates[proc.name] = "\n".join(proc.body)
    builders = {n for n, body in candidates.items() if NEW_CAP.search(body)}
    grew = True
    while grew:
        grew = False
        for n, body in candidates.items():
            if n not in builders and any(m.group(1) in builders for m in CALL.finditer(body)):
                builders.add(n)
                grew = True
    return names | builders


def scan_procs(procs_list):
    """Type procs on atoms (holders: capabilities() is an atom proc) named like a constructor."""
    names = reserved_names(procs_list)
    return [(p.rel, p.line) for p in procs_list
            if not p.is_global() and p.name in names and "/atom" in dm.lineage(p.path)]


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
/obj/machinery/console/proc/wall_console()
	return
/obj/machinery/power/apc/proc/power_channels()
	return
/obj/machinery/power/apc/proc/wires_of()
	return
/datum/input_adapter/proc/power_channels()
	return
"""
PRESETS_FIXTURE = """
/proc/wall_console(board)
	return list()
"""
LIBRARY_FIXTURE = """
/proc/power_channels(list/channels)
	return list(new /datum/capability/power_channels)
/proc/wires_of(atom/A)
	return cap_of(A, /datum/capability/wires)
/proc/cap_of(atom/A, key)
	return null
"""


def selftest():
    lines = FIXTURE.split("\n")
    procs_list = dm.procs([("x.dm", lines), (PRESET_FILES + "s.dm", PRESETS_FIXTURE.split("\n")),
                           (CAPS_DIR + "library/apc.dm", LIBRARY_FIXTURE.split("\n"))])
    got = sorted(n for r, n in scan_procs(procs_list) if r == "x.dm")

    def at(snippet):
        return [k + 1 for k, line in enumerate(lines) if snippet in line][0]
    # cap_lock and cap_has are global cap_* procs; wall_console is a global of the presets file;
    # power_channels is a bundle in another library file (it builds a capability). wires_of is a
    # helper (it calls cap_of(), which builds nothing), a /datum proc can't shadow inside an atom's
    # capabilities(), cap_cover_toggle has no global twin, cap_lock_verb is another name, and computer()/
    # lock() are not constructors.
    assert got == sorted([at("airlock/proc/cap_lock()"), at("airlock/cap_has(bits)"),
                          at("console/proc/wall_console()"), at("apc/proc/power_channels()")]), got
    return "dx_constructor_shadow"
