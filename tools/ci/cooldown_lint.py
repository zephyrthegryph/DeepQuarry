#!/usr/bin/env python3
"""Raw world.time cooldown lint (doc/rewrite/object_model_core.md sec 16, "Rate-limit something").

A cooldown is COOLDOWN_DECLARE()/COOLDOWN_START()/COOLDOWN_FINISHED()/COOLDOWN_TIMELEFT()
(code/__defines/cooldowns.dm), or om_after()/om_deadline() when something must happen at the
deadline. This counts the hand-rolled form: a line that compares world.time with something,
such as `if(world.time < last_use + delay)` or `if(next_use > world.time)`. Arithmetic like
`world.time - start` (elapsed time) is not a compare and is not counted.

Skipped: code/modules/unit_tests, code/controllers (MC and subsystem internals),
code/datums/om (the scheduler core), #define lines, and every line carrying
`// ALLOW(cooldown): <reason>` on it or on the comment line above it
(tools/ci/allow_annotations.py).

The count may fall, never rise: tools/ci/cooldown_baseline.txt holds the ceiling.

    python tools/ci/cooldown_lint.py            # the CI check
    python tools/ci/cooldown_lint.py --report   # every counted site
    python tools/ci/cooldown_lint.py --update   # rewrite the ceiling to today's count
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "cooldown_baseline.txt")
SKIP_DIRS = ("code/modules/unit_tests/", "code/controllers/", "code/datums/om/")

CMP = r"(?:>=|<=|(?<![<>=!])>(?![>=])|(?<![<>=])<(?![<=]))"
COMPARE = re.compile(rf"(?<![\w.])world\.time\s*{CMP}|{CMP}\s*world\.time(?![\w])")


def norm(text):
    return " ".join(text.split())


def scan():
    sites = []
    for path in sorted(glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)):
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        if rel.startswith(SKIP_DIRS):
            continue
        with open(path, encoding="utf-8", errors="ignore") as f:
            raw = f.read()
        if "world.time" not in raw:
            continue
        raw_lines = raw.split("\n")
        for number, line in enumerate(code_only(raw).split("\n"), 1):
            if line.lstrip().startswith("#"):
                continue
            if COMPARE.search(line) and not allowed(raw_lines, number, "cooldown"):
                sites.append((rel, number, norm(raw_lines[number - 1])))
    return sites


def main(argv):
    counted = scan()
    if "--report" in argv:
        for rel, number, text in counted:
            print("%s:%d: %s" % (rel, number, text))
    count = len(counted)
    if "--update" in argv:
        with open(BASELINE, "w", encoding="utf-8", newline="\n") as f:
            f.write("# Raw world.time cooldown compares (tools/ci/cooldown_lint.py). May fall, never rise.\n")
            f.write("# Lower it after a sweep: `python tools/ci/cooldown_lint.py --update`.\n")
            f.write("%d\n" % count)
        print("cooldown lint baseline: %d" % count)
    failed = False
    if "--update" in argv:
        return 0
    ceiling = None
    if os.path.exists(BASELINE):
        with open(BASELINE, encoding="utf-8") as f:
            for line in f:
                if line.strip() and not line.startswith("#"):
                    ceiling = int(line.strip())
    if ceiling is None:
        print("cooldown: %d raw world.time compares, FAIL (no ceiling in %s)" % (count, BASELINE))
        return 1
    if count > ceiling:
        print("cooldown: %d raw world.time compares, FAIL (ceiling %d). Use COOLDOWN_START/COOLDOWN_FINISHED "
              "(code/__defines/cooldowns.dm) or om_after(); `--report` lists the sites." % (count, ceiling))
        failed = True
    elif count < ceiling:
        print("cooldown: %d raw world.time compares, below ceiling %d: lower it with --update" % (count, ceiling))
    else:
        print("cooldown: %d raw world.time compares, ok" % count)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
