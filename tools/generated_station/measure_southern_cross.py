#!/usr/bin/env python3
"""Measure furnishing envelopes from the live Southern Cross DMMs.

Rooms are connected floor components sharing one mapped /area path.  The
result deliberately separates functional floor fixtures from wall services,
underfloor infrastructure, and cosmetic decals so an APC cannot make an empty
office appear furnished.
"""

from __future__ import annotations

import json
import statistics
import sys
from collections import Counter, defaultdict, deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1] / "mapmerge2"))
from dmm import Coordinate, DMM  # noqa: E402


MAPS = [Path(f"maps/southern_cross/southern_cross-{z}.dmm") for z in (1, 7, 6)]
IGNORED_OBJECT_PREFIXES = (
    "/obj/effect/",
    "/obj/machinery/light",
    "/obj/machinery/alarm",
    "/obj/machinery/power/apc",
    "/obj/machinery/atmospherics/",
    "/obj/structure/cable",
    "/obj/structure/disposalpipe",
    "/obj/structure/window",
    "/obj/machinery/door",
)


def base(atom: str) -> str:
    return atom.split("{", 1)[0].strip()


def fixture_family(atom: str) -> str:
    """Collapse implementation subtypes to a generator-comparable category."""
    parts = atom.split("/")
    return "/".join(parts[:4]) if len(parts) > 4 else atom


def percentile(values: list[int], fraction: float) -> int:
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * fraction)]


def role_for(area: str) -> str:
    text = area.lower().replace("_", "-")
    aliases = {
        "surgery": ("surgery", "operating"),
        "treatment": ("treatment", "exam", "emergency"),
        "ward": ("ward", "recovery", "patient"),
        "pharmacy": ("pharmacy", "chemistry"),
        "laboratory": ("laboratory", "lab", "research"),
        "robotics": ("robotic",),
        "armory": ("armory", "armoury"),
        "brig": ("brig", "cell"),
        "security": ("security", "checkpoint"),
        "operations": ("bridge", "operations", "command"),
        "communications": ("telecom", "communication"),
        "office": ("office",),
        "storage": ("storage", "store", "warehouse"),
        "workshop": ("workshop", "engineering"),
        "atmospherics": ("atmos",),
        "power": ("engine", "power", "generator"),
        "cargo": ("cargo", "quartermaster", "supply"),
        "docking": ("hangar", "dock", "shuttle"),
        "reception": ("lobby", "reception", "foyer", "waiting"),
        "ai": ("ai",),
    }
    for role, needles in aliases.items():
        if any(needle in text for needle in needles):
            return role
    return "general"


def largest_empty_region(points: set[tuple[int, int, int]], occupied: set[tuple[int, int, int]]) -> int:
    remaining = points - occupied
    largest = 0
    while remaining:
        start = remaining.pop()
        queue = deque([start])
        size = 1
        while queue:
            x, y, z = queue.popleft()
            for neighbor in ((x - 1, y, z), (x + 1, y, z), (x, y - 1, z), (x, y + 1, z)):
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    queue.append(neighbor)
                    size += 1
        largest = max(largest, size)
    return largest


def main() -> None:
    rooms = []
    for map_path in MAPS:
        dmm = DMM.from_file(map_path)
        by_area: dict[str, set[tuple[int, int, int]]] = defaultdict(set)
        atoms_by_point = {}
        for coord in dmm.grid:
            atoms = tuple(base(atom) for atom in dmm.get_tile(coord))
            area = next((atom for atom in atoms if atom.startswith("/area/") and atom != "/area/space"), None)
            turf = next((atom for atom in atoms if atom.startswith("/turf/")), "")
            if not area or turf.startswith("/turf/space") or "/wall" in turf:
                continue
            point = (coord[0], coord[1], coord[2])
            by_area[area].add(point)
            atoms_by_point[point] = atoms
        for area, area_points in by_area.items():
            remaining = set(area_points)
            while remaining:
                start = remaining.pop()
                component = {start}
                queue = deque([start])
                while queue:
                    x, y, z = queue.popleft()
                    for neighbor in ((x - 1, y, z), (x + 1, y, z), (x, y - 1, z), (x, y + 1, z)):
                        if neighbor in remaining:
                            remaining.remove(neighbor)
                            component.add(neighbor)
                            queue.append(neighbor)
                if len(component) < 6:
                    continue
                occupied = set()
                fixture_types = Counter()
                for point in component:
                    for atom in atoms_by_point[point]:
                        if not atom.startswith("/obj/") or atom.startswith(IGNORED_OBJECT_PREFIXES):
                            continue
                        occupied.add(point)
                        fixture_types[fixture_family(atom)] += 1
                occupancy = len(occupied) / len(component)
                empty = largest_empty_region(component, occupied) / len(component)
                rooms.append({
                    "area": area,
                    "role": role_for(area),
                    "tiles": len(component),
                    "occupied_tiles": len(occupied),
                    "occupancy_micros": round(occupancy * 1_000_000),
                    "largest_empty_region_micros": round(empty * 1_000_000),
                    "unique_fixture_types": len(fixture_types),
                    "fixture_count": sum(fixture_types.values()),
                })
    profiles = {}
    grouped = defaultdict(list)
    for room in rooms:
        grouped[room["role"]].append(room)
    for role, samples in sorted(grouped.items()):
        if len(samples) < 2:
            continue
        occupancies = [sample["occupancy_micros"] for sample in samples]
        empty_regions = [sample["largest_empty_region_micros"] for sample in samples]
        unique = [sample["unique_fixture_types"] for sample in samples]
        fixture_counts = [sample["fixture_count"] for sample in samples]
        profiles[role] = {
            "samples": len(samples),
            "occupancy_p25_micros": percentile(occupancies, 0.25),
            "occupancy_median_micros": round(statistics.median(occupancies)),
            "largest_empty_region_p75_micros": percentile(empty_regions, 0.75),
            "unique_fixture_types_p25": percentile(unique, 0.25),
            "fixture_count_p25": percentile(fixture_counts, 0.25),
        }
    result = {
        "source": [str(path).replace("\\", "/") for path in MAPS],
        "measurement": "connected non-wall floor components sharing an exact mapped area; functional floor fixtures exclude utilities, doors, windows, pipes, lights, and decals",
        "rooms_measured": len(rooms),
        "profiles": profiles,
        "rooms": rooms,
    }
    output = Path("tools/generated_station/southern_cross_reference.json")
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output}: {len(rooms)} rooms, {len(profiles)} role profiles")


if __name__ == "__main__":
    main()
