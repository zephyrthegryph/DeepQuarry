#!/usr/bin/env python3
"""Breakpoint lint (damage.md §6, roadmap D4).

Machines break through one base /obj/machinery/atom_break(), which sets BROKEN,
sends COMSIG_MACHINERY_BROKEN and publishes REACT_KEY_MACHINE_BROKEN. This lint
fails on:
  - any set_broken() definition: call atom_break() instead;
  - an atom_break()/atom_fix() override whose body only sets flags (calls the
    parent, sets or clears BROKEN, updates the icon). The base already does that;
    an override must have real behaviour.

Usage: python3 tools/ci/breakpoint_lint.py
"""

import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SCAN_DIRS = ["code", "modular_chomp"]

# The base definitions this lint protects.
BASES = {"/atom/proc/atom_break", "/atom/proc/atom_fix", "/obj/machinery/atom_break", "/obj/machinery/atom_fix"}

DEF_RE = re.compile(r"^(/[\w/]*?)/(?:proc/|verb/)?(set_broken|atom_break|atom_fix)\s*\(")
FLAG_ONLY = [
    re.compile(r"^\.\s*=\s*\.\.\(.*\)$"),
    re.compile(r"^\.\.\(.*\)$"),
    re.compile(r"^(src\.)?stat\s*(\|=|&=\s*~|\^=)\s*\(?BROKEN\)?$"),
    re.compile(r"^(src\.)?update_icon\(\)$"),
    re.compile(r"^return(\s+\.)?$"),
    re.compile(r"^if\s*\(\s*!?\s*\.\s*\)$"),
    re.compile(r"^if\s*\(\s*!?\s*\(?\s*stat\s*&\s*BROKEN\s*\)?\s*\)$"),
    re.compile(r"^(set_broken|atom_break|atom_fix)\(\)$"),
]


def body_lines(lines, start):
    """The code lines of the proc whose definition is lines[start]."""
    out = []
    for line in lines[start + 1:]:
        if line.strip() == "":
            continue
        if not line.startswith(("\t", " ")):
            break
        code = line.split("//", 1)[0].strip()
        if code:
            out.append(code)
    return out


def main():
    errors = []
    for scan in SCAN_DIRS:
        base = os.path.join(ROOT, scan)
        if not os.path.isdir(base):
            continue
        for dirpath, _, files in os.walk(base):
            for name in files:
                if not name.endswith(".dm"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
                with open(path, encoding="utf-8", errors="replace") as handle:
                    lines = handle.read().split("\n")
                for index, line in enumerate(lines):
                    match = DEF_RE.match(line)
                    if not match:
                        continue
                    owner, proc = match.group(1), match.group(2)
                    full = f"{owner}/{proc}"
                    if full in BASES:
                        continue
                    where = f"{rel}:{index + 1}"
                    if proc == "set_broken":
                        errors.append(f"{where}: {full}() defines set_broken(); call atom_break() (damage.md §6)")
                        continue
                    body = body_lines(lines, index)
                    if all(any(p.match(code) for p in FLAG_ONLY) for code in body):
                        errors.append(f"{where}: {full}() only sets flags; the base /obj/machinery/{proc}() does that, so delete the override")
    for error in errors:
        print(error)
    if errors:
        print(f"{len(errors)} breakpoint lint error(s)")
        return 1
    print("breakpoint lint: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
