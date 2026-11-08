# Follow-up: the test map's Unit Test Room boots as vacuum

Open. Found 2026-11-08 while chasing the breach leak (breach_air_guard_leak.md).

On `maps/virgo_minitest` the Unit Test Room's block floors (`/turf/simulated/floor/tiled/steel`, e.g. (2,2,4)) read 0 mol at 2.7 K
right after boot, through the DM datum and the Rust cell alike, although the type's own air is 104 mol at 293 K. Writing 104 mol into
one of them shows 0 mol on the next read and after two gas frames. The floor shares air north and east; no space turf is within one tile.

Not caused by the lazy turf air: a build that made every open turf's air datum before the boot registration (the pre-lazy order)
reads the same. Not the real map: Southern Cross rooms read 104 mol after boot.

Questions for whoever takes it: is the room vacuum by the map's design (an airless test room), or does it vent to space somewhere at
boot (its open faces lead through the block edge)? If it vents, what connects it, and do tests that assume a breathable block rely on it?
The harness no longer depends on the answer: the block reset restores each floor's session-start air.
