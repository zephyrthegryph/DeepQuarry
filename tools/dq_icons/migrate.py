#!/usr/bin/env python3
"""Bulk-extract every .dmi under given roots into PNG + .dmi.toml sidecars.

Architecture A workflow:
  * For each .dmi at path/to/foo.dmi we write path/to/foo.png and
    path/to/foo.dmi.toml alongside it. The .dmi stays committed (it is
    both the build artifact AND the upstream-merge anchor).
  * PNG + TOML become the editable sources. The build's repack step
    rebuilds the .dmi from them.

Re-runnable. By default skips DMIs that already have an extracted PNG
*and* TOML newer than the .dmi (the .dmi has not been changed since
extraction). Pass --force to re-extract everything.

Stateless placeholder DMIs (0 icon_states) are skipped — they cannot be
round-tripped via this tool, and they're not editable content anyway.

Usage:
    python -m tools.dq_icons.migrate icons modular_chomp/icons maps
    python -m tools.dq_icons.migrate --force icons
    python -m tools.dq_icons.migrate --dry-run icons
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dmi import Dmi  # type: ignore  # noqa: E402

from . import extract as extract_mod  # noqa: E402


def _is_fresh(dmi: Path) -> bool:
    """True if PNG and TOML sidecars exist and are at least as new as the .dmi.

    Used to skip files that were already extracted on a prior run and
    haven't been touched since. Conservative — any whiff of staleness
    triggers a re-extract.
    """
    png = dmi.with_suffix(".png")
    toml = dmi.with_suffix(".dmi.toml")
    if not (png.exists() and toml.exists()):
        return False
    dmi_mtime = dmi.stat().st_mtime
    return png.stat().st_mtime >= dmi_mtime and toml.stat().st_mtime >= dmi_mtime


def migrate(roots: list[Path], force: bool, dry_run: bool) -> dict[str, int]:
    counters = {"processed": 0, "skipped_fresh": 0, "skipped_stateless": 0, "failed": 0}
    failures: list[tuple[Path, str]] = []

    all_dmis: list[Path] = []
    for r in roots:
        if not r.exists():
            print(f"warn: {r} does not exist; skipping", file=sys.stderr)
            continue
        all_dmis.extend(sorted(r.rglob("*.dmi")))

    total = len(all_dmis)
    print(f"found {total} DMI(s) under {', '.join(map(str, roots))}")
    if not total:
        return counters

    last_progress = time.monotonic()
    for i, p in enumerate(all_dmis, 1):
        try:
            if not force and _is_fresh(p):
                counters["skipped_fresh"] += 1
            else:
                if dry_run:
                    counters["processed"] += 1
                else:
                    # Pre-flight: parse the DMI to detect stateless cases
                    # before extract() so we count them separately.
                    d = Dmi.from_file(str(p))
                    if not d.states:
                        counters["skipped_stateless"] += 1
                    else:
                        result = extract_mod.extract(p)
                        if result is None:
                            counters["skipped_stateless"] += 1
                        else:
                            counters["processed"] += 1
        except Exception as e:  # noqa: BLE001
            counters["failed"] += 1
            failures.append((p, f"{type(e).__name__}: {e}"))

        # Progress heartbeat every ~5s, plus a final tick.
        now = time.monotonic()
        if now - last_progress >= 5 or i == total:
            print(
                f"  [{i}/{total}] processed={counters['processed']} "
                f"skipped_fresh={counters['skipped_fresh']} "
                f"skipped_stateless={counters['skipped_stateless']} "
                f"failed={counters['failed']}",
                flush=True,
            )
            last_progress = now

    if failures:
        print("\nfailures:")
        for p, msg in failures[:50]:
            print(f"  {p}: {msg}")
        if len(failures) > 50:
            print(f"  ... and {len(failures) - 50} more")

    return counters


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("roots", nargs="+", type=Path)
    ap.add_argument("--force", action="store_true", help="Re-extract even if sidecars are fresh.")
    ap.add_argument("--dry-run", action="store_true", help="Count only; don't write.")
    args = ap.parse_args()
    counters = migrate(args.roots, args.force, args.dry_run)
    return 1 if counters["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
