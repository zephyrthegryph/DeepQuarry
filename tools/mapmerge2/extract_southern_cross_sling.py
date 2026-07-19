#!/usr/bin/env python3
"""Extract the archived carrier sling footprint into a reusable map template."""

import subprocess
import sys

from dmm import Coordinate, DMM


REVISION = "a5b8cb92d1^"
SOURCE = "maps/southern_cross/southern_cross-2.dmm"
OUTPUT = "maps/southern_cross/southern_cross-sling.dmm"
AREAS = ("/area/shuttle/expoutpost/station", "/area/expoutpost/stationshuttle")
PADDING = 2


def main():
    raw = subprocess.check_output(["git", "show", f"{REVISION}:{SOURCE}"])
    raw = raw.replace(b"health = ", b"max_integrity = ")
    source = DMM.from_bytes(raw)
    matched = []
    for coord in source.grid:
        tile = source.get_tile(coord)
        if any(any(area in atom for area in AREAS) for atom in tile):
            matched.append(coord)
    if not matched:
        raise RuntimeError("archived sling areas were not found")

    min_x = max(1, min(c[0] for c in matched) - PADDING)
    max_x = min(source.size.x, max(c[0] for c in matched) + PADDING)
    min_y = max(1, min(c[1] for c in matched) - PADDING)
    max_y = min(source.size.y, max(c[1] for c in matched) + PADDING)
    result = DMM(3, Coordinate(max_x - min_x + 1, max_y - min_y + 1, 1))
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            result.set_tile(Coordinate(x - min_x + 1, y - min_y + 1, 1), source.get_tile(Coordinate(x, y, 1)))
    result.to_file(OUTPUT, tgm=False)
    print(f"wrote {OUTPUT}: source origin ({min_x},{min_y}), size {result.size.x}x{result.size.y}")


if __name__ == "__main__":
    sys.exit(main())
