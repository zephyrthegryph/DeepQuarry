#!/usr/bin/env python3
"""Convert every belly-overlay DMI in the project into per-icon-state WebP
animations.

A DMI is a PNG sprite-sheet with extra zTXt metadata describing icon_states,
frame counts, and per-frame delays. The browser inside BYOND's BROWSER widget
can't decode DMIs, so historically the server cropped each frame at runtime
via iconforge and shipped per-frame PNGs — too expensive when a state has
hundreds of frames (e.g. VBOanim_intestine2 = 323 frames).

This script pre-builds one animated WebP per (dmi, icon_state) so the
runtime path becomes: "ship one URL per layer, browser plays it natively."
No iconforge, no per-frame extraction, no JS animation timer.

WebP (instead of APNG) because the file size is roughly an order of
magnitude smaller while quality is identical for our content. WebView2
(used by BYOND 516's BROWSER widget) plays animated WebP natively.

Output: modular_dq/icons/belly_overlays/<safe-dmi-name>__<safe-state>.webp

Run: python3 tools/build_belly_apngs/build.py
"""
from __future__ import annotations

import os
import re
import struct
import subprocess
import sys
import tempfile
import zlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ASSETS_DM = REPO_ROOT / "code/modules/asset_cache/assets/belly_assets.dm"
OUTPUT_DIR = REPO_ROOT / "modular_dq/icons/belly_overlays"

# Extra states we render that aren't in /datum/belly_overlays: the dynamic
# bubbles/mush layers used for liquid belly overlays.
EXTRA_STATES: list[tuple[str, list[str]]] = [
    ("icons/mob/vore_fullscreens/bubbles.dmi", ["mush", "bubbles", "calm"]),
]


# ----- DMI parsing ---------------------------------------------------------


@dataclass
class DmiState:
    name: str
    dirs: int = 1
    frames: int = 1
    delays: list[float] = field(default_factory=list)
    rewind: bool = False


@dataclass
class DmiMeta:
    width: int
    height: int
    states: list[DmiState]


def read_dmi_ztxt(path: Path) -> str | None:
    """Extract the BEGIN DMI/END DMI metadata blob from a DMI's zTXt chunk."""
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return None
    i = 8
    while i < len(data):
        length = struct.unpack(">I", data[i : i + 4])[0]
        ctype = data[i + 4 : i + 8]
        chunk = data[i + 8 : i + 8 + length]
        if ctype == b"zTXt":
            null = chunk.index(b"\x00")
            # chunk[null+1] is the compression method byte
            return zlib.decompress(chunk[null + 2 :]).decode()
        if ctype == b"IEND":
            break
        i += 8 + length + 4
    return None


def parse_dmi_meta(path: Path) -> DmiMeta | None:
    txt = read_dmi_ztxt(path)
    if not txt:
        return None
    width = height = 32
    states: list[DmiState] = []
    current: DmiState | None = None
    for raw in txt.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r'state\s*=\s*"(.*)"\s*$', line)
        if m:
            current = DmiState(name=m.group(1))
            states.append(current)
            continue
        if "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()
        if current is None:
            if key == "width":
                width = int(val)
            elif key == "height":
                height = int(val)
            continue
        if key == "dirs":
            current.dirs = int(val)
        elif key == "frames":
            current.frames = int(val)
        elif key == "delay":
            current.delays = [float(x) for x in val.split(",") if x.strip()]
        elif key == "rewind":
            current.rewind = val.strip() in ("1", "true", "True")
    return DmiMeta(width=width, height=height, states=states)


# ----- Frame extraction ----------------------------------------------------


def state_tile_indices(meta: DmiMeta, state_index: int) -> tuple[int, int]:
    """(start_tile, count) for the state. Tiles are row-major in the sheet."""
    start = 0
    for i, st in enumerate(meta.states):
        if i == state_index:
            break
        start += st.dirs * st.frames
    return start, meta.states[state_index].dirs * meta.states[state_index].frames


def extract_state_frames(
    dmi_path: Path, meta: DmiMeta, state_index: int
) -> list[Image.Image]:
    """SOUTH-facing frames of the state, in playback order (rewind applied)."""
    state = meta.states[state_index]
    start, _count = state_tile_indices(meta, state_index)
    img = Image.open(dmi_path).convert("RGBA")
    cols = img.width // meta.width
    frames: list[Image.Image] = []
    for frame_i in range(state.frames):
        # Frame block layout: [dir0, dir1, ...] for each frame. We want dir0
        # (SOUTH) per frame.
        tile_idx = start + (frame_i * state.dirs)
        col = tile_idx % cols
        row = tile_idx // cols
        left = col * meta.width
        top = row * meta.height
        frames.append(img.crop((left, top, left + meta.width, top + meta.height)))
    if state.rewind and len(frames) > 2:
        frames.extend(reversed(frames[1:-1]))
    return frames


def per_frame_durations_ms(state: DmiState) -> list[int]:
    """Per-frame durations in ms. DMI delays are in deciseconds."""
    delays = state.delays if state.delays else [1.0] * state.frames
    if len(delays) < state.frames:
        delays = delays + [delays[-1]] * (state.frames - len(delays))
    delays = delays[: state.frames]
    durations = [max(20, int(round(d * 100))) for d in delays]
    if state.rewind and len(durations) > 2:
        durations.extend(reversed(durations[1:-1]))
    return durations


