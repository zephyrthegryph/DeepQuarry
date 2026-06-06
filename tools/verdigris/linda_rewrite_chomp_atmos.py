#!/usr/bin/env python3
"""
Rewrite XGM gas_mixture call sites in CHOMP atmos files to LINDA equivalents.

CHOMP atmos was deleted and re-restored; it uses XGM API (`mix.total_moles` var,
`mix.gas[GAS_X]` dict, `SSair.current_cycle` var). LINDA exposes these as procs
or under different names. This script does the mechanical conversion across the
restored CHOMP atmos files.

Conversions:
  - `mix.total_moles`       → `mix.total_moles()`    (var → proc)
  - `mix.gas[GAS_X]`        → `LINDA_GAS_AMT(mix, GAS_X)`  (var dict → macro)
  - `mix.gas[GAS_X] = Y`    → `mix.set_moles(...., Y)`  (NOT handled — bare hand)
  - `mix.gas[GAS_X] += Y`   → `mix.adjust_moles(...., Y)` (NOT handled — bare hand)
  - `SSair.current_cycle`   → `SSair.times_fired`     (renamed in LINDA)

Read-only patterns are safe to rewrite mechanically. Write/mutation patterns
need hand review — those are flagged and skipped.

Run from worktree root:
  python tools/verdigris/linda_rewrite_chomp_atmos.py [paths...]

If no paths given, defaults to:
  code/ATMOSPHERICS/
  code/game/machinery/atmoalter/
  code/game/machinery/pipe/
  code/game/machinery/air_alarm.dm
  code/game/machinery/atmo_control.dm
  code/game/machinery/cryo.dm
  code/game/machinery/fire_alarm.dm
  code/game/machinery/spaceheater.dm
  code/game/machinery/airconditioner_vr.dm
  code/game/machinery/atm_ret_field.dm
  code/game/machinery/bomb_tester_vr.dm
"""

import argparse
import os
import re
import sys
from pathlib import Path


DEFAULT_PATHS = [
    "code/ATMOSPHERICS",
    "code/game/machinery/atmoalter",
    "code/game/machinery/pipe",
    "code/game/machinery/air_alarm.dm",
    "code/game/machinery/atmo_control.dm",
    "code/game/machinery/cryo.dm",
    "code/game/machinery/fire_alarm.dm",
    "code/game/machinery/spaceheater.dm",
    "code/game/machinery/airconditioner_vr.dm",
    "code/game/machinery/atm_ret_field.dm",
    "code/game/machinery/bomb_tester_vr.dm",
    "code/game/machinery/computer/atmos_control.dm",
    "code/game/machinery/computer/shutoff_monitor.dm",
    "code/modules/admin/verbs/atmosdebug.dm",
    "code/modules/admin/verbs/diagnostics.dm",
    "code/modules/multiz/pipes.dm",
    "code/modules/projectiles/guns/magnetic/gasthrower.dm",
    "code/modules/reagents/machinery/distillery.dm",
    "code/modules/overmap/ships/engines/gas_thruster.dm",
    "code/modules/overmap/ships/engines/gas_thruster_vr.dm",
    "code/modules/power/turbine.dm",
    "code/modules/power/generator.dm",
    "code/modules/power/singularity/collector.dm",
]

# Patterns to rewrite. Each is (regex, replacement, description).
# The regex must NOT match inside string literals (we use a simple heuristic:
# don't run on lines starting with `//` after stripping leading whitespace, and
# don't run on lines that look like define/declaration comments).

# `mix.total_moles` (var read) → `mix.total_moles()` (proc call)
# - Avoid matching `mix.total_moles =` (write — would break).
# - Avoid matching `mix.total_moles(...)` (already proc call).
# - Avoid matching `mix.total_moles_*` or `mix.total_moles2` (longer ident).
# Pattern: \.total_moles(?![a-zA-Z0-9_(=])  — followed by non-ident, non-`(`, non-`=`.
RE_TOTAL_MOLES = re.compile(r"\.total_moles(?![a-zA-Z0-9_(=])")

