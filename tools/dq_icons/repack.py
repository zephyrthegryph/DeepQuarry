#!/usr/bin/env python3
"""Repack a (.png, .dmi.toml) pair into a .dmi.

The inverse of extract.py. Reads the TOML to learn state ordering,
dirs/frames/delays/etc., slices the PNG using the TOML's grid geometry,
and emits a .dmi via the existing CHOMP dmi lib (which writes the
zTXt-encoded "# BEGIN DMI / END DMI" metadata that DreamMaker expects).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

# Python 3.11+ stdlib tomllib; fall back to tomli for older.
try:
    import tomllib  # type: ignore[attr-defined]
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dmi import Dmi, LOOP_UNLIMITED  # type: ignore  # noqa: E402

from PIL import Image  # noqa: E402


def repack(
    toml_path: Path,
    png_path: Path | None = None,
    out_path: Path | None = None,
) -> Path:
    """Repack a (.png, .dmi.toml) pair into a .dmi.

    out_path: where to write the resulting .dmi. Defaults to next to the
    .dmi.toml (legacy behavior). Pass an explicit path to redirect into
    a build-output tree like icons/gen/.
    """
    data = tomllib.loads(toml_path.read_text(encoding="utf-8"))
    width = int(data["width"])
    height = int(data["height"])
    cols = int(data["cols"])
    states: list[dict[str, Any]] = list(data.get("state") or [])

    if png_path is None:
        png_path = toml_path.with_suffix("")  # strip .toml
        if png_path.suffix == ".dmi":
            png_path = png_path.with_suffix(".png")
    sheet = Image.open(str(png_path))
    if sheet.mode != "RGBA":
        sheet = sheet.convert("RGBA")

    dmi = Dmi(width, height)
    i = 0
    for st in states:
        s = dmi.state(
            st["name"],
            loop=int(st.get("loop", LOOP_UNLIMITED)),
            rewind=bool(st.get("rewind", False)),
            movement=bool(st.get("movement", False)),
            dirs=int(st.get("dirs", 1)),
        )
        frames = int(st["frames"])
        delays = list(st.get("delays") or [])

        # State.delays is per-frame (length = framecount), while
        # state.frames is per-cell (length = dirs * framecount). The
        # Dmi.frame() helper grows both lists symmetrically, which is
        # wrong for any state with dirs > 1 — it produces a delay list
        # of length dirs*framecount where each per-frame delay is
        # duplicated dirs times. Bypass .frame() and write the two
        # lists with their correct shapes.
        if frames > 1:
            normalised_delays = list(delays) if delays else [1]
            while len(normalised_delays) < frames:
                normalised_delays.append(normalised_delays[-1])
            s.delays = normalised_delays[:frames]
        else:
            s.delays = []

        for _frame_idx in range(frames):
            for _dir_idx in range(s.dirs):
                px = (i % cols) * width
                py = (i // cols) * height
                cell = sheet.crop((px, py, px + width, py + height))
                assert cell.size == (width, height)
                s.frames.append(cell)
                i += 1
        # Hotspots: emitted as `hotspots = [{...}, {...}]` array of
        # inline tables; one entry per hotspot run (first_frame, x, y).
        # Accept the legacy single-key form too for forwards-compat.
        hs = st.get("hotspots") or st.get("hotspot")
        if hs is not None:
            entries = hs if isinstance(hs, list) else [hs]
            for entry in entries:
                s.hotspot(int(entry["frame"]) - 1, int(entry["x"]), int(entry["y"]))

    out = out_path if out_path is not None else toml_path.with_suffix("")  # foo.dmi.toml -> foo.dmi
    out.parent.mkdir(parents=True, exist_ok=True)
    dmi.to_file(str(out))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("toml", type=Path, nargs="+")
    ap.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Output .dmi path (only valid when repacking a single toml).",
    )
    args = ap.parse_args()
    if args.output is not None and len(args.toml) != 1:
        ap.error("--output requires exactly one toml input")
    for p in args.toml:
        out = repack(p, out_path=args.output)
        print(f"{p} -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
