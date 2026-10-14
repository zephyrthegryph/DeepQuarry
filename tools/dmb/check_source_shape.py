#!/usr/bin/env python3
"""Enforce DESIGN.md's Rust source file size limit across workspace targets."""
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parent
    directories = ("src", "tests", "examples", "dev-scripts", "crates")
    failures = []
    for directory in directories:
        for path in sorted((root / directory).rglob("*.rs")):
            if "target" in path.relative_to(root).parts:
                continue
            count = len(path.read_text(encoding="utf-8-sig").splitlines())
            if count > 1000:
                failures.append((path.relative_to(root).as_posix(), count))
    for path, count in failures:
        print(f"{path}: {count} lines exceeds DESIGN.md limit of 1000")
    if not failures:
        print("Rust workspace source file size gate passed")
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
