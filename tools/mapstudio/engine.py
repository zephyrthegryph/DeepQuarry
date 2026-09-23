"""Transactional TGM map editing shared by the browser and MCP bridge."""

from __future__ import annotations

import hashlib
import copy
from collections import deque
import importlib.util
import json
import os
import re
import subprocess
import sys
import threading
import uuid
from pathlib import Path

from sprites import sprites
import rust_bridge

ROOT = Path(__file__).resolve().parents[2]
PARSER = ROOT / "tools/mapmerge2/dmm.py"
spec = importlib.util.spec_from_file_location("dq_mapmerge_dmm", PARSER)
dmm_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dmm_module)
DMM = dmm_module.DMM
Coordinate = dmm_module.Coordinate

LAYERS = {
    "area": "/area/", "turf": "/turf/", "power": "/obj/structure/cable",
    "atmos": "/obj/machinery/atmospherics/", "disposals": "/obj/structure/disposalpipe",
    "apc": "/obj/machinery/power/apc", "objects": "/obj/",
}
NETWORKS = ("power", "atmos", "disposals")
DIRS = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8,
        (1, 1): 5, (1, -1): 6, (-1, 1): 9, (-1, -1): 10}
OPPOSITE = {1: 2, 2: 1, 4: 8, 8: 4, 5: 10, 10: 5, 6: 9, 9: 6}
VALID_MAP_DIRS = (ROOT / "maps",)
PATH_RE = re.compile(r"^/[A-Za-z_][\w]*(?:/[A-Za-z_][\w]*)+$")


def base(atom):
    return atom.split("{", 1)[0].strip()


def kind(atom):
    path = base(atom)
    if path.startswith("/area/"):
        return "area"
    if path.startswith("/turf/"):
        return "turf"
    for name in ("power", "atmos", "disposals", "apc"):
        if path.startswith(LAYERS[name]):
            return name
    return "objects"


def var_edit(atom, name, default=None):
    match = re.search(rf"\b{re.escape(name)}\s*=\s*(\"[^\"]*\"|\d+)", atom)
    return match.group(1).strip('"') if match else default


def ports(atom, layer):
    path = base(atom)
    if layer == "power":
        state = var_edit(atom, "icon_state", "0-1")
        match = re.fullmatch(r"(\d+)-(\d+)", state)
        return {int(x) for x in match.groups() if int(x) in OPPOSITE} if match else set()
    direction = int(var_edit(atom, "dir", "2" if layer == "atmos" or "/junction" in path else "0"))
    if layer == "atmos" and "/binary/circulator" in path:
        return {1, 2} if direction in (1, 2) else {4, 8} if direction in (4, 8) else set()
    if layer == "atmos" and "/pipe/cap/" in path:
        return {direction} if direction in (1, 2, 4, 8) else set()
    if layer == "atmos" and "/pipe/manifold4w/" in path:
        return {1, 2, 4, 8}
    if layer == "atmos" and "/pipe/manifold/" in path:
        return {1, 2, 4, 8} - {direction}
    if layer == "atmos" and "/pipe/simple/" in path:
        return {1, 2} if direction in (1, 2) else {4, 8} if direction in (4, 8) else {d for d in (1, 2, 4, 8) if direction & d}
    if layer == "disposals" and "/junction" in path:
        clockwise = {1: 4, 4: 2, 2: 8, 8: 1}
        counterclockwise = {value: key for key, value in clockwise.items()}
        state = var_edit(atom, "icon_state", "pipe-y" if "/yjunction" in path else "pipe-j1")
        sides = {direction, OPPOSITE[direction]}
        if state == "pipe-y":
            return {direction, clockwise[direction], counterclockwise[direction]}
        return sides | {counterclockwise[direction] if state == "pipe-j2" else clockwise[direction]}
    if layer == "disposals" and "/segment" in path:
        state = var_edit(atom, "icon_state", "pipe-s")
        if state == "pipe-s":
            return {direction, OPPOSITE.get(direction, 0)} - {0}
        clockwise = {1: 4, 4: 2, 2: 8, 8: 1}
        return {direction, clockwise.get(direction, 0)} - {0}
    return set()


