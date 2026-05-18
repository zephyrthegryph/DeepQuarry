#!/usr/bin/env python3
"""Build-time step: regenerate stale .dmi files into a build-output tree.

For each foo.dmi.toml + foo.png pair under one of the source roots, emit
the corresponding .dmi into the build-output tree at the same relative
path. Example:

    icons/effects/effects.dmi.toml + icons/effects/effects.png
    -> icons/gen/icons/effects/effects.dmi

The build-output tree is wired into vorestation.dme as a FILE_DIR that
takes precedence over the committed upstream tree — when an output .dmi
exists it shadows the committed icons/... .dmi at runtime, falling back
to upstream when missing.

Dirty rule (any of):
  * output .dmi is missing
  * .png is newer than output .dmi
  * .dmi.toml is newer than output .dmi

Usage:
    python -m tools.dq_icons.build_step --output icons/gen \
        icons modular_chomp/icons modular_dq/icons maps
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from . import repack as repack_mod  # noqa: E402


def _output_dmi_path(toml: Path, output_root: Path) -> Path:
    # foo/bar/baz.dmi.toml under cwd -> output_root/foo/bar/baz.dmi
    rel = toml.with_suffix("")  # strip .toml -> foo/bar/baz.dmi
    return output_root / rel


def _is_dirty(toml: Path, out_dmi: Path) -> tuple[bool, str]:
    png = toml.with_suffix("").with_suffix(".png")  # foo.dmi.toml -> foo.png
    if not png.exists():
        return False, "no .png sibling"
    if not out_dmi.exists():
        return True, "output missing"
    out_mt = out_dmi.stat().st_mtime
    if png.stat().st_mtime > out_mt:
        return True, "png newer"
    if toml.stat().st_mtime > out_mt:
        return True, "toml newer"
    return False, "fresh"


def run(roots: list[Path], output_root: Path) -> int:
    tomls: list[Path] = []
    for r in roots:
        if not r.exists():
            continue
        # Don't descend into the output tree itself if it happens to live
        # under one of the source roots (e.g. icons/gen inside icons/).
        for toml in r.rglob("*.dmi.toml"):
            try:
                toml.relative_to(output_root)
                continue  # the toml is inside the output tree — skip
            except ValueError:
                pass
            tomls.append(toml)
    tomls.sort()

    if not tomls:
        return 0

    repacked = 0
    skipped = 0
    failures: list[tuple[Path, str]] = []
    t0 = time.monotonic()
    for toml in tomls:
        out_dmi = _output_dmi_path(toml, output_root)
        dirty, _reason = _is_dirty(toml, out_dmi)
        if not dirty:
            skipped += 1
            continue
        try:
            repack_mod.repack(toml, out_path=out_dmi)
            repacked += 1
        except Exception as e:  # noqa: BLE001
            failures.append((toml, f"{type(e).__name__}: {e}"))

    dt = time.monotonic() - t0
    print(
        f"icon-repack: {repacked} regenerated into {output_root}, "
        f"{skipped} up-to-date, {len(failures)} failed in {dt:.1f}s"
    )
    for p, msg in failures[:20]:
        print(f"  FAIL {p}: {msg}")
    if len(failures) > 20:
        print(f"  ... and {len(failures) - 20} more")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("roots", nargs="+", type=Path, help="Source roots to scan for *.dmi.toml.")
    ap.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Build-output root. Generated .dmi files land at <output>/<source-relative-path>.",
    )
    args = ap.parse_args()
    return run(args.roots, args.output.resolve())


if __name__ == "__main__":
    sys.exit(main())
