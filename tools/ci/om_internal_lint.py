#!/usr/bin/env python3
"""Object-model internal time-mechanism lint (doc/rewrite/time_mechanisms.md).

The public ways to do something later are om_after*() (a call), om_deadline() (a behaviour
hook) and om_task*() (work that takes time: om_task_start, om_task_timed, om_task_periodic,
om_task_slices). The machinery under them -- periodic lanes, timed-action plumbing, lane
slices, staggered/drift steps, world-lane boot -- is named `_om_*` and is internal to the
scheduler core. This fails on any `_om_*` name used outside code/datums/om/ and
code/__defines/om.dm (where the public macros map onto them), unless the line carries
`// ALLOW(om_internal): <reason>` (tools/ci/allow_annotations.py).

    python tools/ci/om_internal_lint.py
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from allow_annotations import allowed  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
INTERNAL = re.compile(r"(?<![\w])_om_\w+")
SKIP = ("code/datums/om/", "code/__defines/om.dm")


def main():
    bad = []
    for top in ("code", "maps"):
        for path in sorted(glob.glob(os.path.join(ROOT, top, "**", "*.dm"), recursive=True)):
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            if rel.startswith(SKIP):
                continue
            with open(path, encoding="utf-8", errors="replace") as handle:
                raw = handle.read()
            if "_om_" not in raw:
                continue
            lines = raw.split("\n")
            for number, line in enumerate(lines, 1):
                code = line.split("//", 1)[0]
                m = INTERNAL.search(code)
                if m and not allowed(lines, number, "om_internal"):
                    bad.append("%s:%d: %s is internal to the OM scheduler: use om_after / om_deadline / om_task_*"
                               % (rel, number, m.group(0)))
    for line in bad:
        print(line)
    print("om_internal_lint: %d internal uses outside code/datums/om" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