def power_link_targets(point, direction):
    """Neighbor ports BYOND accepts for one cable port, including diagonal bends."""
    dx, dy = next(delta for delta, value in DIRS.items() if value == direction)
    yield Coordinate(point.x + dx, point.y + dy, point.z), OPPOSITE[direction]
    if direction in (5, 6, 9, 10):
        for axis in (3, 12):
            side = direction & axis
            sx, sy = next(delta for delta, value in DIRS.items() if value == side)
            yield Coordinate(point.x + sx, point.y + sy, point.z), direction ^ axis


def route_atom(atom, layer, directions):
    if layer == "power":
        values = sorted(directions)
        state = f"0-{values[0]}" if len(values) == 1 else f"{values[0]}-{values[1]}"
        return f'{atom}{{icon_state = "{state}"}}'
    if layer == "atmos":
        if not any(part in atom for part in ("/pipe/simple/", "/pipe/manifold/", "/pipe/manifold4w/")):
            raise ValueError("Automated atmos routes require a simple pipe subtype.")
        values = set(directions)
        if len(values) >= 3:
            lane = atom.rsplit("/", 1)[-1]
            if len(values) == 4:
                return f"/obj/machinery/atmospherics/pipe/manifold4w/hidden/{lane}"
            missing = next(iter({1, 2, 4, 8} - values))
            return f"/obj/machinery/atmospherics/pipe/manifold/hidden/{lane}{{dir = {missing}}}"
        if "/pipe/simple/" not in atom:
            raise ValueError("A two-way atmos route needs a simple pipe subtype.")
        if len(values) == 1:
            values.add(OPPOSITE[next(iter(values))])
        direction = 1 if values == {1, 2} else 4 if values == {4, 8} else sum(values)
        return f"{atom}{{dir = {direction}}}"
    if layer == "disposals":
        if not atom.endswith(("/segment", "/junction", "/junction/yjunction")):
            raise ValueError("Automated disposal routes require /disposalpipe/segment.")
        values = set(directions)
        if len(values) == 3:
            missing = next(iter({1, 2, 4, 8} - values))
            return f"/obj/structure/disposalpipe/junction/yjunction{{dir = {OPPOSITE[missing]}}}"
        if len(values) > 3:
            raise ValueError("Disposals have no four-way connected fitting.")
        if not atom.endswith("/segment"):
            raise ValueError("A two-way disposal route needs a segment subtype.")
        if len(values) == 1:
            values.add(OPPOSITE[next(iter(values))])
        if values in ({1, 2}, {4, 8}):
            direction = 1 if values == {1, 2} else 4
            return f"{atom}{{dir = {direction}}}"
        clockwise = {1: 4, 4: 2, 2: 8, 8: 1}
        direction = next((d for d in values if clockwise[d] in values), None)
        if direction is None:
            raise ValueError("Unsupported disposal bend.")
        return f'{atom}{{dir = {direction}; icon_state = "pipe-c"}}'
    raise ValueError("Unknown network.")


def resolved_map(path):
    target = (ROOT / path).resolve()
    if target.suffix.lower() != ".dmm" or not target.is_file() or not any(target.is_relative_to(p) for p in VALID_MAP_DIRS):
        raise ValueError("Choose an existing .dmm file inside maps/.")
    return target


def coord(data, width, height, depth):
    x, y, z = (int(data[k]) for k in ("x", "y", "z"))
    if not (1 <= x <= width and 1 <= y <= height and 1 <= z <= depth):
        raise ValueError(f"Coordinate ({x}, {y}, {z}) is outside this map.")
    return Coordinate(x, y, z)


def rect(data, size, limit=2500):
    x1, y1, x2, y2, z = (int(data[k]) for k in ("x1", "y1", "x2", "y2", "z"))
    if x1 > x2 or y1 > y2 or x1 < 1 or y1 < 1 or x2 > size.x or y2 > size.y or not 1 <= z <= size.z:
        raise ValueError("Rectangle is outside the map or has reversed corners.")
    if (x2 - x1 + 1) * (y2 - y1 + 1) > limit:
        raise ValueError(f"Limit this region to {limit:,} tiles.")
    return x1, y1, x2, y2, z


def iter_rect(r):
    x1, y1, x2, y2, z = r
    for x in range(x1, x2 + 1):
        for y in range(y1, y2 + 1):
            yield Coordinate(x, y, z)


