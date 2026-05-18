#!/usr/bin/env python3
"""Round-trip an existing .dmi through extract + repack, then verify the
result is semantically identical to the original.

Byte equality is NOT the goal — PIL's PNG compression differs from BYOND
and the sprite sheet may be laid out differently. The check is:

  * same width/height
  * same number of states, same names, same order
  * each state has identical dirs/framecount/loop/rewind/movement/delays
  * each frame's pixels are identical (ignoring fully-transparent diffs)
  * hotspot runs identical

A pass means: the regenerated .dmi will behave identically inside BYOND.
"""
from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dmi import Dmi  # type: ignore  # noqa: E402

# Import these as modules so test files can drive them programmatically.
from . import extract as extract_mod  # type: ignore  # noqa: E402
from . import repack as repack_mod  # type: ignore  # noqa: E402


def _images_equal(left, right) -> bool:
    if left.size != right.size:
        return False
    w, h = left.size
    lp, rp = left.load(), right.load()
    for y in range(h):
        for x in range(w):
            a, b = lp[x, y], rp[x, y]
            # Ignore differences where both pixels are fully transparent —
            # alpha=0 with different RGB is BYOND-equivalent.
            if a != b and (a[3] != 0 or b[3] != 0):
                return False
    return True


def _states_equal(left, right) -> tuple[bool, str]:
    if left.name != right.name:
        return False, f"name {left.name!r} vs {right.name!r}"
    for attr in ("dirs", "framecount", "loop", "rewind", "movement"):
        lv, rv = getattr(left, attr), getattr(right, attr)
        if lv != rv:
            return False, f"state {left.name!r} {attr}: {lv!r} vs {rv!r}"
    # Delays: extract drops trailing repeats; repack expands them back to
    # framecount with the BYOND fill rule. So the in-memory state.delays
    # may be shorter on one side. Normalise both before compare.
    ld = list(left.delays) or [1]
    rd = list(right.delays) or [1]
    fc = max(left.framecount, 1)
    while len(ld) < fc:
        ld.append(ld[-1])
    while len(rd) < fc:
        rd.append(rd[-1])
    if ld[:fc] != rd[:fc]:
        return False, f"state {left.name!r} delays: {ld[:fc]} vs {rd[:fc]}"
    # Hotspots: None vs [None]*fc are equivalent.
    lh = list(left.hotspots) if left.hotspots else [None] * fc
    rh = list(right.hotspots) if right.hotspots else [None] * fc
    if lh != rh:
        return False, f"state {left.name!r} hotspots: {lh} vs {rh}"
    # Frames.
    if len(left.frames) != len(right.frames):
        return False, f"state {left.name!r} frame count: {len(left.frames)} vs {len(right.frames)}"
    for i, (lf, rf) in enumerate(zip(left.frames, right.frames)):
        if not _images_equal(lf, rf):
            return False, f"state {left.name!r} frame {i} pixel mismatch"
    return True, ""


def verify(dmi_path: Path) -> tuple[bool, str]:
    original = Dmi.from_file(str(dmi_path))

    # Stateless placeholder DMIs (no icon_states) are non-content
    # markers. The upstream Dmi.to_file can't write them either
    # (ZeroDivisionError on num_frames=0), so they're outside the
    # migration scope — leave them as committed .dmi files.
    if not original.states:
        return True, "stateless (skipped)"

    # Copy the .dmi into a scratch dir, extract+repack there, then load
    # the regenerated .dmi and compare.
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        scratch_dmi = td / dmi_path.name
        shutil.copy2(dmi_path, scratch_dmi)
        extract_mod.extract(scratch_dmi)
        toml_path = scratch_dmi.with_suffix(".dmi.toml")
        repack_mod.repack(toml_path)
        regenerated = Dmi.from_file(str(scratch_dmi))

    if original.width != regenerated.width or original.height != regenerated.height:
        return False, f"cell size changed: {original.width}x{original.height} vs {regenerated.width}x{regenerated.height}"
    if len(original.states) != len(regenerated.states):
        return False, f"state count: {len(original.states)} vs {len(regenerated.states)}"
    for i, (lo, lr) in enumerate(zip(original.states, regenerated.states)):
        ok, why = _states_equal(lo, lr)
        if not ok:
            return False, f"state index {i}: {why}"
    return True, ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dmi", type=Path, nargs="+")
    args = ap.parse_args()
    failures = 0
    for p in args.dmi:
        try:
            ok, msg = verify(p)
        except Exception as e:  # noqa: BLE001
            ok, msg = False, f"exception: {type(e).__name__}: {e}"
        status = "OK  " if ok else "FAIL"
        print(f"{status} {p}" + (f"  ({msg})" if not ok else ""))
        if not ok:
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
