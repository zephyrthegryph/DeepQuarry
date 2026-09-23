"""Resolve mapped DM types to PNG frames from the repository's editable DMI sources."""

from __future__ import annotations

import io
import hashlib
import re
import threading
import tomllib
from functools import lru_cache
from pathlib import Path
from urllib.parse import quote

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
TYPE_LINE = re.compile(r"^(/[A-Za-z_][\w/]*)(?:\s*//.*)?$")
ICON_LINE = re.compile(r"^\ticon\s*=\s*'([^']+\.dmi)'(?:\s*//.*)?$")
STATE_LINE = re.compile(r'^\ticon_state\s*=\s*"([^"]*)"(?:\s*//.*)?$')
DIR_LINE = re.compile(r"^\tdir\s*=\s*(\d+|NORTH|SOUTH|EAST|WEST)(?:\s*//.*)?$")
EDIT_LINE = re.compile(r"\b(icon_state|dir|color|pixel_x|pixel_y|layer|plane|alpha)\s*=\s*(\"[^\"]*\"|-?\d+(?:\.\d+)?|[A-Z][A-Z_0-9]*)")
APPEARANCE_LINE = re.compile(r'^\t(color|pixel_x|pixel_y|layer|plane|alpha)\s*=\s*("[^"]*"|-?\d+(?:\.\d+)?|[A-Z][A-Z_0-9]*)(?:\s*//.*)?$')
DIRECTIONS = {"SOUTH": 2, "NORTH": 1, "EAST": 4, "WEST": 8}
DIR_ORDER = {1: (2, 1, 4, 8), 4: (2, 1, 4, 8), 8: (2, 1, 4, 8, 6, 10, 5, 9)}


def atom_parts(atom):
    path, _, edits = atom.partition("{")
    overrides = {}
    for name, value in EDIT_LINE.findall(edits):
        overrides[name] = value.strip('"')
    return path.strip(), overrides


