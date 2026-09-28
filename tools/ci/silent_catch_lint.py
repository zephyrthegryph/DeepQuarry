"""Silent-catch lint (doc/rewrite/object_model_core.md, lifecycle diagnostics).

A try/catch that swallows an exception hides the runtime from world/Error: no
file/line/stack in the runtime log, and a test run that should fail passes (or
hangs with nothing logged -- the OM sleep-guard trampoline did exactly that).

Every `catch` block must do one of:

    report     dq_report_caught(e, "context") (or the OM scheduler's
               report_caught(e, msg)) -- world/Error with a context line;
               counts as a runtime (fails a test run)
    rethrow    throw ...
    trace      stack_trace(...) / CRASH(...) / world.Error(...)
    log        log_*(...) / Fail(...)  -- allowed outside the strict dirs only,
               for catches of *expected* failures (bad user JSON, a missing file)

Inside the strict dirs (the object-model core, lifecycle, the controllers and
the error handler -- everything that wraps other code's callbacks) a plain
log is not enough: the block must report, rethrow or trace.

Escape hatch: `// ALLOW(silent_catch): reason` on the catch line, the line
above it, or the first line of its block. The reason is mandatory.

Usage:
    python tools/ci/silent_catch_lint.py            # the CI check
    python tools/ci/silent_catch_lint.py --report   # also list every catch and how it passes
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from allow_annotations import allowed, names_on  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

STRICT_DIRS = (
    "code/datums/om/",
    "code/datums/lifecycle/",
    "code/controllers/",
    "code/modules/error_handler/",
)

CATCH_RE = re.compile(r"^(\s*)catch\b\s*(\([^)]*\))?\s*(.*)$")
STRICT_OK = re.compile(r"\b(?:dq_)?report_caught\s*\(|\bthrow\b|\bstack_trace\s*\(|\bCRASH\s*\(|\bworld\.Error\s*\(")
LOOSE_OK = re.compile(STRICT_OK.pattern + r"|\blog_\w+\s*\(|\bFail\s*\(|\bTEST_FAIL\b")


def indent_width(s):
    return len(s.expandtabs(4)) - len(s.expandtabs(4).lstrip())


def strip_comment(line):
    # Good enough for DM: drop a trailing // comment outside of strings.
    out, in_str = [], None
    i = 0
    while i < len(line):
        c = line[i]
        if in_str:
            if c == "\\":
                out.append(line[i:i + 2])
                i += 2
                continue
            if c == in_str:
                in_str = None
        elif c in "\"'":
            in_str = c
        elif line.startswith("//", i):
            break
        out.append(c)
        i += 1
    return "".join(out)


def check_file(path, rel):
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().split("\n")
    strict = rel.startswith(STRICT_DIRS)
    ok_re = STRICT_OK if strict else LOOSE_OK
    problems, seen = [], []
    for i, raw in enumerate(lines):
        code = strip_comment(raw)
        m = CATCH_RE.match(code)
        if not m:
            continue
        base = indent_width(m.group(1))
        inline = m.group(3).strip()
        body = [inline] if inline else []
        j = i + 1
        while j < len(lines):
            nxt = lines[j]
            if nxt.strip() == "":
                j += 1
                continue
            if indent_width(nxt) <= base:
                break
            body.append(nxt)
            j += 1
        # The one ALLOW system (allow_annotations.py): the catch line or a comment line above it;
        # a catch also takes the annotation on the first line of its body.
        if allowed(lines, i + 1, "silent_catch") or (i + 1 < len(lines) and "silent_catch" in names_on(lines[i + 1])):
            seen.append((rel, i + 1, "ALLOW"))
            continue
        text = "\n".join(strip_comment(b) for b in body)
        if ok_re.search(text):
            seen.append((rel, i + 1, "ok"))
            continue
        why = "strict dir: report/rethrow/trace required" if strict else "no log/report/rethrow"
        problems.append(f"{rel}:{i + 1}: silent catch ({why}); use dq_report_caught(e, \"context\") "
                        f"or annotate `// ALLOW(silent_catch): reason`")
    return problems, seen


def main():
    report = "--report" in sys.argv
    problems, seen = [], []
    for base in ("code", "maps"):
        for dirpath, _, files in os.walk(os.path.join(ROOT, base)):
            for name in files:
                if not name.endswith(".dm"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT).replace("\\", "/")
                p, s = check_file(path, rel)
                problems += p
                seen += s
    if report:
        for rel, line, how in seen:
            print(f"{rel}:{line}: {how}")
    for p in problems:
        print(p)
    if problems:
        print(f"silent_catch_lint: {len(problems)} silent catch block(s).")
        return 1
    print(f"silent_catch_lint: {len(seen)} catch blocks, none silent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
