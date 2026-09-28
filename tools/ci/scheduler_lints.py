"""One-scheduler lints (roadmap S6, doc/rewrite/object_model_core.md sec 4.11).

Counts every site of the things the OM scheduler replaces, and the undeclared
object-typed vars (LC-refs, doc/rewrite/lifecycle.md sec 4), across code/
(unit tests excluded; `#define` lines are macro plumbing and don't count).
Each count is ratcheted: tools/ci/scheduler_lints_baseline.txt holds the
ceiling, today's counts at the time it was written. A sweep lowers them to 0
outside the allowlist in sec 4.11 ("What stays").

    spawn            spawn(                        -> om_after, tasks
    addtimer         addtimer(                     -> om_after, clocks, contributions
    invoke_async     INVOKE_ASYNC                  -> nothing: the callee no longer sleeps
    do_after         do_after(                     -> om_task steps
    sleep            sleep(                        -> om_task steps
    stoplag          stoplag(                      -> a lane with a budget
    prompts          input( alert( tgui_input_*( tgui_alert(   -> om_prompt
    set_waitfor      set waitfor                   -> nothing
    weakref          weakref (any case)            -> relations, or OM handles (0: deleted)
    del              del(                          -> qdel and the lifecycle verbs
    lc_refs          undeclared object-typed instance vars and lists

LC-refs: a var whose declared type is an object reference (tmp
included; static/global/const are not instance state) must be named by its
type's declared_owned_vars(), declared_owned_list_vars(), declared_pair_vars(),
declared_backlist_vars() or declared_cache_vars() in the same file. Relations
and slots have no view field, and an OM handle is a text var, so neither is
an object-typed var at all. Vars of task types (/datum/om/task/...) are task
state, held by the task_holds relation, and don't count. Medical, body, organs, surgery and Life are
included (lifecycle.md sec 7).

Justified keeps (MC, GC, failsafe, world and client procs, savefiles, vendored
TGS, blocking external I/O) are listed per count and file, with a required
reason, in tools/ci/scheduler_lints_allowlist.txt and don't count.

Usage:
    python tools/ci/scheduler_lints.py                 # the CI check
    python tools/ci/scheduler_lints.py --report NAME   # every site of one count
    python tools/ci/scheduler_lints.py --update        # rewrite the baseline to today's counts
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import REF_ROOTS, code_only, under  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "scheduler_lints_baseline.txt")
# Justified keeps (sec 4.11 "What stays"): `NAME path count  # reason`, one line per
# count and file. The reason is required. Allowlisted sites don't count toward the
# ceiling; a file with more sites than its line allows counts the excess.
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "scheduler_lints_allowlist.txt")

PATTERNS = [
    ("spawn", re.compile(r"(?<![\w.])spawn\s*\(")),
    ("addtimer", re.compile(r"(?<![\w.])addtimer\s*\(")),
    ("invoke_async", re.compile(r"\bINVOKE_ASYNC\b")),
    ("do_after", re.compile(r"(?<![\w./])do_after\s*\(")),
    ("sleep", re.compile(r"(?<![\w./])sleep\s*\(")),
    ("stoplag", re.compile(r"(?<![\w./])stoplag\s*\(")),
    ("prompts", re.compile(r"(?<![\w./])(?:input|alert|tgui_input_\w+|tgui_alert)\s*\(")),
    ("set_waitfor", re.compile(r"\bset\s+waitfor\b")),
    ("weakref", re.compile(r"(?i)weakref")),
    ("del", re.compile(r"(?<![\w./])del\s*\(")),
]
NAMES = [name for name, _ in PATTERNS] + ["lc_refs"]
# Marks a blocking prompt the S10 allowlist keeps (file uploads, the tgui repair verb, ...).
KEEP_MARK = "// S10 keeps:"

UNSAVED_MODS = {"static", "global", "const"}
ALL_MODS = {"tmp", "static", "global", "const", "final"}
DECLARED_PROCS = (
    "declared_owned_vars",
    "declared_owned_list_vars",
    "declared_owned_value_vars",
    "declared_spill_vars",
    "declared_spill_list_vars",
    "declared_held_vars",
    "declared_pair_vars",
    "declared_backlist_vars",
    "declared_cache_vars",
)
# REF_OWNED(/type, NAMES) and friends (code/__defines/lifecycle.dm): one-line declarations.
REF_MACRO = re.compile(r"^REF_(?:OWNED_LIST|OWNED_VALUES|OWNED|SPILL_LIST|SPILL|HELD|PAIR|BACKLIST)\(\s*(/[\w/]+)\s*,(.*)\)\s*$")
TYPE_HEADER = re.compile(r"^(/[A-Za-z_][\w/]*)\s*$")
PROC_HEADER = re.compile(r"^(/[\w/]*?)/(proc/)?(" + "|".join(DECLARED_PROCS) + r")\s*\(")
VAR_LINE = re.compile(r"^var((?:/[A-Za-z_]\w*)+)\s*(?:=|$)")
STRING_LIT = re.compile(r'"([^"]*)"')
# `/type/var/tmp/datum/x` one-line declarations.
INLINE_VAR = re.compile(r"^(/[A-Za-z_][\w/]*?)/var((?:/[A-Za-z_]\w*)+)\s*(?:=|$)")


def split_var(segs):
    segs = list(segs)
    mods = set()
    while segs and segs[0] in ALL_MODS:
        mods.add(segs.pop(0))
    if not segs:
        return None
    name = segs[-1]
    tsegs = segs[:-1]
    if tsegs and tsegs[0] == "list":
        tsegs = tsegs[1:]
    return mods, ("/" + "/".join(tsegs) if tsegs else ""), name


def lc_ref_sites(rel, raw_text, code_text):
    # Declared names come from string literals, so read them from the raw text.
    declared = {}
    owner, body = None, []
    for raw in raw_text.split("\n"):
        if not raw.strip():
            continue
        stripped = raw.lstrip("\t ")
        if len(raw) == len(stripped):
            if owner is not None:
                for line in body:
                    declared.setdefault(owner, set()).update(STRING_LIT.findall(line))
                owner, body = None, []
            m = REF_MACRO.match(stripped.rstrip())
            if m:
                declared.setdefault(m.group(1), set()).update(STRING_LIT.findall(m.group(2)))
                continue
            m = PROC_HEADER.match(stripped.rstrip())
            if m:
                owner = m.group(1)
        elif owner is not None:
            body.append(stripped)
    if owner is not None:
        for line in body:
            declared.setdefault(owner, set()).update(STRING_LIT.findall(line))

    sites = []
    cur_type = None
    for no, raw in enumerate(code_text.split("\n"), 1):
        if not raw.strip():
            continue
        stripped = raw.lstrip("\t ")
        indent = len(raw) - len(stripped)
        text = stripped.rstrip()
        owner_type, segs = None, None
        if indent == 0:
            m = TYPE_HEADER.match(text)
            cur_type = m.group(1) if m else None
            m = INLINE_VAR.match(text)
            if m:
                owner_type, segs = m.group(1), m.group(2)
        elif indent == 1 and cur_type is not None:
            m = VAR_LINE.match(text)
            if m:
                owner_type, segs = cur_type, m.group(1)
        if not segs:
            continue
        parsed = split_var(segs.strip("/").split("/"))
        if not parsed:
            continue
        mods, vtype, name = parsed
        if mods & UNSAVED_MODS or not under(vtype, REF_ROOTS):
            continue
        if name in declared.get(owner_type, ()):
            continue
        # A task's vars are its state: every datum in them is held by the task_holds
        # relation, which clears the var and cancels the task when the datum is deleted.
        if owner_type == "/datum/om/task" or owner_type.startswith("/datum/om/task/"):
            continue
        sites.append((rel, no, "%s var/%s %s" % (owner_type, vtype.strip("/"), name)))
    return sites


def scan():
    sites = {name: [] for name in NAMES}
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if "/unit_tests/" in rel:
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            raw_text = handle.read()
        text = code_only(raw_text)
        raw_lines = raw_text.split("\n")
        for no, line in enumerate(text.split("\n"), 1):
            if line.lstrip().startswith("#define"):
                continue
            for name, pattern in PATTERNS:
                for _ in pattern.finditer(line):
                    # A prompt the S10 allowlist keeps says why on its line (sec 4.11).
                    if name == "prompts" and KEEP_MARK in raw_lines[no - 1]:
                        continue
                    sites[name].append((rel, no, name))
        sites["lc_refs"].extend(lc_ref_sites(rel, raw_text, text))
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


def read_allowlist():
    allowed = {}
    if not os.path.exists(ALLOWLIST):
        return allowed
    with open(ALLOWLIST, encoding="utf-8") as handle:
        for no, line in enumerate(handle, 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            body, _, reason = line.partition("#")
            parts = body.split()
            if len(parts) < 3 or not parts[-1].isdigit() or not reason.strip():
                raise SystemExit("%s:%d: expected `NAME path count  # reason`" % (ALLOWLIST, no))
            allowed[(parts[0], " ".join(parts[1:-1]))] = int(parts[-1])
    return allowed


def counted(sites, allowed):
    """Sites per count after the allowlist, plus stale allowlist lines."""
    per_file = {}
    for name in NAMES:
        for rel, _, _ in sites[name]:
            per_file[(name, rel)] = per_file.get((name, rel), 0) + 1
    counts = {name: 0 for name in NAMES}
    for (name, rel), n in per_file.items():
        counts[name] += max(n - allowed.get((name, rel), 0), 0)
    stale = [(k, v, per_file.get(k, 0)) for k, v in allowed.items() if per_file.get(k, 0) < v]
    return counts, stale


def write_baseline(counts):
    lines = [
        "# One-scheduler lint ceilings (roadmap S6, doc/rewrite/object_model_core.md sec 4.11).",
        "# tools/ci/scheduler_lints.py fails when a count rises above its line here.",
        "# Lower a line when a sweep removes sites: `python tools/ci/scheduler_lints.py --update`.",
    ]
    for name in NAMES:
        lines.append("%s %d" % (name, counts[name]))
    with open(BASELINE, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def main(argv):
    sites = scan()
    counts, stale = counted(sites, read_allowlist())
    for (name, rel), allow, have in stale:
        print("note: allowlist %s %s %d, now %d: lower it" % (name, rel, allow, have))
    if "--update" in argv:
        write_baseline(counts)
        print("scheduler lints baseline: " + ", ".join("%s %d" % (n, counts[n]) for n in NAMES))
        return 0
    if "--report" in argv:
        wanted = argv[argv.index("--report") + 1:] or NAMES
        for name in wanted:
            for rel, number, what in sites[name]:
                print("%s:%d: %s" % (rel, number, what))
        return 0
    base = read_baseline()
    failed = False
    for name in NAMES:
        limit = base.get(name, 0)
        status = "ok"
        if counts[name] > limit:
            status = "FAIL (ceiling %d)" % limit
            failed = True
        elif counts[name] < limit:
            status = "below ceiling %d: lower it with --update" % limit
        print("%-13s %6d  %s" % (name, counts[name], status))
    if failed:
        print("A count rose above its ceiling. Use the OM scheduler instead "
              "(om_after, om_task steps, om_prompt, OM handles, declared refs); "
              "`--report NAME` lists the sites.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