# `mix.gas[X]` (read) → `LINDA_GAS_AMT(mix, X)`
# - Match `<ident>.gas[<expr>]` but NOT followed by `=` or `+=` etc (write).
# - We use a lookahead to make sure the next non-space char isn't an assignment.
# - Use a backref to capture both the receiver and the key.
# - Skip if line is a write site (handled separately or by hand).
RE_GAS_READ = re.compile(
    r"\b([A-Za-z_][A-Za-z_0-9.]*)\.gas\[([^\]]+)\](?!\s*[+\-*\/]?=)"
)

# `SSair.current_cycle` → `SSair.times_fired` (LINDA renamed).
RE_SSAIR_CYCLE = re.compile(r"\bSSair\.current_cycle\b")


def is_skip_line(line: str) -> bool:
    """Skip comments and obvious non-code lines."""
    s = line.lstrip()
    if s.startswith("//"):
        return True
    if s.startswith("/*") or s.startswith("*"):
        return True
    return False


def is_write_site_for_gas(line: str) -> bool:
    """Heuristic: line contains `mix.gas[...]` followed by `=` / `+=` / `-=`."""
    return bool(re.search(r"\.gas\[[^\]]+\]\s*[+\-*\/]?=", line))


def rewrite_line(line: str) -> tuple[str, list[str]]:
    """Return (rewritten_line, [notes]).

    Notes describe non-mechanical issues (write sites, ambiguity) that need
    hand review.
    """
    notes = []
    if is_skip_line(line):
        return line, notes

    out = line

    # 1. SSair.current_cycle → SSair.times_fired
    out = RE_SSAIR_CYCLE.sub("SSair.times_fired", out)

    # 2. mix.total_moles (read) → mix.total_moles()
    #    Skip if it's a write or already a proc call.
    if not re.search(r"\.total_moles\s*=", out):
        out = RE_TOTAL_MOLES.sub(".total_moles()", out)

    # 3. mix.gas[X] (read) → LINDA_GAS_AMT(mix, X)
    #    Skip write sites — those need hand review.
    if is_write_site_for_gas(out):
        notes.append(
            f"WRITE-SITE: .gas[] assignment in line — hand-rewrite to set_moles/adjust_moles: {line.rstrip()}"
        )
    else:
        out = RE_GAS_READ.sub(r"LINDA_GAS_AMT(\1, \2)", out)

    return out, notes


def rewrite_file(path: Path, dry_run: bool = False) -> tuple[int, list[str]]:
    """Rewrite a single file. Returns (changes, notes)."""
    try:
        original = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        original = path.read_text(encoding="latin-1")

    lines = original.splitlines(keepends=True)
    new_lines = []
    all_notes = []
    changes = 0

    for i, line in enumerate(lines, 1):
        new_line, notes = rewrite_line(line)
        if new_line != line:
            changes += 1
        new_lines.append(new_line)
        for note in notes:
            all_notes.append(f"{path}:{i}: {note}")

    if changes and not dry_run:
        path.write_text("".join(new_lines), encoding="utf-8")

    return changes, all_notes


def iter_dm_files(paths):
    for p in paths:
        path = Path(p)
        if not path.exists():
            print(f"WARN: {p} does not exist; skipping", file=sys.stderr)
            continue
        if path.is_file() and path.suffix == ".dm":
            yield path
        elif path.is_dir():
            for sub in path.rglob("*.dm"):
                yield sub


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("paths", nargs="*", help="files or directories to rewrite")
    ap.add_argument("--dry-run", action="store_true", help="print changes, don't write")
    args = ap.parse_args()

    targets = args.paths or DEFAULT_PATHS
    total_files = 0
    total_changes = 0
    all_notes = []

    for f in iter_dm_files(targets):
        changes, notes = rewrite_file(f, dry_run=args.dry_run)
        if changes:
            total_files += 1
            total_changes += changes
            print(f"{f}: {changes} edits")
        all_notes.extend(notes)

    print(f"\nTotal: {total_changes} edits across {total_files} files")
    if all_notes:
        print(f"\nWRITE-SITES NEEDING HAND REVIEW ({len(all_notes)}):")
        for note in all_notes:
            print(f"  {note}")


if __name__ == "__main__":
    main()
