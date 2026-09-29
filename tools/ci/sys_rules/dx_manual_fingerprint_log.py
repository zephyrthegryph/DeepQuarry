"""sys_lint module: fingerprints and log lines written by hand in dispatched handlers (dx_conventions.md §2, §8).

dispatch_call() records the fingerprint and the log line of every successful dispatched call (a UI
action, a capability entry), at the level the entry's `log =` or the type's ui_logged() names. A
handler that also calls add_fingerprint() or log_game() double-records, and records refusals and
cancellations too:

    /obj/machinery/pump/proc/act_toggle(mob/user)     // no add_fingerprint(user) / log_game() here
        set_on(!on)
        return TRUE

Rule:
  dx_manual_fingerprint_log   add_fingerprint( / log_game( / log_admin( / message_admins( /
                              log_and_message_admins( inside
                                - an act_<action> proc on a type (a client UI action), or
                                - a capability entry handler: the proc named by the handler argument
                                  of cap_hand/cap_tool/cap_use_on/cap_insert/cap_entry (positional or
                                  `handler =`), as PROC_REF(x) (x on the calling type's lineage or
                                  subtypes), TYPE_PROC_REF(T, x) (x on T or a subtype) or
                                  GLOBAL_PROC_REF(x).
Static limits: handlers are matched by name and type relation, not by resolving the exact override,
and helpers a handler calls are not followed. The baseline
(tools/ci/sys_baseline/dx_manual_fingerprint_log.txt) holds the legacy sites; target 0.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _dx_dm as dm  # noqa: E402

RULES = {
    "dx_manual_fingerprint_log": "drop it: dispatch_call() fingerprints and logs a successful dispatched call (set `log =` / ui_logged() for the level) (dx_conventions.md §2, §8)",
}

MANUAL = re.compile(r"(?<![\w./:])(?:add_fingerprint|log_game|log_admin|message_admins|log_and_message_admins)\s*\(")
# constructor -> positional index of its handler argument
HANDLER_ARG = {"cap_hand": 1, "cap_tool": 2, "cap_use_on": 2, "cap_insert": 2, "cap_entry": 2}
CTOR = re.compile(r"(?<![\w./:])(" + "|".join(sorted(HANDLER_ARG)) + r")\s*\(")


def handler_refs(procs_list):
    """[(kind, type, name, calling type)] for every handler named in a constructor call."""
    out = []
    for proc in procs_list:
        for _n, text in proc.lines():
            if "cap_" not in text:
                continue
            for m in CTOR.finditer(text):
                args = dm.call_args(text, m.end() - 1)
                if not args:
                    continue
                ref = dm.proc_ref(dm.pick_arg(args, HANDLER_ARG[m.group(1)], "handler"))
                if ref:
                    out.append(ref + (proc.path,))
    return out


def is_handler(proc, refs):
    for kind, of_type, name, caller in refs:
        if name != proc.name:
            continue
        if kind == "global":
            if proc.is_global():
                return True
        elif kind == "type":
            if not proc.is_global() and dm.is_subtype(proc.path, of_type):
                return True
        elif not proc.is_global() and (caller == "/" or dm.related(proc.path, caller)):
            return True
    return False


def scan_procs(procs_list):
    refs = handler_refs(procs_list)
    by_name = {r[2] for r in refs}
    found = []
    for proc in procs_list:
        is_action = proc.name.startswith("act_") and not proc.is_global()
        if not is_action and not (proc.name in by_name and is_handler(proc, refs)):
            continue
        for number, text in proc.lines():
            if MANUAL.search(text):
                found.append((proc.rel, number))
    return found


def scan(files):
    out = {rule: [] for rule in RULES}
    out["dx_manual_fingerprint_log"] = scan_procs(dm.tree(files).procs)
    return out


FIXTURE = """
/obj/machinery/pump/proc/act_toggle(mob/user)
	add_fingerprint(user)
	log_game("[user] toggled [src]")
	return TRUE

/obj/machinery/pump/capabilities()
	. = ..()
	. += cap_hand("Toggle", PROC_REF(toggle_power))
	. += cap_tool("Unbolt", TOOL_WRENCH, handler = TYPE_PROC_REF(/obj/machinery, unbolt))

/obj/machinery/pump/proc/toggle_power(mob/user)
	message_admins("[user] toggled [src]")
	return TRUE

/obj/machinery/proc/unbolt(mob/user, obj/item/held)
	log_admin("unbolted")
	return TRUE

/obj/machinery/pump/proc/helper(mob/user)
	add_fingerprint(user)

/obj/item/other/proc/toggle_power(mob/user)
	log_game("unrelated type")

/proc/act_message_like(user)
	log_game("a global proc named act_*")
"""


def selftest():
    lines = FIXTURE.split("\n")
    got = sorted(n for _r, n in scan_procs(dm.procs([("x.dm", lines)])))

    def at(snippet):
        return [k + 1 for k, line in enumerate(lines) if snippet in line][0]
    assert got == sorted([at("\tadd_fingerprint(user)"), at('log_game("[user] toggled'),
                          at("message_admins("), at('log_admin("unbolted")')]), got
    return "dx_manual_fingerprint_log"
