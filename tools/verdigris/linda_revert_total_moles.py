"""Revert just the `.total_moles()` rewrites from linda_rewrite_xgm_callsites.py.

XGM's /datum/gas_mixture has `var total_moles`, not a proc, so calling it as
`.total_moles()` errors in the default build. We can't shim because DM forbids
var/proc name collision. So undo those specific edits and leave them as
per-site hand-edits for future LINDA-conversion PRs.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ERR = REPO / "modular_dq/doc/linda_compile_errors_by_file.txt"

# Match `.total_moles()` (the rewritten form) and revert to `.total_moles` (XGM var).
# Only revert in CHOMP source files (not in modular_dq/code/atmospherics/* which is LINDA-side).
REVERT_RE = re.compile(r"\.total_moles\(\)")


def revert_file(path: Path) -> int:
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, FileNotFoundError):
        return 0
    new_text, n = REVERT_RE.subn(".total_moles", text)
    if n > 0:
        path.write_text(new_text, encoding="utf-8", newline="")
    return n


def main() -> int:
    # Walk all CHOMP source dirs; revert any file containing the rewritten form.
    chomp_dirs = [REPO / "code", REPO / "modular_chomp"]
    changed = 0
    total = 0
    for root in chomp_dirs:
        for path in root.rglob("*.dm"):
            n = revert_file(path)
            if n > 0:
                changed += 1
                total += n
                print(f"  {path.relative_to(REPO)}: {n}", file=sys.stderr)
    print(f"\nreverted {total} edits in {changed} files", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
