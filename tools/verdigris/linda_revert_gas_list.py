"""Revert `LINDA_GAS_LIST(...)` rewrites — DM's preprocessor doesn't handle
function-like macro expansion followed by `.member` access cleanly. Restore
the original `.gas` whole-list references; those callsites will need per-site
LINDA adaptation (manual rewrite) when LINDA actually goes active.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

REVERT_RE = re.compile(r"LINDA_GAS_LIST\(([^)]+)\)")


def revert_file(path: Path) -> int:
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, FileNotFoundError):
        return 0
    new_text, n = REVERT_RE.subn(r"\1.gas", text)
    if n > 0:
        path.write_text(new_text, encoding="utf-8", newline="")
    return n


def main() -> int:
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
