# DeepQuarry Map Studio

A local browser editor and MCP bridge for the same transactional TGM map service.
It edits existing `.dmm` files under `maps/`; it never saves an edit until a
preview is committed. Every save creates a sibling `.mapstudio.bak` file.

## Start

From the repository root, run:

```powershell
python tools/mapstudio/server.py
```

Open <http://127.0.0.1:8765> in a browser. The map fills the window. Use the
floating dock to select tiles, draw cable/supply/scrubber/disposal routes, or
place an APC. **Select** replaces the selected region; Ctrl+drag adds tiles and
Ctrl+Shift+drag removes tiles. Ctrl+Z undoes a selection, discards the current
proposal, or undoes the last Map Studio save. A route can be drawn by dragging
or clicking adjacent tiles. **Cable** opens a color picker and **Atmos** opens
one pipe-type picker for supply and scrubbers. Their settings floater also stages
or clears the current route. In-progress routes draw their cable or pipe sprites
with the selected color. **Areas** toggles a colored area overlay. The
**Review** button opens the tile, systems, and proposal menus; save after
reviewing the proposal, or discard it. **Map & tools** opens map/deck controls, advanced edits,
and layer visibility. The Layers panel has separate visibility and Edit controls
for each layer. Right click a tile to inspect its atom stack, pick a type,
copy and paste an atom, edit its appearance or remove that exact atom. Right
drag, middle drag, Space+drag, or arrow keys pan continuously; the wheel zooms
around the pointer. The type picker searches types defined in the repository
and paths already used in the selected map. The view draws sprites from the
repo's editable PNG sheets and DMI metadata, including mapped colors, pixel
offsets, and layer order. Proposed additions use their actual sprite; removed
atoms appear as a faded sprite with a red slash.
The dock selects cable, supply or scrubber pipe, disposal segment, or APC
placement with the matching layer and type already filled in. Route
endpoints pick up compatible neighboring ports. The Mapped systems check reports
possible broken links and APCs without a cable on their tile.
Read-only map operations reuse a parsed map until the source file changes.
The browser loads visible tiles before its type catalog. When panning, it fetches
only the newly exposed strips; large views are split into requests under the
server's tile limit. Sprites load in small atlas batches. The WebGL2 viewport
renders the map while the 2D canvas handles editing controls and fallback.

`maps/mapstudio_reactor_demo.dmm` is a disposable, standalone R-UST reactor
suite for exercising the editor. Rebuild it with
`python tools/mapstudio/build_reactor_demo.py`. The 27 by 21 tile suite is
built from individual atoms: a shielded chamber, tagged controls, indoor TEG
and coolant service, fuel preparation, and separate APC areas. The Sif outpost
reactor informed the equipment list; none of its room tiles are copied. The
static mapped-port check and maplint pass. It is not registered as a live
station map or validated through a game boot.
Agent previews appear in the browser automatically, where you can inspect and
save them. The browser can undo the last Map Studio save if no one has edited
the map since then.

## MCP connection

Codex has a project MCP definition in `.codex/config.toml`. Restart Codex
after adding it to load the tools. Keep the browser service running so the
agent and browser share previews and edits. In other MCP clients, point a
stdio server at this script:

```json
{
  "mcpServers": {
    "deepquarry-mapstudio": {
      "command": "python",
      "args": ["tools/mapstudio/mcp.py"],
      "cwd": "E:/projects/CHOMPStation2"
    }
  }
}
```

If the browser server uses another port, set `DQ_MAPSTUDIO_URL` to its `/api`
URL in the MCP server's environment. The bridge speaks MCP over stdio and
offers `map_list`, `map_info`, `map_inspect`, `map_catalog`, `map_check`,
`map_preview`, `map_commit`, `map_dismiss`, and `map_undo`. It also provides
direct tools for common edits: `map_route`, `map_network_component`,
`map_network_join`, `map_network_cross`, `map_network_split`, `map_place`,
`map_paint`, `map_erase`, `map_fill`, `map_room`, `map_remove`, `map_edit`, `map_move`,
and `map_copy`. `map_activity` reports the proposal visible in the browser.
Each editing tool creates a proposal with a diff and warnings; save it with
`map_commit` after review. Use `map_preview` to combine several operations
into one proposal, such as a room, door, APC, and cable route.

## Editing operations

`map_preview` accepts `{"map":"maps/...dmm","operations":[...]}`. Operations
can be combined into one preview:

```json
{"action":"paint","layer":"turf","rect":{"x1":2,"y1":3,"x2":5,"y2":6,"z":1},"atom":"/turf/simulated/floor"}
{"action":"place","layer":"apc","at":{"x":3,"y":4,"z":1},"atom":"/obj/machinery/power/apc"}
{"action":"move","source":{"x1":2,"y1":3,"x2":5,"y2":6,"z":1},"dx":10,"dy":0,"replace":false}
{"action":"route","layer":"power","atom":"/obj/structure/cable","points":[{"x":2,"y":3,"z":1},{"x":3,"y":3,"z":1}]}
{"action":"paint","layer":"turf","points":[{"x":2,"y":3,"z":1},{"x":5,"y":3,"z":1}],"atom":"/turf/simulated/floor"}
{"action":"fill","layer":"turf","at":{"x":2,"y":3,"z":1},"atom":"/turf/simulated/floor/tiled"}
{"action":"room","rect":{"x1":2,"y1":3,"x2":8,"y2":9,"z":1},"floor":"/turf/simulated/floor/tiled","wall":"/turf/simulated/wall","area":"/area/space"}
```

The diff and any isolated-network warnings return with a `preview_id`; pass
that ID to `map_commit`. A commit fails if the map changed on disk since the
preview. `move` and `copy` preserve each source tile's full atom stack. A move
leaves the destination's former floor and area at the source footprint.

Type paths must be defined in the repository or occur in the selected map.
Network routing generates cable `icon_state`, atmos `dir`, and disposal segment
`dir`/`icon_state` from the route geometry and matching neighboring ports.
The Mapped systems panel and `map_check` tool check reciprocal mapped ports
and APC cable presence in a selected region.
This does not prove that a destination is pressurized, powered, or reachable by
disposal machinery. Check those in a local game boot before using a changed
map in production. Saves run the Rust mapcore parser and repo map lint before
replacing the source file.

Run `python -m unittest discover -s tools/mapstudio -p test_engine.py` for
transaction tests, then use the repo's map lint and mapmerge checks.