# ----- WebP / PNG writing -------------------------------------------------


def write_static_png(out_path: Path, frame: Image.Image) -> None:
    """Single-frame: just save a still PNG. Cheaper than spinning up ffmpeg."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    frame.save(out_path, format="PNG", optimize=True)


def write_animated_webp(
    out_path: Path, frames: list[Image.Image], durations_ms: list[int]
) -> None:
    """Encode `frames` as an animated WebP via ffmpeg.

    We dump frames as numbered PNGs in a temp dir then run a single ffmpeg
    command with the `concat` demuxer and `libwebp_anim` encoder. ffmpeg
    handles per-frame durations via the concat file.
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="dq_webp_") as tmpdir:
        tmp = Path(tmpdir)
        # Write each frame as a PNG and a concat list. The concat demuxer
        # is the only ffmpeg path that lets us specify per-frame durations.
        # Duration values are in seconds.
        concat_lines: list[str] = []
        for i, frame in enumerate(frames):
            fp = tmp / f"f{i:05d}.png"
            frame.save(fp, format="PNG")
            concat_lines.append(f"file '{fp}'")
            concat_lines.append(f"duration {durations_ms[i] / 1000.0:.4f}")
        # Concat demuxer requires the last file to be listed twice (without
        # a trailing duration) — quirk of the format.
        concat_lines.append(f"file '{tmp / f'f{len(frames) - 1:05d}.png'}'")
        concat_path = tmp / "concat.txt"
        concat_path.write_text("\n".join(concat_lines))
        # libwebp_anim with -loop 0 for infinite, -lossless 1 to preserve
        # alpha edges exactly. -compression_level 6 is the slow/best
        # setting.
        cmd = [
            "ffmpeg",
            "-y",
            "-loglevel", "error",
            "-f", "concat",
            "-safe", "0",
            "-i", str(concat_path),
            "-c:v", "libwebp_anim",
            "-lossless", "0",
            "-quality", "80",
            "-compression_level", "6",
            "-loop", "0",
            str(out_path),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(
                f"ffmpeg failed for {out_path.name}: {result.stderr}"
            )


# ----- Driver --------------------------------------------------------------


# Matches: `belly_icon = "icons/path/to/file.dmi"`
ICON_LINE_RE = re.compile(r'belly_icon\s*=\s*"([^"]+\.dmi)"', re.IGNORECASE)


def find_belly_dmis() -> set[str]:
    return set(ICON_LINE_RE.findall(ASSETS_DM.read_text()))


def safe_name(s: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "_", s)


def output_path(dmi_rel: str, state_name: str, ext: str) -> Path:
    safe_dmi = safe_name(dmi_rel.replace(".dmi", "")).replace("_dmi", "")
    safe_state = safe_name(state_name)
    return OUTPUT_DIR / f"{safe_dmi}__{safe_state}.{ext}"


def process_dmi(dmi_rel: str, only_states: list[str] | None = None) -> Iterable[Path]:
    dmi_path = REPO_ROOT / dmi_rel
    if not dmi_path.exists():
        print(f"  SKIP missing: {dmi_rel}", file=sys.stderr)
        return
    meta = parse_dmi_meta(dmi_path)
    if not meta:
        print(f"  SKIP unparseable: {dmi_rel}", file=sys.stderr)
        return
    src_mtime = dmi_path.stat().st_mtime
    for idx, state in enumerate(meta.states):
        if only_states is not None and state.name not in only_states:
            continue
        frames = extract_state_frames(dmi_path, meta, idx)
        # Static PNG for single-frame states; WebP otherwise.
        if state.frames == 1 and not state.rewind:
            out = output_path(dmi_rel, state.name, "png")
            if out.exists() and out.stat().st_mtime >= src_mtime:
                yield out
                continue
            write_static_png(out, frames[0])
            print(f"  wrote {out.relative_to(REPO_ROOT)} (still)")
            yield out
        else:
            out = output_path(dmi_rel, state.name, "webp")
            if out.exists() and out.stat().st_mtime >= src_mtime:
                yield out
                continue
            durations = per_frame_durations_ms(state)
            write_animated_webp(out, frames, durations)
            print(f"  wrote {out.relative_to(REPO_ROOT)} ({len(frames)} frames)")
            yield out


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    dmis = sorted(find_belly_dmis())
    print(f"Discovered {len(dmis)} belly DMIs in belly_assets.dm")
    total = 0
    for dmi_rel in dmis:
        print(f"[{dmi_rel}]")
        total += sum(1 for _ in process_dmi(dmi_rel))
    print(f"\nExtra states from {len(EXTRA_STATES)} DMI(s):")
    for dmi_rel, states in EXTRA_STATES:
        print(f"[{dmi_rel}] {states}")
        total += sum(1 for _ in process_dmi(dmi_rel, only_states=states))
    print(f"\nDone. {total} outputs in {OUTPUT_DIR.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
