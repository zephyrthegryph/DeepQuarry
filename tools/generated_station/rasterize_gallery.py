#!/usr/bin/env python3
"""Rasterize generated-station diagnostic HTML into readable tile maps."""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


CELL = 10
MARGIN = 24
HEADER = 104
LEGEND = 84
BACKGROUND = "#10141b"
GRID = "#27303b"

COLORS = {
    " ": "#080b10",
    "~": "#080b10",
    "#": "#6f7b88",
    "+": "#d3a43c",
    ".": "#273746",
    "@": "#55d6e8",
    "!": "#ff3b4f",
    "C": "#436fa8",
    "I": "#7857a6",
    "S": "#9d414a",
    "E": "#b36b32",
    "L": "#9d844c",
    "D": "#3d8587",
    "A": "#ffe066",
    "M": "#eaf2ff",
    "t": "#9a7048",
    "s": "#8a9cab",
    "c": "#73bd75",
}


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    windows_fonts = Path("C:/Windows/Fonts")
    family = windows_fonts / ("arialbd.ttf" if bold else "arial.ttf")
    if not family.exists():
        family = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    return ImageFont.truetype(family, size)


def parse_report(path: Path) -> tuple[str, str, list[str]]:
    source = path.read_text(encoding="utf-8")
    title_match = re.search(r"<h2>(.*?)</h2>", source, re.S)
    summary_match = re.search(r"<div id='layer-summary'[^>]*>(.*?)</div>", source, re.S)
    raster_match = re.search(r"<h3>Composite gameplay layer</h3><pre[^>]*>(.*?)</pre>", source, re.S)
    if not raster_match:
        raise ValueError(f"{path} has no composite gameplay layer")
    title = html.unescape(title_match.group(1)) if title_match else path.stem
    summary = re.sub(r"<[^>]+>", "", summary_match.group(1)) if summary_match else ""
    rows = html.unescape(raster_match.group(1)).strip("\n").splitlines()
    width = max(map(len, rows))
    return title, html.unescape(summary), [row.ljust(width) for row in rows]


def tile_color(character: str) -> str:
    return COLORS.get(character, "#52606d")


def render_report(path: Path, destination: Path) -> Path:
    title, summary, rows = parse_report(path)
    columns = len(rows[0])
    width = MARGIN * 2 + columns * CELL
    height = HEADER + len(rows) * CELL + LEGEND + MARGIN
    image = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(image)
    draw.text((MARGIN, 18), title, font=font(25, True), fill="#f4f7fb")
    draw.text((MARGIN, 54), summary, font=font(12), fill="#b9c4d0")

    map_x = MARGIN
    map_y = HEADER
    for y, row in enumerate(rows):
        for x, character in enumerate(row):
            left = map_x + x * CELL
            top = map_y + y * CELL
            draw.rectangle((left, top, left + CELL - 1, top + CELL - 1), fill=tile_color(character))
            if character not in {" ", "~", ".", "#", "+"}:
                text_fill = "#10141b" if character in {"@", "A", "M", "!"} else "#f7fbff"
                draw.text((left + 2, top - 1), character, font=font(8, True), fill=text_fill)

    # Major 8-tile guides retain the exact tile grid without overwhelming it.
    for x in range(0, columns + 1, 8):
        px = map_x + x * CELL
        draw.line((px, map_y, px, map_y + len(rows) * CELL), fill=GRID)
    for y in range(0, len(rows) + 1, 8):
        py = map_y + y * CELL
        draw.line((map_x, py, map_x + columns * CELL, py), fill=GRID)

    legend_y = map_y + len(rows) * CELL + 22
    legend = [
        ("#", "wall/hull"), ("+", "main hall"), (".", "maintenance"), ("@", "door"),
        ("C", "command"), ("I", "AI"), ("S", "security"), ("E", "engineering"),
        ("L", "logistics"), ("D", "docking"), ("M", "machine"), ("A", "APC"),
        ("t", "table"), ("s", "storage"), ("c", "chair"),
    ]
    cursor_x = MARGIN
    for character, label in legend:
        swatch = 12
        label_width = draw.textlength(label, font=font(11))
        item_width = swatch + 6 + label_width + 18
        if cursor_x + item_width > width - MARGIN:
            cursor_x = MARGIN
            legend_y += 24
        draw.rectangle((cursor_x, legend_y, cursor_x + swatch, legend_y + swatch), fill=tile_color(character))
        draw.text((cursor_x + swatch + 6, legend_y - 1), label, font=font(11), fill="#d5dde6")
        cursor_x += item_width

    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, optimize=True)
    return destination


def contact_sheet(images: list[Path], destination: Path) -> Path:
    opened = [Image.open(path).convert("RGB") for path in images]
    target_width = 720
    thumbs = []
    for image in opened:
        ratio = target_width / image.width
        thumbs.append(image.resize((target_width, round(image.height * ratio)), Image.Resampling.LANCZOS))
    gap = 24
    sheet_width = target_width * 2 + gap * 3
    row_heights = [max(thumbs[i].height for i in range(0, min(2, len(thumbs))))]
    if len(thumbs) > 2:
        row_heights.append(max(thumbs[i].height for i in range(2, len(thumbs))))
    sheet_height = sum(row_heights) + gap * (len(row_heights) + 1)
    sheet = Image.new("RGB", (sheet_width, sheet_height), BACKGROUND)
    y = gap
    for index, thumb in enumerate(thumbs):
        row = index // 2
        if row and index % 2 == 0:
            y = gap * (row + 1) + sum(row_heights[:row])
        x = gap + (index % 2) * (target_width + gap)
        sheet.paste(thumb, (x, y))
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, optimize=True)
    return destination


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    reports = sorted(args.source.glob("generated-station-content-[0-9]*.html"))
    if not reports:
        raise SystemExit(f"No generated station reports in {args.source}")
    images = [render_report(report, args.destination / f"{report.stem}.png") for report in reports]
    contact_sheet(images, args.destination / "generated-station-examples.png")
    print("\n".join(str(path.resolve()) for path in [*images, args.destination / "generated-station-examples.png"]))


if __name__ == "__main__":
    main()