class SpriteIndex:
    def __init__(self):
        self.types = {}
        self.defined_types = set()
        self.sheets = {}
        self.atlases = {}
        self.atlas_lock = threading.RLock()
        self.constants = dict(re.findall(r'^#define\s+([A-Z][A-Z_0-9]*)\s+"(#[0-9a-fA-F]{6})"', (ROOT / 'code/__defines/color.dm').read_text(encoding='utf-8'), re.MULTILINE))
        self._scan_types()

    def _scan_types(self):
        manifest = (ROOT / "deepquarry.dme").read_text(encoding="utf-8", errors="replace")
        includes = re.findall(r'^#include\s+"([^"]+\.dm)"', manifest, re.MULTILINE)
        for include in includes:
            source = ROOT / include.replace("\\", "/")
            if not source.is_file():
                continue
            current = None
            for line in source.read_text(encoding="utf-8", errors="replace").splitlines():
                if not line.startswith((" ", "\t")):
                    match = TYPE_LINE.match(line)
                    current = match.group(1) if match else None
                    if current:
                        self.defined_types.add(current)
                    continue
                if not current:
                    continue
                icon = ICON_LINE.match(line)
                state = STATE_LINE.match(line)
                direction = DIR_LINE.match(line)
                appearance = APPEARANCE_LINE.match(line)
                if icon:
                    self.types.setdefault(current, {})["icon"] = icon.group(1)
                elif state:
                    self.types.setdefault(current, {})["icon_state"] = state.group(1)
                elif direction:
                    self.types.setdefault(current, {})["dir"] = direction.group(1)
                elif appearance:
                    self.types.setdefault(current, {})[appearance.group(1)] = appearance.group(2).strip('"')

    @lru_cache(maxsize=100_000)
    def appearance(self, atom):
        path, overrides = atom_parts(atom)
        values = {}
        parts = path.split('/')
        for i in range(2, len(parts) + 1):
            values.update(self.types.get('/'.join(parts[:i]), {}))
        values.update(overrides)
        color = self.constants.get(values.get('color'), values.get('color', '#ffffff'))
        if not re.fullmatch(r'#[0-9a-fA-F]{6}', color):
            color = '#ffffff'
        def numeric(name, default=0):
            try:
                return float(values.get(name, default))
            except (TypeError, ValueError):
                return default
        return {'color': color, 'pixel_x': numeric('pixel_x'), 'pixel_y': numeric('pixel_y'),
                'layer': numeric('layer'), 'alpha': max(0, min(255, numeric('alpha', 255))),
                'dir': DIRECTIONS.get(values.get('dir'), values.get('dir', '')),
                'icon_state': values.get('icon_state', '')}

    @lru_cache(maxsize=100_000)
    def resolve(self, atom):
        path, overrides = atom_parts(atom)
        values = {}
        parts = path.split("/")
        for i in range(2, len(parts) + 1):
            values.update(self.types.get("/".join(parts[:i]), {}))
        values.update(overrides)
        icon = values.get("icon")
        if not icon:
            return None
        source = (ROOT / icon.removesuffix(".dmi")).with_suffix(".png")
        metadata = source.with_suffix(".dmi.toml")
        if not source.is_file() or not metadata.is_file() or not source.is_relative_to(ROOT / "icons"):
            return None
        state = values.get("icon_state", "")
        direction = values.get("dir", "SOUTH")
        return icon, state, DIRECTIONS.get(direction, int(direction) if direction.isdigit() else 2)

    def url(self, atom):
        if not self.resolve(atom):
            return None
        return "/sprite?atom=" + quote(atom, safe="")

    @lru_cache(maxsize=256)
    def _sheet(self, icon):
        source = (ROOT / icon.removesuffix(".dmi")).with_suffix(".png")
        metadata = tomllib.loads(source.with_suffix(".dmi.toml").read_text(encoding="utf-8"))
        offsets = {}
        position = 0
        for state in metadata["state"]:
            offsets.setdefault(state["name"], (position, state["dirs"]))
            position += state["dirs"] * state["frames"]
        return Image.open(source).convert("RGBA"), metadata, offsets

    @lru_cache(maxsize=20_000)
    def png(self, atom):
        frame = self.frame(atom)
        if frame is None:
            return None
        output = io.BytesIO()
        frame.save(output, format="PNG")
        return output.getvalue()

    @lru_cache(maxsize=20_000)
    def frame(self, atom):
        resolved = self.resolve(atom)
        if not resolved:
            return None
        icon, state, direction = resolved
        sheet, metadata, offsets = self._sheet(icon)
        if state not in offsets:
            if "" not in offsets:
                return None
            state = ""
        index, dirs = offsets[state]
        if dirs > 1:
            order = DIR_ORDER.get(dirs, DIR_ORDER[4])
            index += order.index(direction) if direction in order[:dirs] else 0
        width, height, cols = (metadata[k] for k in ("width", "height", "cols"))
        x, y = (index % cols) * width, (index // cols) * height
        frame = sheet.crop((x, y, x + width, y + height))
        appearance = self.appearance(atom)
        color = appearance['color']
        if color != '#ffffff':
            tint = tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))
            rgb = ImageChops.multiply(frame.convert('RGB'), Image.new('RGB', frame.size, tint))
            frame = Image.merge('RGBA', (*rgb.split(), frame.getchannel('A')))
        return frame

    def atlas(self, atoms):
        selected = tuple(sorted(a for a in atoms if self.resolve(a)))
        key = hashlib.sha256("\n".join(selected).encode()).hexdigest()[:24]
        with self.atlas_lock:
            cached = self.atlases.get(key)
            if cached:
                return {"url": f"/atlas?id={key}", "frames": cached[1], "appearance": {a: self.appearance(a) for a in selected}}
            positions = {}
            frames = []
            padding = 8  # Keep mip levels from sampling the neighboring sprite.
            x = y = padding
            row_height = 0
            for atom in selected:
                frame = self.frame(atom)
                if frame is None:
                    continue
                if x + frame.width + padding > 2048 and x > padding:
                    x, y, row_height = padding, y + row_height + padding, 0
                positions[atom] = [x, y, frame.width, frame.height]
                frames.append((frame, x, y))
                x += frame.width + padding
                row_height = max(row_height, frame.height)
            image = Image.new("RGBA", (2048, max(1, y + row_height + padding)))
            for frame, px, py in frames:
                image.paste(frame, (px, py))
            output = io.BytesIO()
            image.save(output, format="PNG")
            if len(self.atlases) >= 128:
                self.atlases.pop(next(iter(self.atlases)))
            self.atlases[key] = (output.getvalue(), positions)
            return {"url": f"/atlas?id={key}", "frames": positions, "appearance": {a: self.appearance(a) for a in selected}}

    def atlas_bytes(self, key):
        with self.atlas_lock:
            record = self.atlases.get(key)
            return record[0] if record else None


sprites = SpriteIndex()
