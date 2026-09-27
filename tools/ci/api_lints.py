"""One-way-to-do-it lints (doc/rewrite/object_model_core.md sec 16, "One way to do X").

Each count is a banned alternative to the object model's one mechanism for a
job. tools/ci/api_lints_baseline.txt holds the ceilings: a count may fall,
never rise. Most are at 0; the rest are ratchets a sweep lowers.

    do_after_state   om_do_after() with more than two arguments across done_args,
                     fail_args and check_args, or a list built elsewhere: state
                     belongs on a named task type (/datum/om/task/timed/x)
    use_tool_state   the same for use_tool()'s done_args/fail_args
    vars_helpers     om_set_var(), om_set_var_then(), om_toggle_var(),
                     cure_temporary_(s)disability(): a var written back by name.
                     Use the thing's own setter (om_after(E, d, PROC_REF(setter)))
                     or a timed status/contribution (status_at_least(), om_apply())
    vars_write       any other `vars[name] = value`: framework plumbing only
                     (serializer, links, tasks, VV); gameplay calls a setter
    timer_cooldown   TIMER_COOLDOWN_START(): a cooldown is COOLDOWN_START() and
                     COOLDOWN_FINISHED(), a time compared, with no timer
    accessor_macros  BUCKLED(), PULLING(), SLOT_ITEM() and the other relation/slot
                     accessor macros: a relation read is a typed proc
                     (M.buckled_to(), I.slot_item(slot)) so it chains
    raw_relation     om_relation_of()/om_source_of()/om_related(_to)() outside
                     code/datums/om: call the relation's typed accessor proc
    field_write      a direct write to a declared field (fields.dm) outside its setter and
                     Initialize()/New(): om_set() or the OM_SETTER() setter raises its channel
                     (tools/ci/field_write_lint.py has the rules)
    raw_world_bind   a vg_world_* subscription or step bind outside code/datums/om/world_watch.dm:
                     subscribe with om_world_at/on_key/on_change/when/on_rate (sec 4.8)
    string_keys      a string passed to om_world_publish()/om_world_on_key(): keys are numbers
    reactor_api      SSreactor, on_react(), react_every() or a REACT_* macro: Rust
                     wakes are world watches on the OM scheduler (om_world_*, sec 4.8)

Usage:
    python tools/ci/api_lints.py                 # the CI check
    python tools/ci/api_lints.py --report NAME   # every site of one count
    python tools/ci/api_lints.py --update        # rewrite the baseline to today's counts
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
import field_write_lint  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "api_lints_baseline.txt")


def split_args(s):
    out, depth, cur = [], 0, ""
    for c in s:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += c
    if cur.strip():
        out.append(cur.strip())
    return out


def calls(text, name):
    """(line number, argument text) of every call of `name` (strings already blanked)."""
    for m in re.finditer(r"(?<![\w/.])" + name + r"\s*\(", text):
        if text[max(0, m.start() - 5):m.start()] == "proc/":
            continue
        i, depth = m.end(), 1
        while depth and i < len(text):
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
            i += 1
        yield text.count("\n", 0, m.start()) + 1, text[m.end():i - 1]


def state_args(argtext, positional_lists, named_lists):
    """How many arguments the call passes through its argument lists (99: a list built elsewhere)."""
    n = 0
    for i, arg in enumerate(split_args(argtext)):
        m = re.match(r"(\w+)\s*=(?!=)\s*(.*)$", arg, re.S)
        if m and m.group(1) in named_lists:
            value = m.group(2).strip()
        elif not m and i in positional_lists:
            value = arg
        else:
            continue
        if value in ("null", ""):
            continue
        lm = re.match(r"list\((.*)\)$", value, re.S)
        n += len(split_args(lm.group(1))) if lm else 99
    return n


def do_after_state(rel, text):
    for line, args in calls(text, "om_do_after"):
        if state_args(args, {5, 8, 10}, {"done_args", "fail_args", "check_args"}) > 2:
            yield line


def use_tool_state(rel, text):
    for line, args in calls(text, "use_tool"):
        if state_args(args, set(), {"done_args", "fail_args"}) > 2:
            yield line


def pattern(regex):
    compiled = re.compile(regex)

    def check(rel, text):
        for no, line in enumerate(text.split("\n"), 1):
            if line.lstrip().startswith("#define"):
                continue
            for _ in compiled.finditer(line):
                yield no
    return check


def outside(prefix, regex):
    inner = pattern(regex)

    def check(rel, text):
        if rel.startswith(prefix):
            return
        yield from inner(rel, text)
    return check


CHECKS = [
    ("do_after_state", do_after_state),
    ("use_tool_state", use_tool_state),
    ("vars_helpers", pattern(r"\b(?:om_set_var(?:_then)?|om_toggle_var|cure_temporary_s?disability)\b")),
    # om_set() (code/datums/om/fields.dm) is the one sanctioned write by name: it raises the field's channel.
    ("vars_write", outside("code/datums/om/fields.dm",r"\bvars\[[^\]]*\]\s*=(?!=)")),
    ("timer_cooldown", pattern(r"\bS?_?TIMER_COOLDOWN_START\s*\(")),
    ("accessor_macros", pattern(r"(?<![\w/])(?:BUCKLED|BUCKLED_MOBS|PULLING|PULLED_BY|GRABBED_BY|EYE_OWNER|EYES_OF"
                                r"|ACTIVE_EYE|GRAB_TARGET|ORBIT_TARGET|ORBITERS|GRAB_ASSAILANT|LEASH_PET|LEASH_MASTER"
                                r"|LEASH_OF|TETHERED_HANDHELD|TETHER_HOST|FOLLOWING|FOLLOWERS|BORER_HOST|BORER_OF"
                                r"|BS_TX_TARGET|BS_TX_RADIOS|BS_RX_SOURCE|BS_RX_RADIOS|GRIPPER_HELD|UAV_MASTERS"
                                r"|STASIS_SOURCE|SLOT_ITEM|SLOT_LIST|OM_REL_TARGETS?|OM_REL_SOURCES?)\s*\(")),
    ("field_write", field_write_lint.check),
    ("raw_world_bind", outside("code/datums/om/world_watch.dm", r"(?<![\w/])vg_world_(?:at|on_key|watch_\w+|rate_watch|step|clear|cancel)\s*\(")),
    ("string_keys", pattern(r"\bom_world_(?:publish|on_key)\([^)\n]*\"")),
    ("reactor_api", pattern(r"\b(?:SSreactor|on_react|react_every|react_sleep_violation|reactor_id|REACT_[A-Z_]+)\b")),
    ("raw_relation", outside("code/datums/om/", r"(?<![\w/.])om_(?:relation_of|source_of|related|related_to)\s*\(")),
]
NAMES = [name for name, _ in CHECKS]


def scan():
    sites = {name: [] for name in NAMES}
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if "/unit_tests/" in rel:
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = code_only(handle.read())
        for name, check in CHECKS:
            for line in check(rel, text):
                sites[name].append((rel, line))
    return sites


def read_baseline():
    base = {}
    if os.path.exists(BASELINE):
        with open(BASELINE, encoding="utf-8") as handle:
            for line in handle:
                line = line.split("#", 1)[0].strip()
                if line:
                    name, count = line.split()
                    base[name] = int(count)
    return base


def write_baseline(counts):
    lines = [
        "# One-way-to-do-it lint ceilings (doc/rewrite/object_model_core.md sec 16).",
        "# tools/ci/api_lints.py fails when a count rises above its line here.",
        "# Lower a line when a sweep removes sites: `python tools/ci/api_lints.py --update`.",
    ]
    for name in NAMES:
        lines.append("%s %d" % (name, counts[name]))
    with open(BASELINE, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def main(argv):
    sites = scan()
    counts = {name: len(sites[name]) for name in NAMES}
    if "--update" in argv:
        write_baseline(counts)
        print("api lints baseline: " + ", ".join("%s %d" % (n, counts[n]) for n in NAMES))
        return 0
    if "--report" in argv:
        wanted = argv[argv.index("--report") + 1:] or NAMES
        for name in wanted:
            for rel, line in sites[name]:
                print("%s:%d: %s" % (rel, line, name))
        return 0
    base = read_baseline()
    failed = False
    for name in NAMES:
        ceiling = base.get(name)
        if ceiling is None:
            print("%-16s %5d  FAIL (no ceiling in the baseline)" % (name, counts[name]))
            failed = True
        elif counts[name] > ceiling:
            print("%-16s %5d  FAIL (ceiling %d)" % (name, counts[name], ceiling))
            failed = True
        elif counts[name] < ceiling:
            print("%-16s %5d  below ceiling %d: lower it with --update" % (name, counts[name], ceiling))
        else:
            print("%-16s %5d  ok" % (name, counts[name]))
    if failed:
        print("A count rose above its ceiling: use the one mechanism doc/rewrite/object_model_core.md sec 16 names; `--report NAME` lists the sites.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