def validate_atom(atom, catalog):
    if not isinstance(atom, str) or not PATH_RE.fullmatch(atom):
        raise ValueError("Use an absolute DM type path without variable edits.")
    if atom not in catalog:
        raise ValueError(f"Type is not defined in this repository or map: {atom}")


def edited_atom(path, edits, catalog):
    validate_atom(path, catalog)
    if not isinstance(edits, dict) or set(edits) - {"dir", "icon_state", "color", "pixel_x", "pixel_y", "layer"}:
        raise ValueError("Unsupported appearance edit.")
    fields = []
    for name, value in edits.items():
        if name in ("dir", "pixel_x", "pixel_y", "layer"):
            try:
                number = float(value)
            except (TypeError, ValueError):
                raise ValueError(f"{name} must be numeric.") from None
            if not -128 <= number <= 128:
                raise ValueError(f"{name} is out of range.")
            fields.append(f"{name} = {int(number) if number.is_integer() else number}")
        else:
            if not isinstance(value, str) or len(value) > 100 or any(ch in value for ch in '\\"\r\n;{}'):
                raise ValueError(f"Invalid {name} value.")
            fields.append(f'{name} = "{value}"')
    return path + ("{" + "; ".join(fields) + "}" if fields else "")


class MapStudio:
    def __init__(self):
        self.lock = threading.RLock()
        self.previews = {}
        self.latest_preview = None
        self.last_commit = None
        self.read_cache = {}
        self.catalog_cache = {}

    def maps(self):
        return [str(p.relative_to(ROOT)).replace("\\", "/") for p in sorted((ROOT / "maps").rglob("*.dmm"))
                if not any(part.startswith("mapstudio-test-") for part in p.relative_to(ROOT / "maps").parts)]

    def load(self, path):
        target = resolved_map(path)
        return target, DMM.from_file(target), hashlib.sha256(target.read_bytes()).hexdigest()

    def read(self, path):
        target = resolved_map(path)
        stat = target.stat()
        stamp = (stat.st_mtime_ns, stat.st_size)
        with self.lock:
            cached = self.read_cache.get(str(target))
            if cached and cached[0] == stamp:
                return target, cached[1], cached[2]
            payload = target.read_bytes()
            parsed = DMM.from_bytes(payload)
            digest = hashlib.sha256(payload).hexdigest()
            self.read_cache[str(target)] = (stamp, parsed, digest)
            return target, parsed, digest

    def catalog(self, map_obj, query="", layer=None):
        paths = ({base(atom) for tile in map_obj.dictionary.values() for atom in tile} |
                 {path for path in sprites.defined_types if path.startswith(("/obj/", "/mob/", "/turf/", "/area/"))})
        if layer:
            if layer not in LAYERS:
                raise ValueError("Unknown layer.")
            paths = {p for p in paths if kind(p) == layer}
        if query:
            paths = {p for p in paths if query.lower() in p.lower()}
        return sorted(paths)

    def catalog_for_revision(self, map_obj, revision):
        cached = self.catalog_cache.get(revision)
        if cached is None:
            cached = frozenset(self.catalog(map_obj))
            if len(self.catalog_cache) >= 8:
                self.catalog_cache.pop(next(iter(self.catalog_cache)))
            self.catalog_cache[revision] = cached
        return cached

    def inspect(self, path, region):
        _, m, digest = self.read(path)
        r = rect(region, m.size, limit=12000)
        tiles = [self.tile(m, c) for c in iter_rect(r)]
        atoms = {a for tile in tiles for a in tile["atoms"] if kind(a) != "area"}
        return {"size": list(m.size), "revision": digest, "tiles": tiles,
                "sprite_atoms": sorted(atoms)}

    def tile(self, m, c):
        atoms = m.get_tile(c)
        return {"x": c.x, "y": c.y, "z": c.z, "atoms": list(atoms)}

    def network_component(self, path, at, atom, operations=None):
        _, m, revision = self.read(path)
        if operations:
            if not isinstance(operations, list) or len(operations) > 50:
                raise ValueError("Provide at most 50 proposed operations.")
            proposed = copy.copy(m)
            proposed.dictionary = m.dictionary.copy()
            proposed.grid = m.grid.copy()
            catalog = self.catalog_for_revision(m, revision)
            for operation in operations:
                self._operation(proposed, operation, catalog)
            m = proposed
        start = coord(at, *m.size)
        layer = kind(atom)
        if layer not in NETWORKS or atom not in m.get_tile(start):
            raise ValueError("Select a mapped network segment first.")
        def compatible(candidate):
            if kind(candidate) != layer:
                return False
            if layer == "atmos":
                return base(candidate).split("/")[-1] == base(atom).split("/")[-1]
            return True
        queue = deque([(start, atom)])
        seen = set()
        while queue:
            current, segment = queue.popleft()
            if (current, segment) in seen:
                continue
            seen.add((current, segment))
            for other in m.get_tile(current):
                if other != segment and compatible(other) and ports(other, layer) & ports(segment, layer):
                    queue.append((current, other))
            for (dx, dy), direction in DIRS.items():
                if direction not in ports(segment, layer):
                    continue
                targets = power_link_targets(current, direction) if layer == "power" else [
                    (Coordinate(current.x + dx, current.y + dy, current.z), OPPOSITE[direction])]
                for neighbor, required in targets:
                    if not (1 <= neighbor.x <= m.size.x and 1 <= neighbor.y <= m.size.y):
                        continue
                    for other in m.get_tile(neighbor):
                        if compatible(other) and required in ports(other, layer):
                            queue.append((neighbor, other))
        return {"revision": revision, "layer": layer, "members": [
            {"x": c.x, "y": c.y, "z": c.z, "atom": segment} for c, segment in sorted(seen)]}

    def check_systems(self, path, region):
        _, m, digest = self.read(path)
        r = rect(region, m.size)
        counts = {name: 0 for name in (*NETWORKS, "apc")}
        issues = []
        for c in iter_rect(r):
            atoms = m.get_tile(c)
            for atom in atoms:
                layer = kind(atom)
                if layer == "apc":
                    counts["apc"] += 1
                    if not any(kind(other) == "power" for other in atoms):
                        issues.append(f"APC ({c.x},{c.y},{c.z}) has no mapped cable on its tile.")
                if layer not in NETWORKS:
                    continue
                counts[layer] += 1
                for direction in ports(atom, layer):
                    dx, dy = next((dx, dy) for (dx, dy), value in DIRS.items() if value == direction)
                    neighbor = Coordinate(c.x + dx, c.y + dy, c.z)
                    if not (1 <= neighbor.x <= m.size.x and 1 <= neighbor.y <= m.size.y):
                        issues.append(f"{layer} at ({c.x},{c.y},{c.z}) points off-map.")
                        continue
                    adjacent = m.get_tile(neighbor)
                    targets = power_link_targets(c, direction) if layer == "power" else [(neighbor, OPPOSITE[direction])]
                    connected = any(1 <= target.x <= m.size.x and 1 <= target.y <= m.size.y and
                                    any(required in ports(other, layer) for other in m.get_tile(target)
                                        if kind(other) == layer) for target, required in targets)
                    if not connected:
                        connected = any(not ports(other, layer) for other in adjacent if kind(other) == layer)
                    if not connected and layer == "atmos":
                        connected = any(base(other).startswith("/obj/machinery/atmospherics/") and
                                        "/pipe/" not in base(other) for other in adjacent)
                    if not connected and layer == "disposals":
                        connected = any(base(other).startswith("/obj/machinery/disposal") for other in adjacent)
                    if not connected:
                        issues.append(f"{layer} at ({c.x},{c.y},{c.z}) has no reciprocal port toward {direction}.")
        issues = list(dict.fromkeys(issues))
        return {"revision": digest, "counts": counts, "issues": issues[:500], "truncated": len(issues) > 500,
                "scope": "Static mapped-port checks only; a game boot is needed to verify live power, gas, and disposal behavior."}

    def _replace(self, m, c, layer, atom):
        old = m.get_tile(c)
        if layer in ("area", "turf", "apc"):
            new = [a for a in old if kind(a) != layer]
        else:
            new = list(old)
        if atom:
            new.append(atom)
        if not any(kind(a) == "area" for a in new) or not any(kind(a) == "turf" for a in new):
            raise ValueError("A tile must retain one area and one turf.")
        m.set_tile(c, dmm_module.fix_atom_ordering(new))

    def _operation(self, m, op, catalog):
        action = op.get("action")
        if action == "room":
            region = rect(op["rect"], m.size)
            x1, y1, x2, y2, _z = region
            if x2 - x1 < 2 or y2 - y1 < 2:
                raise ValueError("A room needs at least a 3 by 3 tile footprint.")
            floor, wall, area = op["floor"], op["wall"], op["area"]
            for atom, layer in ((floor, "turf"), (wall, "turf"), (area, "area")):
                validate_atom(atom, catalog)
                if kind(atom) != layer:
                    raise ValueError(f"Room {layer} type is invalid.")
            points = list(iter_rect(region))
            for c in points:
                boundary = c.x in (x1, x2) or c.y in (y1, y2)
                self._replace(m, c, "turf", wall if boundary else floor)
                self._replace(m, c, "area", area)
            return points
        if action == "fill":
            start = coord(op["at"], *m.size)
            layer, atom = op["layer"], op["atom"]
            if layer not in LAYERS:
                raise ValueError("Unknown layer.")
            validate_atom(atom, catalog)
            if kind(atom) != layer:
                raise ValueError("Fill type does not match its layer.")
            signature = lambda c: tuple(a for a in m.get_tile(c) if kind(a) == layer)
            target = signature(start)
            if target == (atom,):
                return []
            queue, seen, points = deque([start]), {start}, []
            while queue:
                c = queue.popleft()
                if signature(c) != target:
                    continue
                points.append(c)
                if len(points) > 2500:
                    raise ValueError("Fill exceeds 2,500 tiles; choose a smaller region.")
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    neighbor = Coordinate(c.x + dx, c.y + dy, c.z)
                    if neighbor not in seen and 1 <= neighbor.x <= m.size.x and 1 <= neighbor.y <= m.size.y:
                        seen.add(neighbor)
                        queue.append(neighbor)
            for c in points:
                self._replace(m, c, layer, atom)
            return points
        if action in ("network_split", "network_join", "network_cross"):
            c = coord(op["at"], *m.size)
            layer = op.get("layer")
            if layer not in NETWORKS:
                raise ValueError("Choose a power, atmos, or disposal network.")
            current = list(m.get_tile(c))
            existing = [a for a in current if kind(a) == layer]
            if action == "network_split":
                target = op.get("atom")
                if target not in existing:
                    raise ValueError("Select a network segment to split.")
                current.remove(target)
                m.set_tile(c, dmm_module.fix_atom_ordering(current))
                return [c]
            atom = op.get("atom")
            validate_atom(atom, catalog)
            if kind(atom) != layer:
                raise ValueError("The chosen type does not belong to this network.")
            if action == "network_cross":
                if layer == "disposals":
                    raise ValueError("Disposals have no simple crossing fitting; select a mapped junction instead.")
                if len(existing) != 1:
                    raise ValueError("A crossing needs exactly one existing straight segment.")
                axis = ports(existing[0], layer)
                if axis not in ({1, 2}, {4, 8}):
                    raise ValueError("A crossing needs a straight cardinal segment.")
                if layer == "atmos" and base(existing[0]) == atom:
                    raise ValueError("Use different pipe lanes for an unconnected crossing.")
                crossing = route_atom(atom, layer, {4, 8} if axis == {1, 2} else {1, 2})
                current.append(crossing)
                m.set_tile(c, dmm_module.fix_atom_ordering(current))
                return [c]
            if existing:
                raise ValueError("This tile already has a segment; select it or use Cross.")
            directions = set()
            for (dx, dy), direction in DIRS.items():
                if layer != "power" and dx and dy:
                    continue
                neighbor = Coordinate(c.x + dx, c.y + dy, c.z)
                if not (1 <= neighbor.x <= m.size.x and 1 <= neighbor.y <= m.size.y):
                    continue
                for other in m.get_tile(neighbor):
                    if kind(other) != layer or OPPOSITE[direction] not in ports(other, layer):
                        continue
                    if layer == "atmos" and base(other).split("/")[-1] != atom.split("/")[-1]:
                        continue
                    directions.add(direction)
            if len(directions) < 2:
                raise ValueError("Join needs at least two matching neighboring endpoints.")
            if layer == "power" and len(directions) > 2:
                current.extend(route_atom(atom, layer, {direction}) for direction in sorted(directions))
            else:
                current.append(route_atom(atom, layer, directions))
            m.set_tile(c, dmm_module.fix_atom_ordering(current))
            return [c]
        if action == "paste_atom":
            c = coord(op["at"], *m.size)
            atom = op["atom"]
            validate_atom(base(atom), catalog)
            if kind(atom) in ("area", "turf"):
                self._replace(m, c, kind(atom), atom)
            else:
                old = list(m.get_tile(c))
                old.append(atom)
                m.set_tile(c, dmm_module.fix_atom_ordering(old))
            return [c]
        if action in ("remove_atom", "edit_atom"):
            c = coord(op["at"], *m.size)
            old = m.get_tile(c)
            target = op["atom"]
            if target not in old:
                raise ValueError("The selected atom is no longer on this tile.")
            if kind(target) in ("area", "turf") and action == "remove_atom":
                raise ValueError("Paint a replacement area or turf instead of removing it.")
            replacement = None
            if action == "edit_atom":
                path = op.get("path", base(target))
                validate_atom(path, catalog)
                if kind(path) != kind(target):
                    raise ValueError("Editing must keep the atom on the same layer.")
                replacement = edited_atom(path, op.get("vars", {}), catalog)
            new = list(old)
            new.remove(target)
            if replacement:
                new.append(replacement)
            m.set_tile(c, dmm_module.fix_atom_ordering(new))
            return [c]
        if action == "place_atom":
            layer = op.get("layer")
            if layer not in LAYERS:
                raise ValueError("Unknown layer.")
            atom = edited_atom(op["atom"], op.get("vars", {}), catalog)
            if kind(atom) != layer:
                raise ValueError("Placement type does not match the active layer.")
            if "points" in op:
                if not isinstance(op["points"], list) or not 1 <= len(op["points"]) <= 2500:
                    raise ValueError("Select 1 to 2,500 tiles.")
                points = list(dict.fromkeys(coord(p, *m.size) for p in op["points"]))
            else:
                points = [coord(op["at"], *m.size)]
            for c in points:
                self._replace(m, c, layer, atom)
            return points
        if action in ("paint", "place", "erase"):
            layer = op.get("layer")
            if layer not in LAYERS:
                raise ValueError("Unknown layer.")
            if "points" in op:
                if not isinstance(op["points"], list) or not 1 <= len(op["points"]) <= 2500:
                    raise ValueError("Select 1 to 2,500 tiles.")
                points = list(dict.fromkeys(coord(p, *m.size) for p in op["points"]))
            else:
                points = list(iter_rect(rect(op["rect"], m.size))) if "rect" in op else [coord(op["at"], *m.size)]
            if action != "erase":
                atom = op["atom"]
                validate_atom(atom, catalog)
                if kind(atom) != layer:
                    raise ValueError(f"{atom} does not belong to the {layer} layer.")
            elif layer in ("area", "turf"):
                raise ValueError("Paint a replacement area or turf instead of erasing it.")
            for c in points:
                self._replace(m, c, layer, None if action == "erase" else atom)
            return points
        if action in ("copy", "move"):
            source = rect(op["source"], m.size)
            dx, dy = int(op["dx"]), int(op["dy"])
            if dx == 0 and dy == 0:
                raise ValueError("Choose a different destination.")
            src = list(iter_rect(source))
            dst = [Coordinate(c.x + dx, c.y + dy, c.z) for c in src]
            for c in dst:
                coord(c._asdict(), *m.size)
            source_set, dest_set = set(src), set(dst)
            if source_set & dest_set:
                raise ValueError("Source and destination must not overlap.")
            if not op.get("replace", False):
                for c in dst:
                    atoms = m.get_tile(c)
                    if any(kind(a) in ("objects", "power", "atmos", "disposals", "apc") for a in atoms):
                        raise ValueError(f"Destination contains fixtures at ({c.x}, {c.y}); set replace=true after reviewing.")
            contents = {s: m.get_tile(s) for s in src}
            destination = {d: m.get_tile(d) for d in dst}
            for s, d in zip(src, dst):
                m.set_tile(d, contents[s])
            if action == "move":
                for s in src:
                    floor = next(a for a in destination[dst[src.index(s)]] if kind(a) == "turf")
                    area = next(a for a in destination[dst[src.index(s)]] if kind(a) == "area")
                    m.set_tile(s, (floor, area))
            return src + dst
        if action == "route":
            layer, atom = op["layer"], op["atom"]
            if layer not in NETWORKS or kind(atom) != layer:
                raise ValueError("Route atom does not match the network layer.")
            validate_atom(atom, catalog)
            points = [coord(p, *m.size) for p in op["points"]]
            if not 2 <= len(points) <= 500:
                raise ValueError("A route needs 2 to 500 points.")
            nearby = set(points)
            for point in points:
                for dx, dy in DIRS:
                    if 1 <= point.x + dx <= m.size.x and 1 <= point.y + dy <= m.size.y:
                        nearby.add(Coordinate(point.x + dx, point.y + dy, point.z))
            tiles = [{"x": p.x, "y": p.y, "z": p.z, "atoms": list(m.get_tile(p))}
                     for p in sorted(nearby)]
            payload = {key: value for key, value in op.items() if key != "action"}
            payload["tiles"] = tiles
            diff = rust_bridge.call("route", payload)
            changed = []
            for tile in diff:
                p = Coordinate(tile["x"], tile["y"], tile["z"])
                m.set_tile(p, tuple(tile["after"]))
                changed.append(p)
            return changed
        raise ValueError("Unknown action. Use paint, place, erase, copy, move, or route.")

    def preview(self, path, operations):
        if not isinstance(operations, list) or not 1 <= len(operations) <= 50:
            raise ValueError("Provide 1 to 50 operations.")
        with self.lock:
            target, base_map, digest = self.read(path)
            m = copy.copy(base_map)
            m.dictionary = base_map.dictionary.copy()
            m.grid = base_map.grid.copy()
            catalog = self.catalog_for_revision(base_map, digest)
            changed = set()
            before = {}
            for op in operations:
                points = self._operation(m, op, catalog)
                for c in points:
                    if c not in before:
                        before[c] = list(base_map.get_tile(c))
                    changed.add(c)
            diff = [{"x": c.x, "y": c.y, "z": c.z, "before": before[c], "after": list(m.get_tile(c))}
                    for c in sorted(changed) if before[c] != list(m.get_tile(c))]
            if not diff:
                raise ValueError("These operations make no change.")
            token = uuid.uuid4().hex
            self.previews[token] = {"path": str(target), "revision": digest, "operations": operations, "diff": diff}
            result = {"preview_id": token, "map": str(target.relative_to(ROOT)).replace("\\", "/"),
                      "revision": digest, "changed_tiles": len(diff), "diff": diff, "operations": operations,
                      "warnings": self._warnings(base_map, m, changed),
                      "sprites": {a: url for d in diff for a in d["after"] if (url := sprites.url(a))}}
            if any(op.get("action") == "route" for op in operations):
                result["warnings"].append("Route directions were generated from adjacent segments. Verify equipment, supply/scrubber lanes, and terminal connections in a game boot.")
            self.latest_preview = result
            return result

    def draft(self, path, operations):
        if not isinstance(operations, list) or not 1 <= len(operations) <= 50:
            raise ValueError("Provide 1 to 50 operations.")
        with self.lock:
            _, base_map, revision = self.read(path)
            m = copy.copy(base_map)
            m.dictionary = base_map.dictionary.copy()
            m.grid = base_map.grid.copy()
            catalog = self.catalog_for_revision(base_map, revision)
            for op in operations[:-1]:
                self._operation(m, op, catalog)
            old_grid = m.grid.copy()
            old_dictionary = m.dictionary.copy()
            changed = self._operation(m, operations[-1], catalog)
            diff = [{"x": c.x, "y": c.y, "z": c.z,
                     "before": list(old_dictionary[old_grid[c]]), "after": list(m.get_tile(c))}
                    for c in sorted(set(changed)) if old_dictionary[old_grid[c]] != m.get_tile(c)]
            return {"revision": revision, "diff": diff,
                    "sprites": {a: url for d in diff for a in d["after"] if (url := sprites.url(a))}}

    def activity(self):
        with self.lock:
            return self.latest_preview or {"preview_id": None}

    def dismiss(self, preview_id):
        with self.lock:
            removed = self.previews.pop(preview_id, None)
            if self.latest_preview and self.latest_preview["preview_id"] == preview_id:
                self.latest_preview = None
            return {"dismissed": bool(removed)}

    def _warnings(self, old, m, changed):
        warnings = []
        for c in changed:
            atoms = m.get_tile(c)
            for layer in NETWORKS:
                if not any(kind(a) == layer for a in atoms):
                    continue
                neighbors = [Coordinate(c.x + dx, c.y + dy, c.z) for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))]
                linked = any(1 <= n.x <= m.size.x and 1 <= n.y <= m.size.y and
                             any(kind(a) == layer for a in m.get_tile(n)) for n in neighbors)
                if not linked:
                    warnings.append(f"Isolated {layer} at ({c.x}, {c.y}, {c.z}); inspect connections.")
            for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
                n = Coordinate(c.x + dx, c.y + dy, c.z)
                if not (1 <= n.x <= m.size.x and 1 <= n.y <= m.size.y):
                    continue
                for layer in NETWORKS:
                    formerly_linked = all(any(kind(a) == layer for a in old.get_tile(p)) for p in (c, n))
                    now_linked = all(any(kind(a) == layer for a in m.get_tile(p)) for p in (c, n))
                    if formerly_linked and not now_linked:
                        warnings.append(f"{layer} connection broken between ({c.x}, {c.y}) and ({n.x}, {n.y}).")
            if any(kind(a) == "apc" for a in atoms) and not any(kind(a) == "power" for a in atoms):
                warnings.append(f"APC at ({c.x}, {c.y}, {c.z}) has no cable on its tile.")
        return sorted(set(warnings))[:100]

    def commit(self, preview_id):
        with self.lock:
            item = self.previews.get(preview_id)
            if not item:
                raise ValueError("Preview expired or does not exist.")
            target, m, digest = self.load(item["path"])
            if digest != item["revision"]:
                raise ValueError("Map changed since preview. Preview the edit again.")
            catalog = set(self.catalog(m))
            for op in item["operations"]:
                self._operation(m, op, catalog)
            # Parse the serialized candidate before replacing the source file.
            payload = m.to_bytes(tgm=True)
            DMM.from_bytes(payload)
            temp = target.with_suffix(target.suffix + ".mapstudio.tmp")
            temp.write_bytes(payload)
            mapcore = ROOT / "tools/mapcore/target/debug/mapcore.exe"
            command = ([str(mapcore)] if mapcore.is_file() else
                       ["cargo", "run", "--quiet", "--manifest-path", str(ROOT / "tools/mapcore/Cargo.toml"), "--"])
            try:
                checked = subprocess.run([*command, "inspect", str(temp)], cwd=ROOT, capture_output=True,
                                         text=True, timeout=120, check=True)
                dimensions = json.loads(checked.stdout)["size"]
                if dimensions != list(m.size):
                    raise ValueError("Rust map validation returned different map dimensions.")
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError) as exc:
                temp.unlink(missing_ok=True)
                raise ValueError(f"Rust map validation failed: {exc}") from exc
            environment = os.environ.copy()
            environment["PYTHONPATH"] = str(ROOT / "tools") + os.pathsep + environment.get("PYTHONPATH", "")
            lint = subprocess.run([sys.executable, "-m", "tools.maplint.source", str(temp)], cwd=ROOT,
                                  env=environment, capture_output=True, text=True, timeout=120)
            if lint.returncode:
                temp.unlink(missing_ok=True)
                raise ValueError("Map lint rejected the edit: " + (lint.stdout + lint.stderr)[-4000:])
            backup = target.with_suffix(target.suffix + ".mapstudio.bak")
            backup.write_bytes(target.read_bytes())
            temp.replace(target)
            self.read_cache.pop(str(target), None)
            del self.previews[preview_id]
            self.latest_preview = None
            self.last_commit = {"path": str(target), "revision": hashlib.sha256(payload).hexdigest(), "backup": str(backup)}
            return {"saved": str(target.relative_to(ROOT)).replace("\\", "/"),
                    "backup": str(backup.relative_to(ROOT)).replace("\\", "/"),
                    "changed_tiles": len(item["diff"])}

    def undo(self):
        with self.lock:
            item = self.last_commit
            if not item:
                raise ValueError("No Map Studio save to undo in this session.")
            target = Path(item["path"])
            if hashlib.sha256(target.read_bytes()).hexdigest() != item["revision"]:
                raise ValueError("Map changed since the save. Undo is unsafe.")
            backup = Path(item["backup"])
            target.write_bytes(backup.read_bytes())
            self.read_cache.pop(str(target), None)
            self.last_commit = None
            return {"restored": str(target.relative_to(ROOT)).replace("\\", "/")}


studio = MapStudio()
