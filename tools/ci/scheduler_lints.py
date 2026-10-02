"""One-scheduler lints (roadmap S6, doc/rewrite/object_model_core.md sec 4.11).

Counts every site of the things the OM scheduler replaces, and the undeclared
object-typed vars (LC-refs, doc/rewrite/lifecycle.md sec 4), across code/
(unit tests excluded; `#define` lines are macro plumbing and don't count).
Each count is ratcheted: tools/ci/scheduler_lints_baseline.txt holds the
legacy sites as fingerprints (file + line text); it only shrinks. A sweep empties it
outside the justified keeps of sec 4.11 ("What stays").

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
    blocking_builtins  winget( winexists( .MeasureText( shell(   -> DX-exec (dx_exec.dm) callbacks

Object-typed vars are checked by tools/ci/ownership_lint.py (doc/rewrite/ownership.md): the
kind of each var is inferred from how it is written, so there is no per-var declaration count here.

Justified keeps (MC, GC, failsafe, world and client procs, savefiles, vendored
TGS, blocking external I/O, prompts that must block) carry
`// ALLOW(scheduler): <reason>` on the site's line or the comment line above it
(tools/ci/allow_annotations.py) and don't count.

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
from allow_annotations import allowed, check_sites, exempt_path, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "scheduler_lints_baseline.txt")

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
    # BYOND's blocking built-ins: client round trips and OS processes. Callers ask DX-exec
    # (dx_winget(), dx_winexists(), dx_measure_text(), dx_shell(), dx_shelleo()) instead.
    ("blocking_builtins", re.compile(r"(?<![\w./])(?:winget|winexists|shell)\s*\(|\.MeasureText\s*\(")),
]
NAMES = [name for name, _ in PATTERNS]
# Counts whose ratchet reached 0 and became an outright ban: no baseline line, ceiling 0.
BANNED = set()
LINT = "scheduler"

def scan():
    sites = {name: [] for name in NAMES}
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if exempt_path(rel):
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
                    # A justified keep says why on its line (sec 4.11).
                    if allowed(raw_lines, no, LINT):
                        continue
                    sites[name].append((rel, no, name))
    return sites


def main(argv):
    sites = scan()
    counts = {name: len(sites[name]) for name in NAMES}
    if "--update" in argv or "--seed" in argv:
        write_sites(BASELINE, [
            "scheduler lint legacy sites (tools/ci/scheduler_lints.py). rule<TAB>file<TAB>normalized line.",
            "A site not listed here fails. Shrink-only: after a sweep, `python tools/ci/scheduler_lints.py --update`.",
        ], sites, [n for n in NAMES if n not in set(BANNED)], shrink_only="--seed" not in argv)
        print("scheduler lints baseline: " + ", ".join("%s %d" % (n, counts[n]) for n in NAMES))
        return 0
    if "--report" in argv:
        wanted = argv[argv.index("--report") + 1:] or NAMES
        for name in wanted:
            for rel, number, what in sites[name]:
                print("%s:%d: %s" % (rel, number, what))
        return 0
    failed = check_sites("scheduler", sites, BASELINE, "use the OM scheduler (om_after, om_task steps, om_prompt, OM handles, declared refs)", banned=BANNED)
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
