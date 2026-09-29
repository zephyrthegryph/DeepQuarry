"""sys_lint module: var names passed as string literals (doc/rewrite/dx_conventions.md, design review §7).

Every accessor that takes a var name takes it as nameof(...), so a rename is a compile error instead
of a silent runtime miss:

    own_set(src, nameof(beaker), I)      // not own_set(src, "beaker", I)

Rule:
  dx_string_names   the second argument of own_set/own_add/own_remove/own_take/own_clear/own_put/
                    rel_set/rel_add/rel_remove/om_set/timed_set/time_left/timed_cancel is a string
                    literal ("x" or "[x]"). A variable holding a name (framework plumbing) is fine.

The baseline (tools/ci/sys_baseline/dx_string_names.txt) holds the legacy sites; target 0.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _dx_dm as dm  # noqa: E402

RULES = {
    "dx_string_names": "pass the var name as nameof(var), never a string literal (dx_conventions.md; design review §7)",
}

ACCESSORS = ("own_set", "own_add", "own_remove", "own_take", "own_clear", "own_put", "rel_set",
             "rel_add", "rel_remove", "om_set", "timed_set", "time_left", "timed_cancel")
CALL = re.compile(r"(?<![\w./:])(" + "|".join(ACCESSORS) + r")\s*\(")
STRING_ARG = re.compile(r'^\s*(?:"|\{")')


def scan_file(rel, lines):
    """Sites in one file: a call whose second argument, in the raw text, is a string literal."""
    found = []
    clean = dm.sanitize(lines)
    for number, (raw, code) in enumerate(zip(lines, clean), 1):
        for m in CALL.finditer(code):
            # Definitions (`/proc/own_set(`) are excluded by the lookbehind on "/".
            open_at = m.end() - 1
            # Argument boundaries come from the sanitized text; the literal check from the raw text.
            end = dm.match_paren(code, open_at)
            if end < 0:
                continue
            parts = dm.split_top(code[open_at + 1:end])
            if len(parts) < 2:
                continue
            second_at = open_at + 1 + len(parts[0]) + 1
            if STRING_ARG.match(raw[second_at:end]):
                found.append((rel, number))
                break
    return found


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        if not any(a in "\n".join(lines) for a in ACCESSORS):
            continue
        out["dx_string_names"].extend(scan_file(rel, lines))
    return out


def selftest():
    fixture = [
        'own_set(src, "beaker", I)',                    # 1 bad
        "own_set(src, nameof(beaker), I)",              # 2 ok
        'timed_set(get_holder(x, "a"), "emp", TRUE)',   # 3 bad: nested call in the first arg
        'rel_add(src, "[slot]_link", T)',               # 4 bad: interpolated literal
        "om_set(E, name, value)",                       # 5 ok: a variable
        "/proc/own_set(datum/holder, var_name, datum/value)",  # 6 ok: the definition
        '// own_set(src, "x", I)',                      # 7 ok: a comment
        'to_chat(user, "own_set(src, \\"x\\", I)")',    # 8 ok: inside a string
        'time_left(src, "cooldown")',                   # 9 bad
    ]
    got = [n for _rel, n in scan_file("x.dm", fixture)]
    assert got == [1, 3, 4, 9], got
    return "dx_string_names"
