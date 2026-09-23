"""MCP stdio bridge. Uses the same running Map Studio service as the browser."""

from __future__ import annotations

import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

URL = os.environ.get("DQ_MAPSTUDIO_URL", "http://127.0.0.1:8765/api")

TOOLS = [
    ("map_list", "List editable .dmm maps.", {}),
    ("map_info", "Get map dimensions and revision.", {"map": "string"}),
    ("map_inspect", "Inspect tiles in a rectangle (maximum 2500 tiles).", {"map": "string", "rect": "object"}),
    ("map_catalog", "Find map atom paths, optionally filtering query and layer.", {"map": "string", "query": "string?", "layer": "string?"}),
    ("map_check", "Check mapped power, atmos, disposal port reciprocity and APC cable presence in a rectangle. This is static validation, not a game simulation.", {"map": "string", "rect": "object"}),
    ("map_preview", "Preview operations without saving. Paint/place/erase accept at, rect, or disconnected points; copy/move use a rectangle; route uses adjacent points. Inspect warnings and diff before commit.", {"map": "string", "operations": "array"}),
    ("map_commit", "Save a reviewed preview to TGM and create a backup.", {"preview_id": "string"}),
    ("map_dismiss", "Discard a proposed edit without saving it.", {"preview_id": "string"}),
    ("map_undo", "Undo the last Map Studio save if the map has not changed since.", {}),
    ("map_activity", "Read the current proposal, revision, and pending edits.", {}),
    ("map_network_component", "Trace one connected power, atmos, or disposal network, optionally including proposed operations.", {"map": "string", "at": "object", "atom": "string", "operations": "array?"}),
    ("map_route", "Preview a connected power, atmos, or disposal route. Points must be adjacent and ordered; existing endpoints are updated.", {"map": "string", "layer": "string", "atom": "string", "points": "array"}),
    ("map_network_join", "Preview a junction between compatible network endpoints at one tile.", {"map": "string", "layer": "string", "atom": "string", "at": "object"}),
    ("map_network_cross", "Preview an unconnected power or atmos crossing over one straight segment.", {"map": "string", "layer": "string", "atom": "string", "at": "object"}),
    ("map_network_split", "Preview removal of one exact network segment, splitting its component.", {"map": "string", "layer": "string", "atom": "string", "at": "object"}),
    ("map_place", "Preview placing an object, decoration, APC, fixture, or single floor/area type at points. Optional vars set mapped appearance.", {"map": "string", "layer": "string", "atom": "string", "at": "object?", "points": "array?", "vars": "object?"}),
    ("map_paint", "Preview replacing a layer over a rectangle, one tile, or selected points; use for floors, walls, or areas.", {"map": "string", "layer": "string", "atom": "string", "at": "object?", "rect": "object?", "points": "array?"}),
    ("map_erase", "Preview removing all atoms in one non-floor layer from a tile, rectangle, or selected points.", {"map": "string", "layer": "string", "at": "object?", "rect": "object?", "points": "array?"}),
    ("map_fill", "Preview a bounded four-way flood fill of matching tiles, up to 2,500 tiles.", {"map": "string", "layer": "string", "atom": "string", "at": "object"}),
    ("map_room", "Preview a rectangular room with boundary walls, interior floor, and area. Place doors and fittings in the same proposal with map_preview.", {"map": "string", "rect": "object", "floor": "string", "wall": "string", "area": "string"}),
    ("map_remove", "Preview removing one exact mapped atom at a tile.", {"map": "string", "at": "object", "atom": "string"}),
    ("map_edit", "Preview changing one mapped atom's type or variables.", {"map": "string", "at": "object", "atom": "string", "path": "string?", "vars": "object?"}),
    ("map_move", "Preview moving a full rectangular tile stack by an offset.", {"map": "string", "source": "object", "dx": "integer", "dy": "integer", "replace": "boolean?"}),
    ("map_copy", "Preview copying a full rectangular tile stack by an offset.", {"map": "string", "source": "object", "dx": "integer", "dy": "integer", "replace": "boolean?"}),
]


def schema(fields):
    types = {"string": "string", "object": "object", "array": "array", "integer": "integer", "boolean": "boolean"}
    return {"type": "object", "properties": {name: {"type": types[kind.rstrip("?")]} for name, kind in fields.items()},
            "required": [name for name, kind in fields.items() if not kind.endswith("?")]}


def call(name, arguments):
    operations = {
        "map_route": "route", "map_network_join": "network_join", "map_network_cross": "network_cross",
        "map_network_split": "network_split", "map_place": "place_atom", "map_paint": "paint",
        "map_fill": "fill", "map_room": "room", "map_erase": "erase", "map_remove": "remove_atom",
        "map_edit": "edit_atom", "map_move": "move", "map_copy": "copy",
    }
    method = "maps" if name == "map_list" else name.removeprefix("map_")
    if name in operations:
        op = {key: value for key, value in arguments.items() if key != "map"}
        op["action"] = operations[name]
        arguments = {"map": arguments["map"], "operations": [op]}
        method = "preview"
    request = Request(URL, data=json.dumps({"method": method, "args": arguments}).encode(),
                      headers={"Content-Type": "application/json"})
    try:
        with urlopen(request, timeout=120) as response:
            return json.load(response)
    except HTTPError as exc:
        return json.load(exc)
    except URLError as exc:
        return {"error": f"Start Map Studio first: {exc}"}


def handle(message):
    method = message.get("method")
    if method == "initialize":
        return {"protocolVersion": "2025-06-18", "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "deepquarry-mapstudio", "version": "1.0.0"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": [{"name": n, "description": d, "inputSchema": schema(f)} for n, d, f in TOOLS]}
    if method == "tools/call":
        name = message["params"]["name"]
        if name not in {t[0] for t in TOOLS}:
            raise ValueError("Unknown tool")
        result = call(name, message["params"].get("arguments", {}))
        return {"content": [{"type": "text", "text": json.dumps(result)}], "isError": "error" in result}
    raise ValueError("Unknown method")


def main():
    for line in sys.stdin:
        try:
            message = json.loads(line)
            if "id" not in message:
                continue
            result = {"jsonrpc": "2.0", "id": message["id"], "result": handle(message)}
        except Exception as exc:
            result = {"jsonrpc": "2.0", "id": message.get("id") if isinstance(message, dict) else None,
                      "error": {"code": -32603, "message": str(exc)}}
        sys.stdout.write(json.dumps(result) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
