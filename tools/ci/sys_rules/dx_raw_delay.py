"""sys_lint module: raw decisecond literals in delay arguments (AGENTS.md §3f; dx_conventions.md §7).

A delay is written with the time defines (`2 SECONDS`, `5 MINUTES`, `1 TICK`), never as a bare
number of deciseconds, so the unit is visible at the call:

    om_after(src, 2 SECONDS, PROC_REF(finish))       // not om_after(src, 20, ...)
    timed_set(src, nameof(emp_disabled), TRUE, for_time = 90 SECONDS / severity)

Rule:
  dx_raw_delay   the delay argument of a timer or delayed action holds a numeric literal other than
                 0 that is not scaled by a time define. Calls and their delay position (or the named
                 argument `delay =` / `for_time =`):
                   after(E, delay), om_after(E, delay), om_after_unique/om_after_replace(E, delay),
                   om_after_slot(E, slot, delay), om_after_realtime(delay), addtimer(cb, delay),
                   do_after(user, delay), COOLDOWN_START(src, index, delay),
                   timed_set(D, name, value, for_time), cap_tool(name, quality, handler, delay), and
                   `delay =` on any cap_* constructor.
                 A literal is fine when it is followed by a time define (`2 SECONDS`), when the group
                 or call it sits in is (`rand(2, 5) SECONDS`, `(base + 1) SECONDS`), or when it is a
                 factor (`delay * 2`, `delay / 2`, `2 * delay`), which scales a value that already
                 has a unit.

Static limits: a delay held in a variable or a define is not followed back to its value; a
factor on a raw literal (`20 * 2`) passes. The baseline (tools/ci/sys_baseline/dx_raw_delay.txt)
holds the legacy sites; target 0.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _dx_dm as dm  # noqa: E402

RULES = {
    "dx_raw_delay": "write the delay with a time define (2 SECONDS, 5 MINUTES, 1 TICK), not raw deciseconds (AGENTS.md §3f)",
}

# call name -> (positional index of the delay, named argument that can carry it)
DELAY_ARGS = {
    "after": (1, "delay"),
    "om_after": (1, "delay"),
    "om_after_unique": (1, "delay"),
    "om_after_replace": (1, "delay"),
    "om_after_slot": (2, "delay"),
    "om_after_realtime": (0, "delay"),
    "addtimer": (1, "wait"),
    "do_after": (1, "delay"),
    "COOLDOWN_START": (2, "cd_time"),
    "timed_set": (3, "for_time"),
    "cap_tool": (3, "delay"),
}
UNITS = r"(?:MILLISECONDS?|DECISECONDS?|SECONDS?|MINUTES?|HOURS?|TICKS?|DAYS?)\b"
CALL = re.compile(r"(?<![\w./:])(" + "|".join(sorted(DELAY_ARGS)) + r"|cap_\w+)\s*\(")
NUMBER = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?(?:e[+-]?\d+)?|\.\d+)(?![\w.])")
GROUP_WITH_UNIT = re.compile(r"\(")


def blank_scaled_groups(expr):
    """expr with every (...) group (a call's arguments or a parenthesis) that is followed by a time
    define blanked, so `rand(1, 3) SECONDS` counts as scaled."""
    chars = list(expr)
    for m in GROUP_WITH_UNIT.finditer(expr):
        end = dm.match_paren(expr, m.start())
        if end > 0 and re.match(r"\s*" + UNITS, expr[end + 1:]):
            for k in range(m.start() + 1, end):
                chars[k] = " "
    return "".join(chars)


def raw_literal(expr):
    """True when expr holds a numeric literal other than 0 not scaled by a unit or used as a factor."""
    expr = blank_scaled_groups(expr)
    for m in NUMBER.finditer(expr):
        if float(m.group(1)) == 0:
            continue
        after = expr[m.end():]
        before = expr[:m.start()].rstrip()
        if re.match(r"\s*" + UNITS, after):
            continue
        if before.endswith(("*", "/")) or re.match(r"\s*\*", after):
            continue
        return True
    return False


def delay_of(name, args):
    if name in DELAY_ARGS:
        index, key = DELAY_ARGS[name]
        got = dm.pick_arg(args, index, key)
        if got is None and key != "delay":
            got = dm.pick_arg(args, None, "delay")
        return got
    # any other cap_* constructor: only its named `delay =`
    return dm.pick_arg(args, None, "delay")


def scan_lines(rel, clean):
    found = []
    for number, code in enumerate(clean, 1):
        for m in CALL.finditer(code):
            args = dm.call_args(code, m.end() - 1)
            if not args:
                continue
            delay = delay_of(m.group(1), args)
            if delay and raw_literal(delay):
                found.append((rel, number))
                break
    return found


def scan(files):
    out = {rule: [] for rule in RULES}
    tree = dm.tree(files)
    for rel, _lines in files:
        text = tree.raw_text(rel)
        if not any(k in text for k in ("after", "addtimer", "COOLDOWN_START", "timed_set", "cap_")):
            continue
        out["dx_raw_delay"].extend(scan_lines(rel, tree.clean[rel]))
    return out


def selftest():
    fixture = [
        "om_after(src, 20, PROC_REF(finish))",                          # 1 bad
        "om_after(src, 2 SECONDS, PROC_REF(finish))",                   # 2 ok
        "om_after_slot(src, \"x\", rand(10, 20), PROC_REF(x))",         # 3 bad
        "om_after_slot(src, \"x\", rand(1, 2) SECONDS, PROC_REF(x))",   # 4 ok: the call is scaled
        "timed_set(src, nameof(a), TRUE, for_time = 90 SECONDS / severity)",  # 5 ok
        "timed_set(src, nameof(a), TRUE, for_time = 50)",               # 6 bad
        "timed_set(src, nameof(a), 5, for_time = duration)",            # 7 ok: 5 is the value
        "COOLDOWN_START(src, cooldown, 15)",                            # 8 bad
        "COOLDOWN_START(src, cooldown, base_delay * 2)",                # 9 ok: a factor
        "after(src, 0, PROC_REF(now))",                                 # 10 ok: zero
        "cap_tool(\"Unbolt\", TOOL_WRENCH, PROC_REF(unbolt), 40)",      # 11 bad
        "cap_cover(open_tool = TOOL_CROWBAR, delay = 2 SECONDS)",       # 12 ok
        "cap_cover(open_tool = TOOL_CROWBAR, delay = 30)",              # 13 bad
        "om_after(src, (base + 5) SECONDS, PROC_REF(x))",               # 14 ok
        "om_after(src, delay + 5, PROC_REF(x))",                        # 15 bad
        "/proc/om_after(datum/E, delay, proc_ref, ...)",                # 16 ok: the definition
        "addtimer(CALLBACK(src, PROC_REF(x)), 10)",                     # 17 bad
        "do_after(user, 1.5 SECONDS, target)",                          # 18 ok
    ]
    got = [n for _rel, n in scan_lines("x.dm", dm.sanitize(fixture))]
    assert got == [1, 3, 6, 8, 11, 13, 15, 17], got
    return "dx_raw_delay"
