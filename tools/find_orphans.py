#!/usr/bin/env python3
"""Find .dm files in the source tree that aren't transitively reachable
from deepquarry.dme.

Two passes:
  1. Build the include closure starting from deepquarry.dme: every .dm
     file that the compiler would see during a full build.
  2. Diff against every .dm file under code/, modular_chomp/, modular_dq/.

The diff is the orphan set — code that exists on disk but the compiler
never touches.
"""
from __future__ import annotations

import re
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INCLUDE_RE = re.compile(r'#include\s+"([^"]+\.dm[em]?)"')


def collect_includes(file: Path) -> set[Path]:
    """Return the set of .dm/.dme/.dmm files transitively included from `file`.

    Resolution rule mirrors DreamMaker: paths are relative to the
    including file's directory unless they start with code/, modular_*/,
    etc. (i.e. project-root-anchored).
    """
    if not file.exists():
        return set()
    seen: set[Path] = {file.resolve()}
    q: deque[Path] = deque([file.resolve()])
    while q:
        cur = q.popleft()
        try:
            text = cur.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        cur_dir = cur.parent
        for m in INCLUDE_RE.finditer(text):
            raw = m.group(1).replace("\\", "/")
            # Try project-root-anchored first, then relative to the
            # including file. DreamMaker uses relative-to-source for
            # quoted includes, so prefer that.
            candidates = [
                (cur_dir / raw).resolve(),
                (ROOT / raw).resolve(),
            ]
            for cand in candidates:
                if cand.exists():
                    if cand not in seen:
                        seen.add(cand)
                        if cand.suffix in (".dm", ".dme"):
                            q.append(cand)
                    break
    return seen


def main():
    dme = ROOT / "deepquarry.dme"
    print(f"Walking includes from {dme.relative_to(ROOT)}")
    reached = collect_includes(dme)
    reached_dm = {p for p in reached if p.suffix == ".dm"}
    print(f"  -> {len(reached_dm)} .dm files in the build")

    on_disk = set()
    for root in ("code", "modular_chomp", "modular_dq"):
        on_disk.update((ROOT / root).rglob("*.dm"))
    on_disk = {p.resolve() for p in on_disk}
    print(f"  -> {len(on_disk)} .dm files on disk")

    orphans = sorted(on_disk - reached_dm, key=lambda p: str(p))
    print(f"  -> {len(orphans)} orphans (on disk, not in build)")
    print()
    print("Orphans by top-level directory:")
    buckets: dict[str, list[Path]] = {}
    for o in orphans:
        rel = o.relative_to(ROOT)
        parts = rel.parts
        if parts[0] in ("modular_chomp", "modular_dq") and len(parts) > 2:
            key = "/".join(parts[:3])
        else:
            key = "/".join(parts[:2])
        buckets.setdefault(key, []).append(o)
    for k in sorted(buckets, key=lambda k: -len(buckets[k])):
        print(f"  {len(buckets[k]):4d}  {k}")

    # Write the orphan list to a file for downstream inspection.
    out = ROOT / "tools" / "_orphans.txt"
    out.write_text(
        "\n".join(str(o.relative_to(ROOT)).replace("\\", "/") for o in orphans) + "\n",
        encoding="utf-8",
    )
    print(f"\nFull list -> {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
