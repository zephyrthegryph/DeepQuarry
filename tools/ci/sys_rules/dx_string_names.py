"""sys_lint module: var names passed as string literals (doc/rewrite/dx_conventions.md, design review §7).

Every accessor that takes a var name takes it as nameof(...), so a rename is a compile error instead
of a silent runtime miss:

    own_set(src, nameof(beaker), I)      // not own_set(src, "beaker", I)

Rule:
  dx_string_names   a var-name argument of an ownership / relation / field / timed accessor is a
                    string literal ("x" or "[x]_link"). The accessors and their name positions are
                    read from the tree: every global proc named own_* / rel_* / om_set / timed_* /
                    time_left whose parameter is called var_name, from_var, dest_var (or `name` for
                    om_set). ACCESSORS below is the fallback when a tree has none (the selftest). A
                    variable holding a name (framework plumbing) is fine.

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

# name -> positional indexes of var-name arguments (fallback when the tree defines none).
ACCESSORS = {
    "own_set": (1,), "own_add": (1,), "own_remove": (1,), "own_take": (1,), "own_clear": (1,),
    "own_put": (1,), "own_take_member": (1,), "own_take_all": (1,), "own_values": (1,),
    "own_transfer": (1, 3), "own_move": (2,), "rel_set": (1,), "rel_add": (1,), "rel_remove": (1,),
    "rel_clear": (1,), "rel_targets": (1,), "om_set": (1,), "timed_set": (1,), "time_left": (1,),
    "timed_cancel": (1,),
}
ACCESSOR_NAME = re.compile(r"^(?:own_\w+|rel_\w+|om_set|timed_\w+|time_left)$")
NAME_PARAMS = ("var_name", "from_var", "dest_var")
STRING_ARG = re.compile(r'^\s*(?:"|\{")')


def accessors_from(procs_list):
    """{name: (indexes)} for every global accessor proc with a var-name parameter."""
    out = {}
    for proc in procs_list:
        if not proc.is_global() or not ACCESSOR_NAME.match(proc.name):
            continue
        wanted = NAME_PARAMS + (("name",) if proc.name == "om_set" else ())
        idx = tuple(k for k, p in enumerate(proc.params) if p in wanted)
        if idx:
            out[proc.name] = idx
    return out


def call_pattern(accessors):
    return re.compile(r"(?<![\w./:])(" + "|".join(sorted(map(re.escape, accessors))) + r")\s*\(")


def scan_file(rel, lines, clean=None, accessors=None, pattern=None):
    """Sites in one file: a call whose var-name argument, in the raw text, is a string literal."""
    accessors = accessors or ACCESSORS
    pattern = pattern or call_pattern(accessors)
    found = []
    clean = clean if clean is not None else dm.sanitize(lines)
    for number, (raw, code) in enumerate(zip(lines, clean), 1):
        for m in pattern.finditer(code):
            # Definitions (`/proc/own_set(`) are excluded by the lookbehind on "/".
            spans = dm.call_arg_spans(code, m.end() - 1)
            if not spans:
                continue
            positional = [sp for sp in spans if not dm.NAMED_ARG.match(code[sp[0]:sp[1]])]
            hit = False
            for index in accessors[m.group(1)]:
                if index < len(positional):
                    start, end = positional[index]
                    # Argument boundaries come from the sanitized text; the literal check from the raw text.
                    if STRING_ARG.match(raw[start:end]):
                        hit = True
                        break
            if hit:
                found.append((rel, number))
                break
    return found


def scan(files):
    out = {rule: [] for rule in RULES}
    tree = dm.tree(files)
    accessors = accessors_from(tree.procs) or ACCESSORS
    pattern = call_pattern(accessors)
    for rel, lines in files:
        text = "\n".join(lines)
        if "own_" not in text and "rel_" not in text and "om_set" not in text and "time" not in text:
            continue
        out["dx_string_names"].extend(scan_file(rel, lines, tree.clean[rel], accessors, pattern))
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
        'own_transfer(src, nameof(a), dest, "b")',      # 10 bad: the destination var
        'own_transfer(src, nameof(a), dest, nameof(b), member = "x")',  # 11 ok: a named non-name arg
    ]
    got = [n for _rel, n in scan_file("x.dm", fixture)]
    assert got == [1, 3, 4, 9, 10], got
    # The accessor table is read from the tree's global procs.
    procs_list = dm.procs([("a.dm", [
        "/proc/own_widget(datum/holder, var_name, datum/value)",
        "\treturn",
        "/proc/own_key(datum/D)",
        "\treturn",
        "/obj/proc/own_set(var_name)",
        "\treturn",
        "/proc/om_set(datum/E, name, value)",
        "\treturn",
    ])])
    assert accessors_from(procs_list) == {"own_widget": (1,), "om_set": (1,)}, accessors_from(procs_list)
    return "dx_string_names"
