"""Reject production object-model declarations that require a live instance.

DM cannot enumerate an overridden instance proc's builder effects without
constructing its owner. Static declaration datums are the safe boot route.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


OVERRIDE = re.compile(r"^(/[^\s(]+?)/(?:proc/)?om_declare\s*\(", re.MULTILINE)
INCLUDE = re.compile(r'^\s*#include\s+"([^"]+\.dm)"', re.MULTILINE)
FIXTURE_PARTS = {"unit_tests", "benchmarks"}


def find_instance_declarations(root: Path) -> list[str]:
    manifest = (root / "deepquarry.dme").read_text(encoding="utf-8", errors="replace")
    failures: list[str] = []
    for include in INCLUDE.findall(manifest):
        relative = Path(include.replace("\\", "/"))
        if FIXTURE_PARTS.intersection(relative.parts):
            continue
        source_path = root / relative
        source = source_path.read_text(encoding="utf-8", errors="replace")
        for match in OVERRIDE.finditer(source):
            owner = match.group(1)
            if owner == "/datum":
                continue
            line = source.count("\n", 0, match.start()) + 1
            failures.append(
                f"{relative.as_posix()}:{line}: {owner}/om_declare requires an instance; "
                "use /datum/object_model/declaration with target_type and build()"
            )
    return failures


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    failures = find_instance_declarations(root)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print("Object-model production declarations are static.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
