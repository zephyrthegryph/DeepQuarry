#!/usr/bin/env python3
"""Find icon files (.png/.dmi) that are never referenced in source.

Catches: 'icons/foo.dmi', "icons\\foo.dmi", icon = 'icons/foo.dmi', etc.
Also catches references by basename inside a directory the code uses
(e.g. icon_state strings — though we don't disambiguate those).

The result is conservative: any string match anywhere in code/, maps/,
modular_chomp/, modular_dq/ counts as a reference, including comments.
A file marked "unreferenced" is very likely actually unreferenced; a
file marked "referenced" might still be dead if its only reference is
in a dead .dm or comment.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_GLOBS = (
    ("code", ("*.dm",)),
    ("modular_chomp", ("*.dm",)),
    ("modular_dq", ("*.dm",)),
    ("maps", ("*.dmm", "*.dm")),
    ("modular_chomp/maps", ("*.dmm",)),
    ("modular_dq/maps", ("*.dmm",)),
    ("interface", ("*.dmf",)),
)

ICON_DIRS = ("icons", "modular_chomp/icons", "modular_dq/icons")
EXCLUDE_DIRS = ("icons/gen",)


def gather_icons() -> list[Path]:
    out = []
    for d in ICON_DIRS:
        root = ROOT / d
        if not root.exists():
            continue
        for ext in ("*.png", "*.dmi"):
            for f in root.rglob(ext):
                rel = f.relative_to(ROOT).as_posix()
                if any(rel.startswith(x) for x in EXCLUDE_DIRS):
                    continue
                out.append(f)
    return out


def gather_source() -> str:
    """Read every interesting source file into one lowercased blob.

    Lowercasing both sides of the comparison gives us case-insensitive
    matching, which is what BYOND and NTFS actually use at runtime. The
    naive case-sensitive version flagged icons/mob/animal_VG.png as
    orphan because vistors.dm/wizards.dm refer to it as
    icons/mob/animal_vg.dmi (lowercase) — caused a Tier 4 false positive
    that broke the build until restored.
    """
    parts: list[str] = []
    for d, exts in SOURCE_GLOBS:
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
    icons = gather_icons()
    print(f"Found {len(icons)} icon files in source")
    print("Reading every .dm/.dmm/.dmf into memory (one pass)…")
    src = gather_source()
    print(f"  -> {len(src)/1e6:.1f} MB of source")

    orphans: list[Path] = []
    for f in icons:
        rel = f.relative_to(ROOT).as_posix().lower()
        # Source-of-truth PNGs are paired with a generated .dmi at the
        # same relative path (PNG + TOML -> DMI via build_step.py). DM
        # code references the .dmi form, but interface/skin.dmf and
        # asset_cache callers reference .png/.webp directly — search
        # for both. Also include the bare filename for icon_state-style
        # lookups and Path-name asset_cache lookups. Source has been
        # lowercased upstream so we compare lowercase-vs-lowercase.
        candidates: set[str] = set()
        candidates.add(rel)
        candidates.add(rel.replace("/", "\\"))
        candidates.add(Path(rel).name)
        if rel.endswith(".png"):
            rel_dmi = rel[:-4] + ".dmi"
            candidates.add(rel_dmi)
            candidates.add(rel_dmi.replace("/", "\\"))
            candidates.add(Path(rel_dmi).name)
        if any(c in src for c in candidates):
            continue
        orphans.append(f)

    orphans.sort(key=lambda p: str(p))
    print(f"  -> {len(orphans)} icons never referenced anywhere in source")
    print()
    buckets: dict[str, list[Path]] = {}
    for o in orphans:
        rel = o.relative_to(ROOT)
        parts = rel.parts
        # Group by 2 path components for icons/foo/* and 3 for modular_*/icons/foo/*
        if parts[0] in ("modular_chomp", "modular_dq") and len(parts) > 3:
            key = "/".join(parts[:3])
        elif len(parts) > 2:
            key = "/".join(parts[:2])
        else:
            key = "/".join(parts[:1])
        buckets.setdefault(key, []).append(o)
    print("Orphan icons by location:")
    for k in sorted(buckets, key=lambda k: -len(buckets[k]))[:30]:
        print(f"  {len(buckets[k]):4d}  {k}")
    out = ROOT / "tools" / "_orphan_icons.txt"
    out.write_text(
        "\n".join(o.relative_to(ROOT).as_posix() for o in orphans) + "\n",
        encoding="utf-8",
    )
    print(f"\nFull list -> {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
