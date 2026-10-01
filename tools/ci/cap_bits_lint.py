#!/usr/bin/env python3
"""cap_state bit registry check (code/__defines/cap_bits.dm; dx_conventions.md §2).

Fails when a CAP_* bit is defined outside the registry file, two bits share a value, or a bit
reaches 1<<24 (DM's safe bitwise range). Also rejects raw writes to cap_state outside the framework
(cap_set() is the writer).

    python tools/ci/cap_bits_lint.py
    python tools/ci/cap_bits_lint.py --selftest
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
REGISTRY = "code/__defines/cap_bits.dm"
BIT = re.compile(r"^\s*#define\s+(CAP_[A-Z0-9_]+)\s+\(1\s*<<\s*(\d+)\)")
RAW_WRITE = re.compile(r"\bcap_state\s*(\|=|&=|\^=|=(?!=))")
WRITERS = ("code/datums/capabilities/capabilities.dm",)


def check(files):
    problems = []
    seen = {}
    for rel, text in files:
        for number, line in enumerate(text.split("\n"), 1):
            m = BIT.match(line)
            if m:
                name, shift = m.group(1), int(m.group(2))
                if rel != REGISTRY:
                    problems.append("%s:%d: %s is allocated outside %s" % (rel, number, name, REGISTRY))
                if shift >= 24:
                    problems.append("%s:%d: %s uses bit %d (max 23)" % (rel, number, name, shift))
                if shift in seen:
                    problems.append("%s:%d: %s shares bit %d with %s" % (rel, number, name, shift, seen[shift]))
                seen[shift] = name
            code = re.sub(r"\"[^\"]*\"", "\"\"", line.split("//", 1)[0])
            if RAW_WRITE.search(code) and rel not in WRITERS and not rel.startswith("code/modules/unit_tests/"):
                if re.match(r"^\s*var/", code) or re.match(r"^\t+cap_state\s*=", code) and "/" not in code:
                    # a type default (`cap_state = CAP_X` under a type) is configuration, not a write
                    if re.match(r"^\tcap_state\s*=", code):
                        continue
                problems.append("%s:%d: write cap_state through cap_set()" % (rel, number))
    return problems


def selftest():
    files = [
        (REGISTRY, "#define CAP_A (1<<0)\n#define CAP_B (1<<1)\n"),
        ("code/x.dm", "#define CAP_C (1<<1)\n/obj/x\n\tcap_state = CAP_A\n/obj/x/proc/y()\n\tcap_state |= CAP_B\n"),
        ("code/y.dm", "#define CAP_D (1<<30)\n"),
    ]
    problems = check(files)
    assert any("outside" in p and "CAP_C" in p for p in problems), problems
    assert any("shares bit 1" in p for p in problems), problems
    assert any("max 23" in p for p in problems), problems
    assert any("x.dm:5" in p and "cap_set" in p for p in problems), problems
    assert not any("x.dm:3" in p for p in problems), problems
    print("cap_bits_lint selftest ok")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    files = []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        with open(path, encoding="utf-8", errors="replace") as handle:
            files.append((rel, handle.read()))
    problems = check(files)
    for p in problems:
        print(p)
    print("cap_bits_lint: %d problem(s)" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
