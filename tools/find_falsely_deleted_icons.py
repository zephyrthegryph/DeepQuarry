#!/usr/bin/env python3
"""Scan the Tier 4 cleanup deletion list for case-mismatch false positives.

For each deleted icon path that the scanner flagged as orphan, look
again — but case-insensitively — at whether the source actually
references it. Real orphans show up unchanged; case-mismatched ones
(like icons/mob/animal_VG.png referenced as animal_vg.dmi) come back
flagged as deleted-in-error.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def gather_source_lowercase() -> str:
    """Read every interesting source file into one big lowercased blob.
    Lowercasing both sides of the comparison gives us case-insensitive
    `in` checks.
    """
    parts: list[str] = []
    for d, exts in (
        ("code", ("*.dm",)),
        ("modular_chomp", ("*.dm",)),
        ("modular_dq", ("*.dm",)),
        ("maps", ("*.dmm", "*.dm")),
        ("modular_chomp/maps", ("*.dmm",)),
        ("modular_dq/maps", ("*.dmm",)),
        ("interface", ("*.dmf",)),
    ):
        root = ROOT / d
        if not root.exists():
            continue
        for ext in exts:
            for f in root.rglob(ext):
                try:
                    parts.append(f.read_text(encoding="utf-8", errors="replace"))
                except OSError:
                    pass
    return ("\n".join(parts)).lower()


def main() -> None:
    # Pull every icon deleted in the Tier 4 cleanup commit.
    out = subprocess.check_output(
        ["git", "show", "--diff-filter=D", "--name-only", "--no-renames",
         "e3251642d4"],
        cwd=ROOT,
        text=True,
    )
    deleted = [
        line.strip()
        for line in out.splitlines()
        if line.endswith(".png") or line.endswith(".dmi") or line.endswith(".dmi.toml")
    ]
    pngs = [p for p in deleted if p.endswith(".png")]
    print(f"Tier 4 deleted {len(pngs)} PNGs (plus paired TOMLs/DMIs)")

    src = gather_source_lowercase()
    print(f"Source corpus: {len(src)/1e6:.1f} MB (lowercased)")

    false_positives: list[str] = []
    for p in pngs:
        rel_lower = p.lower()
        # Candidates to check — same shape as the original scanner but
        # all lowercase.
        rel_dmi = rel_lower[:-4] + ".dmi" if rel_lower.endswith(".png") else rel_lower
        candidates = (
            rel_lower,
            rel_lower.replace("/", "\\"),
            Path(rel_lower).name,
            rel_dmi,
            rel_dmi.replace("/", "\\"),
            Path(rel_dmi).name,
        )
        if any(c in src for c in candidates):
            false_positives.append(p)

    print(f"\nFalse positives ({len(false_positives)}):")
    for p in false_positives:
        print(f"  {p}")

    out_file = ROOT / "tools" / "_falsely_deleted.txt"
    out_file.write_text("\n".join(false_positives) + "\n", encoding="utf-8")
    print(f"\nList -> {out_file.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
