#!/usr/bin/env python3
"""Rebuild code/modules/unit_tests/snapshots/compiler_behaviour.txt from a dump of the compiler behaviour probe.

The dump is data/compiler_behaviour.txt written by /datum/unit_test/dq_compiler_behaviour. Pin it from a DreamMaker build, never from the
native one (the pin is what native has to reproduce):

  DQ_COMPILER=dreammaker bash tools/dq_focused_test.sh --force /datum/unit_test/dq_compiler_behaviour
  python tools/dmb/scripts/pin_behaviour.py data/compiler_behaviour.txt > code/modules/unit_tests/snapshots/compiler_behaviour.txt

The rows are the ones compiler_probe_pin_rows() builds in DM: the small sections (iterators, branches, spread) whole, and one digest per
folded operator over its constant forms (the part of a `fold` row before ` | `).
"""
import hashlib
import sys


def main(path):
    by_op = {}
    pins = []
    for row in open(path, encoding="utf-8").read().split("\n"):
        if row.startswith("fold "):
            op = row.split(" ")[1]
            bar = row.find(" | ")
            by_op.setdefault(op, []).append(row[:bar])
        elif row.startswith(("iter ", "branches ", "spread ")):
            pins.append(row)
    for op, group in by_op.items():
        pins.append(f"fold {op} {len(group)} {hashlib.md5(chr(10).join(group).encode('utf-8')).hexdigest()}")
    print("# GENERATED from a DreamMaker build by tools/dmb/scripts/pin_behaviour.py; see dq_compiler_behaviour_probe.dm.")
    print("\n".join(pins))


main(sys.argv[1])
