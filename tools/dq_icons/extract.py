#!/usr/bin/env python3
"""Extract a .dmi into a sidecar TOML (metadata) + sprite-sheet PNG (no DMI chunk).

Round-trip companion to repack.py. Together they let us treat a .dmi as an
editable PNG + a small TOML, so the canonical source-of-truth becomes the
PNG (paintable in any image editor) and the .dmi is a generated artifact.

Usage:
    python -m tools.dq_icons.extract path/to/foo.dmi
    # produces path/to/foo.png  +  path/to/foo.dmi.toml
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

# Reuse the existing CHOMP/upstream DMI library — same parser used by the
# git merge driver, so we get the same coverage on width/height, per-state
# dirs/frames/delays/loop/rewind/movement/hotspots.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dmi import Dmi  # type: ignore  # noqa: E402

from PIL import Image  # noqa: E402


def _toml_escape(s: str) -> str:
    # TOML basic strings disallow raw control chars (<0x20) except for
    # specific escapes (\t \n \r). BYOND state names sometimes contain
    # raw bytes like \x1f, so escape any control char as \uXXXX.
    out = []
    for ch in s:
        cp = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\b":
            out.append("\\b")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\f":
            out.append("\\f")
        elif ch == "\r":
            out.append("\\r")
        elif cp < 0x20 or cp == 0x7F:
            out.append(f"\\u{cp:04X}")
        else:
            out.append(ch)
    return "".join(out)


def _state_to_toml(state) -> str:
    out = [f'[[state]]']
    out.append(f'name = "{_toml_escape(state.name)}"')
    out.append(f"dirs = {state.dirs}")
    out.append(f"frames = {state.framecount}")
    if state.framecount > 1 and state.delays:
        # Drop trailing repeats: BYOND fills out delays to framecount by
        # repeating the last value, so a list like [1, 1, 1, 1] is the
        # same as [1]. Keep the shortest equivalent.
        delays = list(state.delays)
        while len(delays) > 1 and delays[-1] == delays[-2]:
            delays.pop()
        out.append("delays = [" + ", ".join(str(d) for d in delays) + "]")
    if state.loop:
        out.append(f"loop = {state.loop}")
    if state.rewind:
        out.append("rewind = true")
    if state.movement:
        out.append("movement = true")
    if state.hotspots and any(h is not None for h in state.hotspots):
        # Compress runs: emit one entry per distinct hotspot run.
        # TOML requires an array, not repeated keys.
        runs = []
        current = object()  # sentinel that won't equal anything
        for i, h in enumerate(state.hotspots):
            if h != current:
                if h is not None:
                    runs.append((i, h[0], h[1]))
                current = h
        entries = ", ".join(
            f"{{ frame = {f + 1}, x = {x}, y = {y} }}" for f, x, y in runs
        )
        out.append(f"hotspots = [{entries}]")
    return "\n".join(out)


def extract(dmi_path: Path) -> tuple[Path, Path] | None:
    dmi = Dmi.from_file(str(dmi_path))

    # Stateless placeholder DMIs: nothing to extract. Caller should
    # leave the original .dmi committed and skip emitting PNG/TOML.
    if not dmi.states:
        return None

    # Sprite-sheet PNG: identical layout to what Dmi.to_file would produce
    # (sqrt-square grid, state→frame→dir order). This is also the layout
    # we re-pack from, so users editing the PNG are editing in the same
    # coordinate space the repack expects.
    num_cells = sum(len(s.frames) for s in dmi.states)
    cols = math.ceil(math.sqrt(num_cells))
    rows = math.ceil(num_cells / cols)
    sheet = Image.new("RGBA", (cols * dmi.width, rows * dmi.height))
    i = 0
    for state in dmi.states:
        for frame in state.frames:
            sheet.paste(frame, ((i % cols) * dmi.width, (i // cols) * dmi.height))
            i += 1

    png_path = dmi_path.with_suffix(".png")
    sheet.save(str(png_path), "png", optimize=True)

    # TOML sidecar: header + one [[state]] block per state.
    toml_lines = [
        f"# Generated from {dmi_path.name} — edit the .png and regenerate the .dmi via tools/dq_icons/repack.py.",
        f"width = {dmi.width}",
        f"height = {dmi.height}",
        f"cols = {cols}",
        "",
    ]
    for state in dmi.states:
        toml_lines.append(_state_to_toml(state))
        toml_lines.append("")

    toml_path = dmi_path.with_suffix(".dmi.toml")
    toml_path.write_text("\n".join(toml_lines), encoding="utf-8")

    return png_path, toml_path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dmi", type=Path, nargs="+")
    args = ap.parse_args()
    for p in args.dmi:
        result = extract(p)
        if result is None:
            print(f"{p} -> SKIP (stateless placeholder)")
            continue
        png, toml = result
        print(f"{p} -> {png.name} + {toml.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
