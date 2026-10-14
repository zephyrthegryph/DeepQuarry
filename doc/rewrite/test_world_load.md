# Test world: what loads before world/New (design note, for review)

Measured 2026-10-13 on `boot-speed/load`. Nothing here is implemented; it is the evidence and the options.

## Timing

DreamDaemon spawn to `world/New`: about 19 s unprofiled, 33.6 s with `-profile` on a loaded machine
(`-params boot_profile=1`, logged as `Boot timing: world/New reached Ns after DreamDaemon was spawned`).
Global var initialisation is not it: the 1,532 `InitGlobal*` procs total 0.018 s, GLOB creation 1.6 s (and it runs inside `world/New`).
What is left is DreamDaemon reading the .rsc and the .dmb and instantiating the compiled map.

## Compiled map (virgo_minitest, 3 z-levels of 100x100)

Counted from the three `.dmm` files (key dictionary x grid):

| | Count |
|---|---|
| turfs | 29,997 |
| objs | 4,282 |
| mobs | 11 |
| atoms created before `world/New` | about 34,300 (the profile shows 36,706 `/atom/New` calls, 36,704 `InitAtom`) |

Top types: `/turf/space` 17,751 (59% of turfs), `/turf/simulated/floor/beach/sand` 4,556, `/turf/simulated/mineral` 2,656,
`/turf/simulated/floor/tiled` 1,330, `/obj/structure/window/reinforced` 773, water 762 + deep 444, grille 407,
`/turf/unsimulated/wall` 322, `/turf/simulated/wall/r_wall` 257, lattice 251, cable 231.
Filler that most focused tests never touch (space, rock, walls): about 21,600 turfs, 72% of all turfs.
z2 and z3 are the overmap demo sectors (beach planet, carp farm; `virgo_minitest_sectors.dm`) and are almost all sand, water, rock and space.

Options (not implemented):
1. Move z2/z3 out of the compiled map and load them as map templates only for the tests that use overmap sectors. It removes about 40,000 cells and most non-space atoms of those levels. It breaks any test that reads z2/z3 or the sector objects at boot; 15 test files mention `maxz`/z-level numbers and need an audit.
2. Shrink z1 (100x100, 877 distinct keys) to its used bounds. Tests depend on named areas and machines, so this needs the same audit.
3. Neither fixes the .rsc part below. No measurement yet says how much of the 19 s is atoms versus resources, so measure before cutting a map: boot the same dmb with z2/z3 removed in a scratch copy and compare the `Boot timing` line.

## The .rsc (224 MB)

Single-quoted resources referenced from `code/`:
- sounds: 1,918 files, about 110 MB (ambience 24 MB, effects 21, vore 11, machines 10, music 9, voice 8, runtime 8)
- icons: 1,894 files, about 104 MB (`caelus.dmi` 12.8 MB, `ionbox.dmi` 4.2, `screen_full.dmi` 3.8, `skybox_vr.dmi` 3.3)
Together about 215 MB of the 224 MB.

Options (not implemented): under `CITESTING`, have the sound-set tables reference sounds by string path (no packing) instead of `'file'`; skip the skybox dmis. Both change asset loading and any test that reads sound file existence or icon states. I did not measure the load delta: a smaller .rsc needs a recompile (about 5 min plus the compile queue) and a test world launch, and a world started by hand would have to be killed, which I did not do. Experiment to run: compile once with the sound tables excluded from packing and compare the `Boot timing` line (three samples each).

## Experiments (2026-10-14, `boot-speed/world`; `Boot timing` line, `-profile` on, machine loaded)

| Variant | .rsc | launch to `world/New` |
|---|---|---|
| master | 224.5 MB | 30.0 s, 25.8 s |
| no z2/z3 (sector `.dmm` includes removed) | 224.5 MB | 29.1 s, 24.8 s, 21.9 s |
| no z2/z3 and every `.ogg` under `sound/` replaced by a 2.6 KB stub (.rsc rebuilt from scratch) | 123.1 MB | 26.4 s |

Run-to-run noise on this machine is about 4 s. Removing 20,000 of the 34,000 compiled atoms gains about 1 s; shrinking the .rsc by 101 MB (45%) gains nothing measurable.
Conclusion: neither option pays. Compiled map atoms (about 1 s) and .rsc size (about 0 s) are not where the pre-`world/New` time goes, so neither the z2/z3 opt-in nor the sound-free test build was implemented.
The no-z2/z3 boot also passed the boot gate with no tests that need those levels, so the remaining time is DreamDaemon startup work this note has not isolated (dmb load and proc tables, native DLL load, z1 atoms).

Build quirks found: `compileDerived()` hashes the dme text, defines and compiler version only, so changing a resource file reuses the old .dmb; and DreamMaker keeps an existing .rsc, so a repack needs the old `deepquarry.test.rsc` deleted.
