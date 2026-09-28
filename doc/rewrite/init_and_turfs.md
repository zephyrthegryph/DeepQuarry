# Init and turfs: boot and bulk-destroy speed

Status: design, from measurements taken 2026-09-26 on `rewrite/boot-perf`
(branched from `rewrite/om-integration` at 7a33a8f24e). No gameplay code
changes here; this document says what to build and in what order.

## 0. How this was measured

Map: Southern Cross (`-DCITESTING_FULL_MAP`), 256x256x6 = 393,216 turfs,
94,361 movables after boot, 505,930 `InitAtom()` calls. BYOND 516.1687.

Scenarios (`code/modules/benchmarks/boot_profile.dm`):

- `boot_profile`: per-subsystem init time, world and lighting counts; with
  `-DBENCHMARK_DEEP_PROFILE`, self time per concrete type of `Initialize()`,
  the post-Initialize step (`materialize()` plus the created-on signal and
  ledger note) and `LateInitialize()`, with nested atom creation subtracted.
  With `--profile`, the BYOND proc profiler runs from the Profiler
  subsystem's init (INITSTAGE_FIRST, before map load) and is summarised.
- `explosion_dense`: `explosion(center, 7, 14, 21)` on the station block
  (15x15, radius 7) with the most furnishings (structures, items and
  non-atmos machinery; pipes and cables excluded; blocks near the
  supermatter excluded). It picked the Security Brig (128,178,2): 841 turfs,
  169 walls, 1,486 objects, 621 machines. Reports the explosion subsystem's
  own phase timers, garbage deltas by type, and with the deep define the
  destroy-transaction phases **exclusive** of nested qdels (lifecycle.md §2).

Runs (all in `data/bench/runs/`, profiles in `data/bench/profiles/`):

| Label | Build | Scenarios | Boots with results |
|---|---|---|---|
| `boot-perf-clean` | plain | boot_profile, explosion_dense | 1/3 (explosion on the first site pick, Engineering Foyer) |
| `boot-perf-clean2` | plain | boot_profile, explosion_dense | 2/3 (Brig) |
| `boot-perf-clean3` | plain | explosion_dense | 0/3 |
| `boot-perf-deep`, `boot-perf-deep-explosion` | deep + profiler | both / explosion | 0/3, 0/3 |
| `boot-perf-deep-boot` | deep + profiler | boot_profile | 3/3 |
| `boot-perf-explosion-phases` | deep | explosion_dense | 2/3 |
| `boot-perf-explosion-profile` | profiler | explosion_dense | 1/3 |

The deep instrumentation (three rust-g timer calls per atom) and the
profiler roughly double Atoms init (99–162 s against 51–92 s clean). Use the
deep numbers for **shares**; the per-item savings below are scaled to the
clean boot with factor 0.54 (clean Atoms mean 67.5 s / instrumented type sum
125.0 s).

### 0.1 The world runs out of address space

DreamDaemon is 32-bit. After boot it holds 2.1–2.3 GB private memory, and the
Rust heap peaks at **1.85 GB during boot** (current 0.63 GB afterwards).
15 of the 21 boots that ran `explosion_dense` died, most on a Rust `memory allocation of ~9 MB failed`
(fragmented address space, not a DM runtime); the rest exited silently. Boot-only runs never failed. This is a correctness problem
on the live map, independent of speed: the first thing a round with a big
bomb can hit. It is item 0 in §6.

### 0.2 Memory after the fixes (2026-09-27, `rewrite/boot-perf` 042983e910)

Runs `final-boot`, `final-explosion`, `final-memory` (and `s2-*` for step 2
alone), Southern Cross, 3 boots and 3 explosions each.

| | Before (7a33a8f24e) | After |
|---|---|---|
| Rust heap peak during boot | 1,850 MB | **226 MB** |
| Rust heap steady after boot | 630–690 MB | **65–100 MB** |
| DreamDaemon private after boot | 2,240–2,280 MB | 1,280–1,590 MB |
| DreamDaemon peak private (whole run) | 3,510–3,760 MB | 1,820–2,090 MB |
| `explosion_dense` survived | 6 of 21 | **6 of 6** |

What held the Rust peak (boot marks, `rust_memory_marks` detail): turf
registration queued one command and one overlay copy of every cell (gas
63 + 72 MB, heat 18 + 20 MB, geometry 11 + 48 MB), and the first field frames
stepped every 16x16 chunk of the grid, space included, so the heat cell store
alone was 320 MB and the gas store 128 MB. The allocation failures were
single large blocks (a doubling `Vec` of 144-byte gas commands) in a
fragmented 32-bit address space. Fixed by: direct bulk writes into the live
stores (`Sim::write_direct`), no stored value for empty space reservoirs,
field steps that only list chunks with nodes, and fixed 1024-entry chunks for
command batches, the overlay and the main mixture slab.

What the Rust heap holds now (70 MB): gas cells 12 MB, heat cells 8 MB,
geometry 6 MB, main mixtures 7 MB, pipes 4 MB, masks 4 MB, the rest is
reactor, entity and small stores. The 226 MB peak is the first frames'
copy-on-write snapshots right after SSair init; it is transient.

### 0.2a Regression and fix on the shared World (2026-09-27, `rewrite/b-boot`)

The move to the shared World (rust-core2) dropped the bulk direct writes: turf
registration went through `MainPort::put` again, one command and one overlay
entry per cell. Southern Cross measured 384 MB Rust peak and 155 MB booted
(marks: +183 MB at "air: turfs registered", the rest in the first frames). Two
fixes:

- `_auxmos_register_turfs_bulk` and `heat_set_turfs_bulk` buffer their rows and
  write them with `Sim::write_direct` (`verdigris/ffi/src/bulk.rs`), falling back
  to the port when the domain is not quiescent (counters `bulk.direct_flushes`,
  `bulk.port_fallback_*` in `verdigris_metrics()`).
- A field step's per-owner flux buffers are allocated on the chunk's first
  live edge. Every space chunk with geometry is an owner on the first frames,
  and a full-size buffer for each was most of the transient.

`boot_memory_tests::southern_cross_boot_rust_heap_peak_is_bounded` (vg-ffi)
drives the same path on a 256x256x5 grid: 255 MB peak before, 113 MB after
(registration 173 → 63 MB). It fails above 160 MB. The DM unit test
`dq_rust_heap_peak_bounded` checks the live world against 512 MB.

Phase 4 track 4b (2026-09-28, `rewrite/k-boot`) took the same test from
113 MB to **55 MB peak** (ceiling now 70 MB):

| Mark | current before | peak before | current after | peak after |
|---|---|---|---|---|
| world built | 6.3 | 7.0 | 6.3 | 7.0 |
| turfs registered | 62.9 | 63.7 | 12.4 | 14.6 |
| first frames | 76.5 | 113.4 | 33.2 | 54.9 |

- Uniform chunks share one allocation. Space is ~85% of the grid and every
  space cell holds the same immutable vacuum, so a bulk flush now points each
  all-identical chunk it touched at one shared chunk
  (`CowStore::share_uniform_chunks`, counter `bulk.shared_uniform_chunks`).
  Gas registration went from 43 MB of chunks to ~7 MB. A later write copies
  the chunk as for any shared one. Field steps never list pure-space chunks,
  so they stay shared.
- Substeps don't snapshot. `FieldState::advance` took a snapshot of the
  cells each substep, so the apply pass copied every target chunk again each
  substep. The fluxes are all computed before anything is written, so they
  read the live store directly. First-frame peak went from 113 to 70 MB.
- Owner fluxes are summed per receiving cell. Before, the buffer held one
  flux per cell and axis. It now holds one sum per cell of the chunk, plus
  strips for the edges that leave it east, north and up, each allocated on
  first use. Gas fluxes are 92 bytes, so this took the per-substep buffers
  from ~21 MB to ~14 MB. The peak went from 70 to 55 MB.

What is left at the peak: two copies of the ~8 MB station gas chunks (the
live store being written and the snapshot the step started from, which the
pinned view and `last_cells` share), ~14 MB of per-substep flux buffers
(the vertical strip is as big as the per-cell sum wherever decks are open to
each other), and ~12 MB of registered state. The live boot is not
reproduced by this test. A base-tree bench boot with the old DLL logged
73 MB after turf registration and 182 MB current / 404 MB peak after SSair
init and the first frames. The unmeasured part is SSair init (14.8 s:
pipenets, machinery, heat bodies), and it needs `RUST_ALLOC_PROFILE` marks
around its stages to find out what allocates there.

### 0.2b Phase 4 on the live map (2026-09-28, `rewrite/k-boot`)

Southern Cross bench boots (`bench -DCITESTING_FULL_MAP --scenario=boot_profile`),
one boot each on a quiet machine. The base is integrate/b7 (7c907512ab) with
its prebuilt DLL; "after" is `rewrite/k-boot` with the 4b DLL.

| | Base | After (2 boots) |
|---|---|---|
| Init total | 65.6 s | 59.8 s, 55.9 s |
| Atoms | 47.2 s | 41.1 s, 37.5 s |
| Atmospherics | 8.9 s | 9.0 s, 8.5 s |
| Lighting | 4.0 s | 3.9 s, 4.1 s |
| Rust heap peak | **403 MB** | **176 MB**, 176 MB |
| Rust heap steady | 189 MB | 151 MB |
| DreamDaemon private, booted | ~1,550 MB | 1,440-1,540 MB |

Two earlier base boots taken while two Rust/DM builds ran on the machine gave
110 s and 85 s, so treat single-boot timings as �5 s.

`benchmark_rust_mark()` now also logs `BENCH_RUST_MARK` lines, and SSair marks
its turf visuals step and its first eight fires, so a boot keeps its memory
marks even when the scenario never starts. After-boot marks: 70 MB after Atoms,
137 MB after `air: turfs registered` (+67 MB: the uniform-chunk sharing
that took the vg-ffi test's registration from 64 to 15 MB does not show up
here yet; cause below), 153 MB peak after pipenets, 168 MB at round start, then 118-126 MB
over the first fires.

**Why registration missed the bulk path (fixed in rewrite/l-boot2).** The
run's metrics show `bulk.direct_flushes` 94 and `bulk.port_fallback_flushes`
94 (749,887 rows): half of the bulk flushes went through commands and the
overlay, which is the old per-cell cost and never reaches
`share_uniform_chunks()`. A bulk flush writes the live store only when its
domain is quiescent, and during SSatoms a few turfs already registered one
by one: `SSair.add_to_active()` on an initialized turf calls
`update_air_ref()` at once (atoms spawning gas, pipelines, fires), which puts
port writes into the gas and heat domains. No frame runs during init, so
those writes stayed queued and every later bulk flush of those domains fell
back. `Sim::write_direct()` now folds a domain's queued writes into its
live store first (as the next frame's apply step would; not while recording
or with a frame in flight), and `early_single_registrations_keep_the_bulk_path`
in `boot_memory_tests.rs` covers it (160 fallbacks before, 0 after, 12 MB at
"turfs registered"). Expect the live mark to drop from +67 MB toward the
test's +6-15 MB, and the ~40 MB fall at "air: fire 1" (the overlay
draining) to go away. Station chunks that mix walls, air and space still
cannot share; only uniform chunks (mostly space) do.

**Measuring caveat.** On this tree the bench scenario never starts on the full
map: after round start the latency sweep keeps hitting a runtime in
`state_count_refs_in` (a recharge station's circuit board) and the test-build
reference finder spends its whole 323 s budget on it, while atmos uses ~125 ms
a tick. The numbers above come from the boot log (`Initialized ... within`,
`RUST_ALLOC_PROFILE`, `BENCH_RUST_MARK`) and `data/bench/process.json`.

### 0.2c rewrite/l-boot2 on the live map (2026-09-28)

One Southern Cross boot (`bench -DCITESTING_FULL_MAP --scenario=boot_profile`,
`DQ_PREBUILT_VERDIGRIS=1` with the l-boot2 DLL). The machine was building
Rust for another session at the same time (about 20 rustc processes), so the
times are not comparable. The memory marks are.

| | k-boot (0.2b) | l-boot2 |
|---|---|---|
| Atoms | 37.5-41.1 s | 61.4 s (loaded machine) |
| Atmospherics | 8.5-9.0 s | 14.5 s (loaded machine) |
| Lighting | 3.9-4.1 s | 7.0 s (loaded machine) |
| Rust after Atoms | 70 MB | 68 MB |
| `air: turfs registered` | 137 MB (**+67**) | 87 MB (**+18**) |
| after pipenets | 153 MB (peak) | 98 MB (peak 103) |
| Rust peak, first fires | 176 MB | **130 MB** |
| Rust steady, fires 1-8 | 118-126 MB | 109-112 MB |
| private after Atoms | ~985 MB | 1,152 MB |

Turf registration now stays on the bulk path (see "Why registration missed"
below). Take a quiet-machine boot before quoting any of these times. The run
logged one runtime, repeated: `get_moles_hook` "no gas mixture behind
handle 1" from the algae farm's `internal` mixture (a compile-time `new()`) in
the OM pipeline audit. It is not yet known whether this is new.

### 0.3 DM memory census (boot_memory, sampled)

809,798 instances: 393,216 turfs, 85,819 objs, 321,633 datums. The per-type
model (`benchmark_type_memory()`: 48 B per datum, 96 per atom, 12 per changed
var, 32 per list, 12 per entry) accounts for **~230 MB**; the other ~1.1 GB of
the 1.33 GB private is outside datums (appearances, the icon and resource
cache, strings, BYOND itself) and needs its own measurement before the 1 GB
target can be planned in full.

| # | Type | Instances | Changed vars | Lists / entries | Est. MB | Fix |
|---|---|---|---|---|---|---|
| 1 | `/turf/space` | 310,652 | 18 | 0 | 92 | Type table (§3.1): no `Initialize()`, cached appearance; changed vars go to ~2 |
| 2 | `/datum/rule_binding` | 21,759 | 11 | 169 k / 780 k | 18 | Per-type binding tables, per-instance state in one flat list (§3.3) |
| 3 | `/datum/light_source` | 15,889 | 15 | 16 k / 417 k | 13 | Lighting as a core field (§5); `effect_str` leaves DM |
| 4 | `/datum/lighting_corner` | 47,225 | 10 | 29 k / 52 k | 9 | Core field (§5) |
| 5 | `/datum/weakref` | 65,255 | 1 | 0 | 4 | OM handles replace weakrefs (LC-refs) |
| 6 | `/turf/simulated/wall/r_wall` | 4,916 | 25 | 10 k / 98 k | 3 | Intern `damage_overlays` and `wall_connections` per type/state |
| 7 | `/datum/om/rec` | 6,787 | 11 | 36 k / 64 k | 3 | Lazy lists on the rec |
| 8 | `/datum/gas_mixture/turf` | 47,205 | 1 | 0 | 3 | The handle is the turf cell: create the datum on first `return_air()` |
| 9 | `/datum/lighting_object` | 29,904 | 2 | 0 | 2 | Core field (§5) |
| 10 | `/turf/simulated/floor/reinforced/airless` | 9,844 | 10 | 393 | 2 | Type table |
| 11 | `/turf/simulated/floor/tiled` | 5,795 | 16 | 4 k / 7 k | 2 | Type table; decals interned |
| 12–13 | supply / scrubber pipes | 6,917 | 25 | 14 k / 35 k | 3.4 | Intern `atom_colours`; one number instead of `rust_pipe_port_ids` for one-port pipes |
| 14 | `/obj/structure/window/reinforced` | 6,705 | 14 | 0 | 2 | Type table |
| 15 | `/datum/state_schema` | 554 | 3 | 1 k / 134 k | 2 | Per type already; fine |
| 16–17 | transit space | 11,072 | 14 | 0 | 2.8 | Type table (as space) |
| 18 | `/turf/simulated/wall` | 1,922 | 22 | 4 k / 38 k | 1 | As r_wall |
| 19 | `/turf/unsimulated/floor` | 6,548 | 7 | 622 | 1 | Type table |
| 20 | `/obj/structure/cable/green` | 3,121 | 17 | 3 k / 12 k | 1 | Intern `atom_colours` |

### 0.4 Where the rest of private memory goes (2026-09-27)

Runs `r2-*` (memory marks read DreamDaemon's private bytes, sampled once a
second from outside). Southern Cross, warm caches, 3 boots:

| Stage | Private MB | Growth |
|---|---|---|
| empty DM world (reference) | 4 | |
| `world/New()` entered: compiled world, globals, compiled map | 680-700 | **~680** |
| datum reference lists, before Master init | ~740 | +40 |
| Atoms init | ~985 | +245 |
| air (turf registration, pipenets) | ~1,070 | +85 |
| Lighting | ~1,140 | +70 |
| MC init done | ~1,150 | |
| round start and the 10 s settle | 1,195-1,220 | +45-70 (was +320-390) |
| **booted** | **1,190-1,220** (was 1,480-1,590) | |
| peak over the run | 1,210-1,380 (was 1,820-1,880) | |

What the experiments showed:

- **The ~680 MB before `world/New()` is the compiled world itself, not
  the map and not DM data.** The minitest map (30 k turfs) enters
  `world/New()` at 635 MB against 680-700 for Southern Cross (393 k
  turfs). The GLOB lists hold ~8 MB in total (deep counts, `globals_top`:
  largest `dq_icon_metadata_cache` 1.9 MB, `state_schemas` 1.6 MB,
  `asset_datums` 1.2 MB). A profile started with the process (`-profile`)
  shows no DM proc time before `world/New()`: it is BYOND loading the .dmb
  (47 MB) and the .rsc (208 MB, which compiles in 224 MB of `sound/` and
  379 MB of `icons/gen/` sources), growing linearly for ~11 s.
- **Private memory is live memory.** Freeing every overlay and all lighting
  did not lower it (BYOND keeps freed memory in its pools), but a probe that
  allocated ~180 MB of lists grew it by 217 MB: the pools held no reusable
  free space.
- **Appearances are small.** 42,961 unique atom appearances, 24,137 unique
  overlay/underlay appearances and 531,878 overlay references over 488 k
  atoms; 1,331 `/icon` objects, no stray images or mutable appearances. At
  BYOND's ~100-200 bytes per appearance that is 10-15 MB plus ~2 MB of
  references.
- **Round start regenerated every batched spritesheet** (+260 MB, on every
  Asset Loading fire): `SMART_CACHE_ASSETS` defaulted off. Fixed (on by
  default; it invalidates itself).

The world-load experiments (one boot each, `r3-*`):

| Build | Private MB at `world/New()` |
|---|---|
| Southern Cross, as is | 682-703 |
| Southern Cross, all 3,235 sounds stubbed to 4 bytes (217 MB out of the .rsc) | 698 |
| minitest, as is | 635-667 |
| minitest, all 1,982 .dmi stubbed to one 211-byte icon (372 MB out) | 658 |
| empty world | 4 |
| synthetic: 20,000 /obj types, 3 vars each (4.4 MB .dmb) | 19 |
| synthetic: same plus 5 procs each (10.8 MB .dmb) | 35 |

So the ~680 MB is **not** resources (sounds and icons are read from the
.rsc on demand), **not** the map (minitest's 30 k turfs vs Southern Cross's
393 k differ by ~40 MB) and **not** DM code we can see: per-global and
per-subsystem-constructor notes (`early_notes`) show memory already at
611 MB when global init starts, and those steps take no measurable time.
It grows over ~10 s while BYOND loads the 47 MB .dmb, before any DM proc
runs, about 13x the file size (the synthetic worlds expand 3-4x). The type
count alone does not explain it (20 k synthetic types cost 15 MB). What
remains is the .dmb's own content: 42 k types' var tables and initial
values, proc bytecode and the string table. Moving sounds out of the .rsc
was **not implemented**: it saves nothing. The next step is to bisect the
.dmb by module (build with large modules' types removed) to find which part
of the compiled code expands.

Fixes, by size:

| Item | Size | Fix |
|---|---|---|
| Compiled world (.dmb load) | ~680 MB | Not sounds or icons (measured). Bisect the .dmb by module; candidates are type var tables and the string table. |
| Atoms (map objects, their vars and lists) | ~245 MB | §3.1 type tables (space turfs 92 MB est.), rule bindings as type tables, interned per-type lists (§0.3). |
| Lighting datums | ~70 MB | §5 option A. |
| Batched spritesheets at round start | 260 MB | Done (smart cache on). |
| Appearances, strings | ~15 MB | Not worth a change now: appearances are already shared by BYOND; string interning is automatic in BYOND. |

### 0.5 What the 680 MB at world load is: per-type proc tables

Bisect (2026-09-27, one measurement each):

| Experiment | Private MB |
|---|---|
| DQ minitest build, at `world/New()` | 667 |
| same, plus 1,000 empty procs on `/datum` (`-DBISECT_EXTRA_PROCS`) | **1,653 (+986)** |
| DQ build with `DEBUG` off (.dmb 48.5 -> 43.1 MB), `no-init` | 528 vs 584 (-56) |
| synthetic 20 k types, 3,000 procs on their parent | 398 |
| same 20 k types, no parent procs | 10 |
| synthetic 20 k types, 400 vars on their parent | 10 (vars are free) |
| synthetic 2,000 procs with 200-line bodies (57.8 MB .dmb) | 73 (bytecode is ~1.3x) |
| synthetic 20 k types with icon, icon_state, colour | 12 (compile-time appearances are small) |
| all sounds stubbed / all .dmi stubbed | unchanged (§0.4) |
| world/New census (minitest) | 5,742 datums, 35,590 atoms: DM data is not it |

BYOND keeps, for every type, a table entry for **every proc the type has,
inherited ones included**: about 23.5 bytes per (type, proc) pair on this
build (1,000 procs x 42,034 types = +986 MB). The 667 MB at world load is
~28 M such pairs: 42 k types with ~670 inherited procs each on average. It is
not bytecode, strings, vars, appearances or resources.

Where the pairs come from: 39.7 k type paths in the source, of which 33.6 k
are leaves and **25.2 k are data-only leaves** (no proc of their own; only var
overrides): 12.4 k `/datum`, 8.0 k `/obj/item`, 1.3 k `/obj/structure`, 0.9 k
`/obj/effect`, 0.8 k `/obj/machinery`, 0.6 k `/area`, 0.6 k `/mob`. An
`/obj/item` type inherits ~1,000 procs (`/datum`, `/atom`, `/atom/movable`,
`/obj`, `/obj/item`), so each costs ~23 KB just by existing.

Proposed fix (not implemented; for approval):

1. **Collapse data-only leaf types into variants** (the existing
   `code/datums/variants/` mechanism): one type per family plus a data table,
   instances created from a variant id. 8 k data-only `/obj/item` leaves at
   ~23 KB each are ~180 MB; the 12.4 k data-only `/datum` leaves (decls,
   recipes, designs, reagents, catalog entries; ~150-300 inherited procs each)
   are ~50-90 MB. Map files reference type paths, so mapped types need a path
   alias in the map loader (or stay types) until maps are migrated.
2. **Shrink the procs every type inherits.** Each proc removed from `/datum`
   saves ~1 MB, from `/atom` ~0.5 MB, from `/obj` or `/obj/item` ~0.2-0.45 MB.
   Candidates: rarely used hooks and debug/admin procs on `/datum` and `/atom`
   (vv_*, stat/debug helpers, legacy compatibility shims) moved to global
   procs or helper datums.
3. **Ship with DEBUG off** in production (-56 MB, and smaller .dmb); keep it
   in test and bench builds for line numbers in runtimes.

Order: 3 is a one-line build change; 2 is mechanical per proc and can be
done incrementally with the count as a ratchet; 1 is the large win and needs
the variant loader and map aliases.

**Done (2026-09-27): fixes 2 and 3.** (1 is not approved.)

- **3, DEBUG off in production.** `deepquarry.dme` and `code/__defines/misc.dm`
  no longer define `DEBUG`; the `dm` target builds without it. `TEST_DEFINES`
  in `tools/build/build.ts` (test and bench builds) and the autowiki build add
  `DEBUG` back, so test runtimes keep file and line. A local debug build of
  the main .dmb is `tools/build/build.sh -DDEBUG`. The custom `world/Error`
  handler (`USE_CUSTOM_ERROR_HANDLER`, `code/_compile_options.dm`) no longer
  depends on `DEBUG`: without file and line it dedupes on the error text plus
  the proc name from the exception's desc (`error_uid()`, `error_where()` in
  `code/modules/error_handler/error_handler.dm`).
  Measured earlier at -56 MB (table above); bench builds keep `DEBUG`, so the
  bench numbers below don't include it.
- **2, procs off the base types.** 33 procs moved to global procs (or deleted
  where nothing called them): 19 on `/datum` (the 12 `tgui_modal_*` helpers,
  `typelist`, `IsAbstract`, `can_vv_mark`, `key_down`, `key_up`,
  `start_coordinated_remoteview`, `dump_harddel_info`), 10 on `/atom`
  (`Admin_Coordinates_Readable`, `Safe_COORD_Location`, `extra_admin_link`,
  `extra_ghost_link`, `vv_auto_rename`, `test_telecomms`, `DrawPixelOn`,
  `laserhit`, `get_ultimate_mob`, `isinspace`), 1 on `/obj`
  (`analyze_gases`, now `analyze_gases_by(tool, target, user)`) and 3 on
  `/mob` (`quest_from_above`, `safe_animal`, `artifact_spawn_debug_tool`).
  Nothing lints procs on base types or global versus type procs; a rarely
  used proc still costs memory per subtype, so prefer a global proc or a
  helper datum when it fits.

  A second pass kept 17 more as global procs (taking the former `src` first),
  all admin, debug, logging or text helpers: `plural_s`, `_search_references`,
  `log_mob_tag`, `log_the_emote`, `format_emote`, `saypiece_scramble`,
  `describe_power`/`_speed`/`_throwpower`/`_penetration`, `examine_tags`,
  `embedded_info`, `GetJobName`, `AddCamoOverlay`, `SkinCmd`,
  `dq_open_languages_panel`, `update_Login_details`. It also deleted the six
  empty `*_act_secondary` tool stubs: secondary (right-click) tool use runs the
  declared interactions for that quality whose default action is Alternate
  (`interaction_tool_act(..., secondary = TRUE)`). Estimated ~11 MB.
  Gameplay API (containment, lifecycle, OM, damage, inventory, movement,
  materials, ...) stays on the type.
  Per-proc value differs by type: a proc on `/datum` or `/atom` is ~1 MB, on
  `/obj` ~0.7 MB, on `/obj/item` ~0.44 MB, on `/mob` only ~0.08 MB (~3.5 k mob
  types).
- **Measured** (bench `boot_profile`, minitest, one boot each, bench build
  with `DEBUG`): private MB at `world/New()` 698.1 before, 666.5 after
  (-31.6); booted 841.3 before, 809.1 after (-32.2).

## 1. Boot profile

### 1.1 Subsystems (clean builds, 3 boots)

| Subsystem | Boot 1 | Boot 2 | Boot 3 | Mean ms | Share |
|---|---|---|---|---|---|
| **Total init** (s) | 145.2 | 112.1 | 104.8 | **120.7 s** | |
| Atoms | 92,051 | 59,213 | 51,084 | 67,449 | 56% |
| Atmospherics | 35,729 | 37,390 | 35,357 | 36,159 | 30% |
| Lighting | 8,276 | 6,666 | 6,077 | 7,006 | 5.8% |
| Assets | 3,378 | 3,257 | 2,583 | 3,073 | 2.5% |
| HoloMiniMaps | 2,200 | 1,827 | 5,512 | 3,180 | 2.6% |
| Wiki | 1,139 | 1,817 | 2,417 | 1,791 | 1.5% |
| Early Assets | 681 | 475 | 368 | 508 | 0.4% |
| Mapping | 474 | 318 | 289 | 360 | |
| Shuttles | 408 | 346 | 320 | 358 | |
| Research | 190 | 153 | 149 | 164 | |

Boot 1 is `boot-perf-clean`, boots 2 and 3 are `boot-perf-clean2`. Everything
else is under 100 ms. Atoms varies most (51–92 s): it is allocation-bound and
the machine was shared. Atmospherics is stable.

### 1.2 Atoms by root (deep profile, mean of 3, instrumented ms)

| Root | Count | Initialize | materialize | Late | Total | Clean-scaled |
|---|---|---|---|---|---|---|
| turf | 393,468 | 43,524 | 14,155 | 2,024 | 59,704 | ~32 s |
| structure | 28,286 | 8,880 | 12,394 | 3,563 | 24,837 | ~13 s |
| machinery | 22,638 | 8,984 | 9,448 | 793 | 19,225 | ~10 s |
| item | 23,327 | 6,751 | 3,842 | 5 | 10,598 | ~6 s |
| effect | 26,854 | 2,628 | 4,827 | 2 | 7,457 | ~4 s |
| other (areas, mobs, screens, misc objs) | 11,411 | 1,222 | 1,072 | 952 | 3,246 | ~2 s |

"materialize" is everything `InitAtom()` does after `Initialize()` returns:
`materialize()` (registries, rules, OM start), the created-on signal and the
ledger note. Times are self times: an atom created inside another's
`Initialize()` counts for its own type only.

Two facts drive the design:

1. **`/turf/space` is 79% of all turfs and a quarter of Atoms.** 310,652
   instances at 96 µs each: 29.7 s instrumented (~16 s clean) for turfs that
   carry no per-instance state at all.
2. **materialize is 36% of the non-turf cost.** A reinforced window spends
   840 µs in materialize against 400 µs in `Initialize()`; a grille 640 µs
   against 90 µs. The proc profile shows where: `dq_rules_on_materialize`
   15.5 s total over 74,103 atoms, of which `/datum/rule_binding/New` 9.7 s
   for 21,759 bindings (450 µs each), and `/proc/REF` 9.1 s self over 171,037
   calls, because the rule-binding registry is keyed by `REF(atom)` text.

### 1.3 Top 40 types by self time (deep profile, mean of 3)

| # | Type | Count | Initialize ms | materialize ms | LateInitialize ms | Self total ms | us/instance |
|---|---|---|---|---|---|---|---|
| 1 | `/turf/space` | 310,652 | 19,138 | 10,549 | 0 | 29,687 | 96 |
| 2 | `/obj/structure/window/reinforced` | 6,705 | 2,682 | 5,648 | 0 | 8,330 | 1,242 |
| 3 | `/turf/simulated/wall/r_wall` | 4,916 | 5,625 | 235 | 41 | 5,901 | 1,200 |
| 4 | `/obj/machinery/door/firedoor/border_only` | 1,436 | 1,315 | 1,309 | 0 | 2,624 | 1,828 |
| 5 | `/turf/simulated/floor/tiled` | 5,795 | 1,783 | 260 | 407 | 2,450 | 423 |
| 6 | `/obj/structure/grille` | 3,115 | 270 | 1,986 | 0 | 2,256 | 724 |
| 7 | `/turf/simulated/sky/moving/north` | 2,895 | 1,948 | 222 | 29 | 2,199 | 759 |
| 8 | `/obj/item/stack/cable_coil` | 1,106 | 576 | 1,245 | 0 | 1,821 | 1,646 |
| 9 | `/turf/simulated/wall` | 1,922 | 1,503 | 89 | 17 | 1,609 | 837 |
| 10 | `/turf/simulated/floor/reinforced/airless` | 9,844 | 930 | 312 | 324 | 1,566 | 159 |
| 11 | `/obj/machinery/light` | 972 | 388 | 1,145 | 0 | 1,532 | 1,576 |
| 12 | `/turf/space/transit/north` | 5,241 | 1,330 | 173 | 0 | 1,503 | 287 |
| 13 | `/obj/structure/disposalpipe/segment` | 1,482 | 146 | 1,326 | 0 | 1,472 | 993 |
| 14 | `/turf/space/transit/east` | 5,831 | 1,172 | 193 | 0 | 1,366 | 234 |
| 15 | `/turf/simulated/floor/plating` | 3,519 | 1,077 | 165 | 102 | 1,344 | 382 |
| 16 | `/obj/structure/catwalk` | 1,002 | 1,240 | 64 | 0 | 1,304 | 1,302 |
| 17 | `/turf/simulated/sky/north` | 2,154 | 932 | 144 | 39 | 1,115 | 517 |
| 18 | `/obj/machinery/door/firedoor/glass` | 518 | 432 | 554 | 0 | 986 | 1,903 |
| 19 | `/turf/simulated/sky/moving/south` | 1,254 | 745 | 102 | 10 | 857 | 684 |
| 20 | `/obj/structure/table/rack` | 370 | 113 | 712 | 0 | 825 | 2,230 |
| 21 | `/obj/machinery/atmospherics/pipe/simple/hidden/supply` | 3,480 | 580 | 245 | 0 | 825 | 237 |
| 22 | `/obj/machinery/power/solar` | 400 | 317 | 496 | 0 | 813 | 2,034 |
| 23 | `/turf/simulated/floor/tiled/white` | 1,726 | 574 | 68 | 114 | 755 | 437 |
| 24 | `/obj/item/clothing/suit/space/void/engineering` | 6 | 747 | 1 | 0 | 747 | 124,567 |
| 25 | `/mob/living/carbon/human/monkey/punpun` | 1 | 741 | 2 | 0 | 743 | 743,290 |
| 26 | `/obj/machinery/alarm` | 443 | 621 | 99 | 0 | 720 | 1,625 |
| 27 | `/obj/machinery/atmospherics/pipe/simple/hidden/scrubbers` | 3,461 | 488 | 209 | 0 | 697 | 201 |
| 28 | `/turf/simulated/floor/tiled/dark` | 2,034 | 499 | 74 | 110 | 684 | 336 |
| 29 | `/obj/structure/table/reinforced` | 252 | 555 | 119 | 0 | 675 | 2,677 |
| 30 | `/obj/structure/cable/green` | 3,121 | 496 | 178 | 0 | 674 | 216 |
| 31 | `/turf/unsimulated/floor` | 6,548 | 432 | 237 | 0 | 670 | 102 |
| 32 | `/obj/effect/wingrille_spawn/reinforced` | 1,244 | 278 | 383 | 0 | 660 | 531 |
| 33 | `/turf/simulated/floor` | 1,686 | 510 | 82 | 57 | 649 | 385 |
| 34 | `/obj/structure/window/reinforced/full` | 139 | 113 | 502 | 0 | 614 | 4,420 |
| 35 | `/obj/structure/closet/crate` | 50 | 25 | 9 | 516 | 550 | 10,998 |
| 36 | `/obj/machinery/light/small` | 319 | 161 | 368 | 0 | 529 | 1,659 |
| 37 | `/obj/machinery/power/apc` | 310 | 163 | 339 | 21 | 523 | 1,686 |
| 38 | `/turf/simulated/sky/south` | 1,254 | 354 | 112 | 57 | 523 | 417 |
| 39 | `/obj/effect/floor_decal/industrial/warning` | 1,234 | 112 | 375 | 0 | 487 | 395 |
| 40 | `/obj/structure/lattice` | 2,914 | 303 | 181 | 0 | 484 | 166 |

Outliers worth a look on their own: the six mapped engineering voidsuits
(125 ms each: helmet, boots, tank and every part's material), Pun Pun (743 ms:
a whole human body plan), crates (11 ms each in `LateInitialize()`: they
gather and ledger their turf's contents one at a time), and medical and
silver airlocks (15–20 ms each in materialize).

### 1.4 Top 40 types by count

| # | Type | Count | Self total ms | us/instance |
|---|---|---|---|---|
| 1 | `/turf/space` | 310,652 | 29,687 | 96 |
| 2 | `/turf/simulated/floor/reinforced/airless` | 9,844 | 1,566 | 159 |
| 3 | `/obj/structure/window/reinforced` | 6,705 | 8,330 | 1,242 |
| 4 | `/turf/unsimulated/floor` | 6,548 | 670 | 102 |
| 5 | `/turf/space/transit/east` | 5,831 | 1,366 | 234 |
| 6 | `/turf/simulated/floor/tiled` | 5,795 | 2,450 | 423 |
| 7 | `/turf/space/transit/north` | 5,241 | 1,503 | 287 |
| 8 | `/turf/simulated/wall/r_wall` | 4,916 | 5,901 | 1,200 |
| 9 | `/turf/unsimulated/wall` | 3,958 | 293 | 74 |
| 10 | `/turf/simulated/floor/plating` | 3,519 | 1,344 | 382 |
| 11 | `/obj/machinery/atmospherics/pipe/simple/hidden/supply` | 3,480 | 825 | 237 |
| 12 | `/obj/machinery/atmospherics/pipe/simple/hidden/scrubbers` | 3,461 | 697 | 201 |
| 13 | `/atom/movable/screen/plane_master` | 3,192 | 141 | 44 |
| 14 | `/obj/structure/cable/green` | 3,121 | 674 | 216 |
| 15 | `/obj/structure/grille` | 3,115 | 2,256 | 724 |
| 16 | `/obj/structure/lattice` | 2,914 | 484 | 166 |
| 17 | `/atom/movable/emissive_blocker` | 2,912 | 214 | 73 |
| 18 | `/turf/simulated/sky/moving/north` | 2,895 | 2,199 | 759 |
| 19 | `/obj/effect/step_trigger/teleporter/random` | 2,403 | 135 | 56 |
| 20 | `/turf/simulated/sky/north` | 2,154 | 1,115 | 517 |
| 21 | `/obj/effect/step_trigger/thrower` | 2,040 | 120 | 59 |
| 22 | `/turf/simulated/floor/tiled/dark` | 2,034 | 684 | 336 |
| 23 | `/turf/simulated/wall` | 1,922 | 1,609 | 837 |
| 24 | `/turf/simulated/floor/tiled/white` | 1,726 | 755 | 437 |
| 25 | `/turf/simulated/floor` | 1,686 | 649 | 385 |
| 26 | `/turf/simulated/sky/moving/west` | 1,617 | 427 | 264 |
| 27 | `/turf/simulated/sky/west` | 1,617 | 428 | 265 |
| 28 | `/obj/effect/decal/cleanable/dirt` | 1,602 | 287 | 179 |
| 29 | `/obj/structure/cable` | 1,538 | 374 | 243 |
| 30 | `/obj/structure/disposalpipe/segment` | 1,482 | 1,472 | 993 |
| 31 | `/turf/unsimulated/wall/planetary/sif/alt` | 1,460 | 125 | 86 |
| 32 | `/obj/machinery/door/firedoor/border_only` | 1,436 | 2,624 | 1,828 |
| 33 | `/obj/effect/step_trigger/teleporter/landmark` | 1,428 | 84 | 59 |
| 34 | `/turf/simulated/sky/moving/south` | 1,254 | 857 | 684 |
| 35 | `/turf/simulated/sky/south` | 1,254 | 523 | 417 |
| 36 | `/obj/effect/wingrille_spawn/reinforced` | 1,244 | 660 | 531 |
| 37 | `/obj/effect/floor_decal/industrial/warning` | 1,234 | 487 | 395 |
| 38 | `/obj/structure/cable/yellow` | 1,215 | 310 | 256 |
| 39 | `/obj/effect/floor_decal/borderfloorblack` | 1,159 | 431 | 372 |
| 40 | `/obj/item/stack/cable_coil` | 1,106 | 1,821 | 1,646 |

### 1.5 Turf init

Turfs cost 59.7 s instrumented (~32 s clean). From the proc profile of the
same boots (instrumented seconds):

| Proc | Total | Self | Calls |
|---|---|---|---|
| `/turf/open/Initialize` | 13.97 | 1.63 | 379,823 |
| `/turf/space/Initialize` | 12.43 | 2.98 | 322,474 |
| `/turf/Initialize` | 10.95 | 2.38 | 393,468 |
| `/proc/dq_property` (material and property lookups) | 6.92 | 1.66 | 324,045 |
| `/atom/proc/add_overlay` | 5.51 | 4.50 | 320,220 |
| `/turf/simulated/wall/Initialize` | 4.99 | 0.12 | 7,261 |
| `/turf/simulated/wall/proc/update_material` | 4.12 | 0.24 | 7,261 |
| `/turf/Entered` (contents re-entered in `Initialize()`) | 3.92 | 0.25 | 64,378 |
| `/turf/simulated/wall/proc/update_connections` | 2.60 | 0.44 | 17,279 |
| `/turf/proc/set_luminosity` | 2.19 | 1.99 | 454,100 |
| `/turf/open/air_block_mask` | 1.99 | 1.43 | 379,870 |
| `SSair.parse_gas_string` | 1.61 | 1.04 | 369,704 |
| `GetAbove` + `GetBelow` + `multiz_turf_new` | 2.7 | 1.66 | ~1.1 M |

Every turf, including every space turf, runs the whole chain: a property
lookup, `add_overlay` (320,220 calls, nearly one per space turf), luminosity,
multi-z neighbour notifications and, for open turfs, a gas string parse and an
air block mask. None of that differs between two space turfs. Walls pay for
material resolution and neighbour smoothing: 17,279 `update_connections`
calls for 7,261 walls, because each wall re-smooths its neighbours.

### 1.6 Atmos init (36 s)

| Proc | Total s | Self s | Calls |
|---|---|---|---|
| `SSair.setup_atmos_machinery` | 30.12 | 0.04 | 1 |
| `SSair.setup_rust_pipenets` | 28.27 | **26.69** | 1 |
| `SSair.setup_allturfs` | 7.38 | 2.07 | 1 |
| `heat_register_turfs` | 2.07 | 1.24 | 47 |
| `vg_hook_register_turfs_bulk` | 1.29 | 1.29 | 47 |

`setup_rust_pipenets()` (`code/ATMOSPHERICS/rust_pipenets.dm`) is 74% of
atmos init, all DM self time, in one call. It builds the topology transaction
as one text string with `operations += rust_pipe_operation(...)` for every
port and every edge, so each append copies the whole string: quadratic in the
number of pipe ports. The Rust side (`vg_pipenet_topology_batch`) is not in
the top 100. Building a list and joining it once (or passing the list) should
remove ~26 s. It is not a design question; it is the cheapest win in the boot.

Turf registration with Rust is already batched (47 bulk calls for 393 k
turfs). The remaining `setup_allturfs()` DM time is the per-turf walk that
builds those batches, which goes away when the map-load chunk builds them
(§3.3).

### 1.7 Lighting init (7 s)

After boot: 29,904 lighting objects (one per dynamically lit turf, each with
its own `mutable_appearance` underlay), 47,197 lighting corners, 15,893 light
sources.

| Proc | Total s | Self s | Calls |
|---|---|---|---|
| `SSlighting.Initialize` | 8.49 | 0.09 | 1 |
| `SSlighting.fire` (init pass) | 6.93 | 0.24 | 475 |
| `/datum/light_source/proc/update_corners` | 4.49 | 3.21 | 15,975 |
| `/datum/lighting_object/proc/update` | 1.93 | 1.20 | 30,728 |
| `create_all_lighting_objects` | 1.63 | 0.43 | 1 |
| `/datum/lighting_corner/proc/update_lumcount` | 0.57 | 0.54 | 534,250 |

Inside Atoms, lighting adds `set_luminosity` 2.19 s (every turf) and
`/atom/proc/update_light` 0.84 s (111,301 calls, most of them no-ops). The
init pass also sleeps inside its loops (`init_tick_checks`), so its wall time
is longer than its work.

### 1.8 Non-map boot costs

| Subsystem | Mean | What it does | Cheapest fix |
|---|---|---|---|
| Assets | 3.1 s | Instantiates every `/datum/asset` and spritesheet; `icon_ref_map` 0.73 s, `md5filepath` 0.61 s | Ship `CACHE_ASSETS` on (it is commented out in `config/example/resources.txt`) so spritesheets load from `data/spritesheets` across boots. Fix `/datum/asset/spritesheet/should_refresh()`: its `var/static/should_refresh` is **one static shared by every spritesheet**, so the first sheet's cache check decides for all. Key the cache on a hash of the icon files and the code revision. |
| HoloMiniMaps | 3.2 s (1.8–5.5) | Renders a PNG per z-level (`render_holomap_png` 2.05 s self) | Cache the PNGs under `data/` keyed by the map files' hash (the map doesn't change between boots), or render on the first station map viewed. |
| Wiki | 1.8 s | Builds every page's data up front (`assemble_reaction_data` 1.04 s for 669 reactions; seeds, genes, lore) | Lazy: build a category on its first page view. The data is static per build, so it can also be cached like assets. |
| Early Assets | 0.5 s | Preference-menu assets needed before Atoms | Covered by the asset cache. |

About 8.5 s together, all removable without touching map load.

## 2. Explosion profile

`explosion(center, 7, 14, 21)` on the Brig block. Wall time runs from
detonation to the explosion subsystem going idle.

| Metric | Clean A | Clean B | Phases A | Phases B | Profile |
|---|---|---|---|---|---|
| Resolve wall time (ms) | 15,969 | 15,769 | 47,069 | 37,088 | 17,881 |
| Explosions subsystem main-thread ms | 5,214 | 5,067 | | | |
| Prepare (flood fill) ms | 60.5 | 60.6 | | | |
| Turf resolve (`ex_act` on turfs) ms | 640 | 616 | 942 | 842 | |
| Atom collect ms | 32.8 | 31.4 | | | |
| Atom resolve (blast packets) ms | 7,289 | 7,161 | 11,703 | 9,816 | 8,221 |
| Turfs / atoms resolved | 1,926 / 4,011 | 1,926 / 3,982 | | | |
| qdels | 9,853 | 9,844 | 10,394 | 9,965 | |
| FFI calls in window | 38,874 | 39,620 | | | 40,426 |
| Tick overruns | 50 | 50 | | | |

The first clean run picked a different site (Engineering Foyer, 895 machines,
mostly pipes, before the site score excluded pipes and cables): 21.5 s wall,
10.1 s atom resolve, 999 ms turf resolve, 16,821 qdels, 61,895 FFI calls.

The phase runs carry per-qdel bookkeeping and the profile run carries the
profiler, so their wall times are longer; use them for the splits only. The
explosion subsystem is tick-budgeted, so wall time (16 s) is about three times
its main-thread work (5.1 s), and the window still overran 50 ticks.

### 2.1 Where the blast time goes (profile run, seconds)

| Bucket | Seconds | Evidence |
|---|---|---|
| **Contract damage reporting** | **5.17** | `contract_report_station_damage` 5.17 total under 4,307 `take_damage` calls; `/datum/contract_opportunity_window/proc/signal_snapshot` 3.46 s **self** for 2,343 calls (1.5 ms each), `prune` 0.29, `revise` 0.41 |
| Destroy (every qdel) | 1.14 | `qdel` total; phases in §2.2 |
| Lighting | 1.07 | `SSlighting.fire`: `lighting_object/update` 0.48 (6,385), `update_corners` 0.47 (815 sources) |
| Rules re-evaluation | 0.80 | `rule_binding/evaluate` (2,754 calls), `dq_rules_settle` 0.55 |
| Messages | 0.71 | `visible_message`, 319 calls at 2.2 ms (`get_mobs_and_objs_in_view_fast`) |
| Turf changes | ~0.9 | floor `ex_act` 0.34 + wall `ex_act` 0.32; `ChangeTurf` 0.23 (270 calls); smoothing `update_connections` 0.09 + wall `update_icon` 0.21; deferred flush 0.11 |
| Atmos | 0.73 | SSair fire; the blast's pipe topology commit is 0.15 (6 batches) |
| Contents spill moves | ~0.18 | `Move` 0.14 (997 calls), `doMove` 0.04 (896) |
| Rust calls | ~1.0 | ~40 k FFI calls in the window; `vg_gas_tick` 0.40 and `vg_react_step` 0.36 are the routine atmos frame, not the blast |

The blast's cost is dominated by one gameplay hook, not by destruction
mechanics: contracts snapshot every open opportunity window on every damaged
object. Reporting once per explosion epoch instead of once per `take_damage`
is worth more than everything else in this section combined. Of the 1,926
turfs the blast resolved, only 270 changed type; `ChangeTurf` itself is
cheap here because the explosion subsystem already defers appearance and
lighting updates per epoch.

### 2.2 Destroy phases (lifecycle.md §2), exclusive ms, 2 runs

| Phase | Run A | Run B | Mean |
|---|---|---|---|
| 0 guard (incl. `COMSIG_QDELETING` handlers) | 134 | 76 | 105 |
| 0.5 mind | 5.8 | 3.8 | 4.8 |
| 1 unbind | 2.5 | 2.4 | 2.4 |
| 2 dematerialize | 1.5 | 3.3 | 2.4 |
| 3 contents | 24 | 34 | 29 |
| 4 links | 260 | 109 | 184 |
| 5 teardown | 39 | 39 | 39 |
| 6 effects | 33 | 34 | 33 |
| 7 leftover `Destroy()` | 556 | 555 | 556 |
| 8 scrub | 58 | 47 | 53 |
| **Total** | 1,115 | 904 | **1,009 ms for ~10.2 k qdels** |

Top qdel self time: `/datum/contract_event` (2,250 qdels, 200–220 ms),
`/datum/contract_opportunity_observation` (2,190, 170–190 ms),
`/datum/material_service` (773, 115–130 ms), sparks (315, 81–85 ms),
`/datum/timedevent` (1,150, 80 ms), walls (110, 26–29 ms), lighting corners
(370, 23–27 ms), turf gas mixtures (350–370, 23–26 ms). Half of the qdels are
bookkeeping datums the explosion itself created (contract events, timers,
sparks), not the objects it destroyed.

## 3. Declarative, lazy Initialize

### 3.1 Type tables, built once per type

A `/datum/type_table` per concrete type, built on first use (or ahead of time
for mapped types, at map-load start) from vars and declarations:

- appearance: icon, icon_state, overlays list, plane and layer per state
  (§3.5);
- turf facts: luminosity, `directional_opacity`, `movement_cost`/`path_weight`,
  `uses_integrity` and max integrity, initial gas (the parsed `initial_gas_mix`
  as one Rust gas template id, not a string per turf), air block mask,
  explosion resistance, material (resolved once: `update_material` is 4.1 s
  today for 7,261 walls of four materials);
- registries, rules, OM decls, processing subsystem: the flags that today are
  looked up per instance (`dq_rules_for_type`, `om_type_has_decl`,
  `type_registries`: 1.7 s of lookups over 488 k materializes);
- smoothing group and connection rules.

`Initialize()` then does only what differs between two instances of the type:
a var set on the map, a random pick, contents the mapper placed. A type whose
table says "nothing per instance" (every `/turf/space`, every unsimulated turf,
floor decals, step triggers, emissive blockers) skips `Initialize()` entirely:
`InitAtom()` sets `ATOM_INITIALIZED` and applies the table.

Space is the proof case. `/turf/space` needs: an appearance keyed by
(x + y) parallax state (one of a few cached appearances), luminosity from
the table, no air (shared immutable vacuum), no overlays of its own. That is
two var writes per turf instead of a 96 µs chain.

### 3.2 Initialize limited to per-instance state

The rule the lint enforces (§3.6): an `Initialize()` override may only touch
the instance's own vars and its own contents. Anything that reads or writes
neighbours, globals or subsystems is either table data (§3.1), registration
(§3.3) or deferred (§3.4). Today's offenders by cost: wall and window
smoothing (`update_connections`, `wingrille_spawn/activate` 13.2 s total),
turfs re-entering their contents (`/turf/Entered` 3.9 s, 64 k calls: the map
loader already placed them), multi-z neighbour notifications
(`multiz_turf_new` on every turf), crates ledgering their turf's contents.

### 3.3 on_materialize registration batched per map-load chunk

The map loader already works in chunks (a z-level, a template, an expedition
site). Instead of `materialize()` per atom:

1. Initialize the chunk (only instances whose table requires it).
2. **Bulk registries.** Group the chunk's atoms by type; for each type append
   the whole group to each registry the table names (one list append per
   type per registry, not one `join_registries()` per atom).
3. **Rules and OM.** One binding table per type and chunk: the rule subscriptions
   are the same for every instance of a type, so subscribe the group to each
   reactor key once and store per-instance state in a flat list indexed by
   the atom's slot. Key bindings by the atom (a var on it, or the OM record),
   never by `REF()` text: `REF` alone was 9.1 s of boot.
4. **One Rust bind call per chunk** for everything that needs a core entity:
   turf cells (already bulk), heat bodies, pipe ports and edges (today's
   string transaction becomes the chunk's list), power nodes.
   *Status (rewrite/l-boot2):* cables queue during an SSatoms batch
   (`SSatoms.deferred_cable_binds`) and bind in one `vg_power_bind_cable_list`
   call when it ends; `setup_rust_pipenets()` sends every port in one
   `vg_pipe_upsert_list` and every edge in one `vg_pipe_connect_list`. Heat
   bodies stay per atom (created lazily; callers use the handle at once);
   machine power nodes stay per machine (bound in `on_materialize()`, some
   with an immediate region read).
5. **One lighting pass per chunk** (§5): sources registered in bulk, one
   propagation over the chunk, one batch of overlay writes.
6. Smoothing once per chunk (§4.2).

`LateInitialize()` becomes the chunk's post-pass, and most of it disappears:
what it does today (APCs finding their area, crates collecting contents) is
chunk-level work that the chunk already has in hand.

### 3.3a Chunked materialize (track 4d, built on rewrite/boot-init)

Every `SSatoms.InitializeAtoms()` call is one `/datum/materialize_batch` frame
(`code/controllers/subsystems/atoms_batch.dm`). The frame initializes its atoms
in chunks of `MATERIALIZE_CHUNK_SIZE` (512) and may yield to the MC only between
two chunks (`batch_yield_point()`: when clients are connected and the tick is
spent; never in unit-test builds unless a test sets `batch_yield_probe`). Each
atom still materializes right after its own Initialize(), so registrations keep
their old timing.

Deferred work is generic: a caller queues with
`SSatoms.batch_defer(BATCH_WORK_<kind>, thing)` (FALSE when no frame runs, so
the caller does the work at once) and drops it with `batch_undefer()`.
`flush_batch_work()` runs each kind once when the owning frame closes, in
`BATCH_WORK_*` order. Today the kinds are wall smoothing and cable binds; a new
per-batch bulk bind adds a define and a `switch` case.

Ordering rules the frames keep (the unit tests in
`dq_materialize_batch_tests.dm` check each):

1. Atoms initialize in the caller's order (areas, turfs, then movables for a
   template). A yield never reorders or skips one.
2. A frame's LateInitialize() calls run after every atom of that frame has
   initialized.
3. Deferred work flushes once, when its owner closes, before that frame's
   LateInitialize() calls (walls, then cables).
4. A frame opened while another runs (a nested call from inside a running
   batch) joins it: its deferred work goes to the running frame's owner, as the
   old shared lists did. Its own late loaders run when it closes.
5. While a frame sleeps at a yield no frame is active. Atoms other code
   creates meanwhile initialize and bind at once instead of queueing into the
   sleeping frame (the old lists stayed set across `stoplag()`), and a frame
   opened meanwhile owns its own work.

Boot air registration (`SSair.setup_allturfs()`) is unchanged: it registers
every turf in 8192-turf bulk calls after SSatoms. Folding it into the frames
(sec 6 row 8) is a new `BATCH_WORK_*` kind once runtime template turfs register
through it too.

### 3.4 Interaction-only setup deferred to first use

Setup that matters only when someone interacts: storage UI state, radio
channel lists and filters (`send_to_filter` and `remove_listener` are 1.7 s
at boot), machine part ratings (`default_apply_parts` + `get_part_rating`
4.4 s total for 900 machines), wiki and techweb data, holomap images. Build
on first use behind an accessor; `latent` already does this for contents and
should cover these too.

### 3.5 Appearance caching per type and state

`add_overlay` is 5.5 s at boot and `build_appearance_list` 1.0 s, nearly all
on turfs whose overlays are identical per type and state. Cache the final
`appearance` (the mutable_appearance with overlays baked) per (type, state
key) in the type table and assign it with one `appearance =` write. Walls and
windows key on (type, material, connection bits); floors on (type, broken,
burnt, decal set).

### 3.6 Ratchet lint on Initialize overrides

**Built (k-boot):** `tools/ci/init_lint.py`, run by `check_ratchets.sh`, with
ceilings in `tools/ci/init_baseline.txt`: `initialize` (3,325 overrides),
`late_initialize` (95), `unreasoned` (overrides without `// INIT: <reason>`,
3,420), `world_reads` (`range(`/`orange(`/`view(`/`GetAbove`/`GetBelow`/`GLOB.`/
`START_PROCESSING` inside an `Initialize()` body, 312) and
`turf_on_materialize` (0). All may fall, never rise. The first type table is
`atom_type_table()` (`code/game/atom/atom_type_table.dm`): one cached row per
type saying whether materialize must join registries, subscribe rules or start
OM. `on_materialize()`/`on_dematerialize()` read it, and `InitAtom()` flags a
turf whose row needs none of the three as materialized without the call chain
(hence the zero ceiling on turf `on_materialize()` overrides). Space turfs pick
their dust appearance from a flat index and share one immutable-air lookup;
`/turf/Initialize` checks multi-z neighbours without `GetAbove`/`GetBelow`.
**l-boot2:**
- **Skipping Initialize.** A type that sets `init_from_table = TRUE` has no
  per-instance `Initialize()` state. `InitAtom()` calls its
  `table_initialize()` instead of the Initialize chain and its arglist.
  - `/turf/space` and plain `/turf/unsimulated` use it. The subtypes that
    override Initialize turn the flag off.
  - The lint's `table_init_overrides` count (ceiling 0) catches a subtype
    that forgets to.
- **Forwarding overrides removed.** 41 overrides whose body was only
  `. = ..()` were deleted. The ceilings are now `initialize` 3284 and
  `unreasoned` 3379.
- **Air template per type.** `create_gas_mixture()` copies one mixture per
  type when the turf's gas string and temperature are its type's.
- **Walls.**
  - Material facts come from one table per (material, reinforcement,
    temperature): `wall_material_facts()`.
  - Overlay images come from one shared list per (masks, materials,
    connections, construction stage, damage step): `wall_overlay_images()`.
- **Rule bindings.** One shared `/datum/rule_type_table` per rule list.
  Per-object state is three bitmasks plus one flat token list.

**boot-init:**
- **Initialize-free obj types.** `/atom/movable`, `/obj`, `/obj/effect` and
  `/obj/structure` keep their Initialize() work in shared setup procs that
  `table_initialize()` also runs. `tools/ci/init_table_candidates.py` finds
  every effect or structure type whose whole Initialize chain is one of those
  (no override on it, its subtypes, or any other ancestor) and generates
  `code/game/atom/init_from_table_types.dm`: 295 types, 822 with subtypes
  (signs, props, decals, overlays, step triggers, salvage, ...). Rerun it with
  `--write` after adding or removing overrides; the lint's
  `table_init_overrides` ceiling of 0 catches a listed type that gains one.
- No forwarding-only overrides were left to delete (k-boot removed them).
  Converting Initialize() bodies into declarations (starting reagents,
  appearance tables, owned children) belongs to the declarative-lifecycle wave.

Not done:
- Appearance caches for floors and windows.
- Material facts for anything but walls.

`tools/ci/check_grep.sh` gets a count of `/Initialize(` overrides (and
separately of `/LateInitialize(`), with the baseline in the ratchet file.
New overrides must carry `// INIT: <reason>` naming the per-instance state
they set; the count may only go down as types move to tables. A second rule
flags `range(`, `orange(`, `GetAbove`, `GetBelow`, `GLOB.` and
`START_PROCESSING` inside an `Initialize()` body.

## 4. Turf changes and batched destroy

### 4.1 Turf type swap as data

`ChangeTurf()` today deletes the turf datum and runs `new N()` (the full
`Initialize()` chain), then copies lighting, air and sunlight state back. With
type tables, a turf change is a data swap:

- the new type's declared state (appearance, opacity, luminosity, air
  template, integrity, material, flags) comes from its table;
- only instance state the old turf carried and the new one keeps (air
  contents, lighting corners, sunlight handler, decals that survive) is
  carried over, as today;
- the full `Initialize()` runs only when the new type's table says it has
  per-instance setup.

For explosions, `ChangeTurf` was 0.23 s for 270 changes, so the win there is
small; it matters for construction, shuttles and expedition site release,
where thousands of turfs change at once.

### 4.2 Batched neighbour smoothing

Collect every changed turf in the batch (a map-load chunk, an explosion epoch,
a shuttle move); compute the set of turfs whose connection bits can change
(changed turfs plus neighbours, deduplicated); recompute each once and write
its cached appearance (§3.5). Today each wall re-smooths its neighbours
(17,279 `update_connections` for 7,261 walls at boot). The explosion subsystem
already does this for appearances (`deferred_appearance_updates`); the same
deferral belongs in the map loader and in `ChangeTurf` under any batch.

**Built for walls (k-boot):** inside `SSatoms.InitializeAtoms()` a wall's
`update_material()` and integrity change queue it in
`SSatoms.deferred_wall_smoothing` instead of smoothing it and its neighbours;
`flush_wall_smoothing()` smooths each queued wall and its wall neighbours once
after the batch's atoms are initialized, before `LateInitialize()`. Windows,
low walls, tables and catwalks still propagate per object.

### 4.3 One Rust field write per batch

Turf changes that alter gas or heat geometry (open/closed, blocks air, heat
capacity) are queued as one field command list per batch and committed once,
as power already does for explosions (`power_batch_begin`/`end`). Pipe
topology already batches per epoch (6 commits for this blast).

### 4.4 Batched destroy

lifecycle.md §2's phases, run across a doomed set instead of per object:

1. **Mark first.** Collect the whole doomed set (the explosion epoch's
   destroyed atoms and every atom they transitively contain) and set
   `gc_destroyed` on all of them before any phase runs. Every
   `QDELETED()` check in every handler now sees the final state.
2. **Contents that land somewhere doomed are deleted without moving.** Phase 3
   resolves SPILL and TRANSFER destinations; if the destination is doomed,
   the child is simply part of the set. Today a window's shards spill onto a
   floor that is about to be destroyed; in the brig blast the spills cost
   ~0.2 s of `Move`, and each move fires `Entered`/`Exited` chains.
3. **Edges between doomed atoms are dropped without bookkeeping.** Phase 4
   (links, 184 ms here) nulls pair partners and removes back-list
   memberships; when both ends are doomed, neither side's lists need
   updating. The same holds for relations, ledgers and registry memberships:
   remove the whole doomed set from each registry in one pass per registry
   (`list -= doomed_list`), not one removal per object.
4. **One Rust unbind call** for the set's entity bindings, heat bodies, pipe
   ports and power nodes.
5. **Per-turf effects.** Phase 6 effects (debris, sparks, messages, sounds)
   are aggregated per turf or per epoch: one debris roll and one message per
   turf, not per object. The brig blast created 315 sparks and 76 particle
   effects and sent 319 `visible_message`s (0.7 s).
6. **Domain hooks per set.** Contract reporting (§2.1, 5.2 s) and material
   service cleanup get one call per set with the list, not one per object.

The measured destroy transaction is 1.0 s for 10.2 k qdels; batching the
phases saves most of guard, links and scrub (~0.35 s) and the moves (~0.2 s).
The large win is the domain hooks in step 6 (~5 s).

**Status (rewrite/k-boot).** Implemented in `code/datums/lifecycle/batch.dm`:
`qdel_batch()` and the collecting scope (`dq_destroy_collect_begin()`/`_end()`,
used by explosion blast delivery, `gib()`, `death` and shuttle crush) do
steps 1-3 (mark first with `GC_BATCH_DOOMED`, contents bound for a doomed
destination are deleted unmoved, links to doomed ends dropped without
back-list bookkeeping), step 4 for entity handles (`vg_entity_unbind_list()`)
and SSvg's bound list, the one pass per registry (`registry_leaves` ->
`remove_many()`), and step 5 for declared `destroy_effects()` (one per turf,
neighbour updates once per turf). Step 6: contract damage reporting batches
per atom and flushes once (`code/modules/contracts/damage_batch.dm`); the
explosion epoch opens that batch, and now every collecting scope does too,
so gibs and shuttle crushes are covered. `dq_destroy_effects_once(atom)` is
the per-turf gate for cosmetic effects outside `destroy_effects()`: machinery
destruction sparks and sound, catwalk and railing break messages use it.

Heat bodies, pipe ports and power nodes now release in one call each per
batch too (`dq_heat_body_release()`, `dq_pipe_port_remove()`,
`dq_power_unbind_node()` queue into the batch; `vg_heat_body_release_list`,
`vg_pipe_remove_list`, `vg_power_unbind_node_list`), and the pipe topology
commits once per batch after the removal (rewrite/l-boot2).

Material service cleanup is per set (rewrite/boot-bind): a service whose
owner is doomed skips its per-hook `om_unhook`s (its own OM teardown drops
them; `om_teardown_hooks()` also skips per-hook bookkeeping on a doomed
source, and `om_deliver()` never calls a listener whose OM state is torn
down) and queues its watch key; the batch flush disarms the whole set's gas
watches with `om_watch_disarm_keys()`: one registry `-=`, one `-=` per
mixture index and one republish per touched mixture.

Remaining: other `atom_destruction()`
messages (material weapons and armour, mob spawners, grave markers,
expedition structures) can adopt `dq_destroy_effects_once()` the same way.

### 4.5 Shared appearance and material caches (rewrite/boot-bind)

Walls already shared `wall_material_facts()` and `wall_overlay_images()`.
Floors now share their edge and inner-corner overlay lists per (flooring,
border bits, corner bits) (`/datum/decl/flooring/proc/get_edge_overlays()`),
full-tile windows share theirs per (icon, basestate, connections, damage
step, layer) (`window_overlay_images()`), and
`/datum/material/proc/material_radiation_transmission()` is cached per
material and thickness, so window, girder, door, wall and item shielding is
worked out once per material (`material_facts_changed()` drops the cache).

### 4.6 Bulk binds (rewrite/boot-bind)

Callers use a heat body's handle as soon as `create_heat_body()` returns, so
a batch cannot simply defer creation. Inside a bind scope
(`dq_heat_bind_begin()`/`_end()`, opened by `SSatoms.InitializeAtoms()`),
`create_heat_body()` takes a pre-reserved handle from a pool filled by one
`heat_body_reserve(n)` call: a live, kept, inert Rust body, so every write
works at once. The real configuration is queued and sent for the whole scope
in one `heat_body_configure_list()` call. Invariants (Rust tests in
`verdigris/ffi/src/heat.rs`, DM tests in `dq_boot_bind_tests.dm`): the
configure never undoes a write made in between (temperature, slot 0
coupling, keep, added heat); a pending body is configured before any DM read
(`HEAT_BODY_RESOLVE`); a body released while pending leaves the queue and a
stale handle is never configured; unused pool handles are released when the
outermost scope ends.

Power machine nodes need no reservation (the handle is the machine's own
`vg_entity`): during a map-load batch `connect_to_network(FALSE)` queues the
machine, and `SSatoms.flush_machine_binds()` binds them all in one
`vg_power_bind_machine_list()` edit after the batch's cables, then runs each
machine's `power_node_sent()` (supply, `power_registered()`).

## 5. Lighting

Today (TG-style): each light source walks the turfs in range, and updates four
corner datums per lit turf; each dynamically lit turf has a lighting-object
datum whose `mutable_appearance` underlay is rebuilt when a corner changes.
Occlusion is BYOND's own view through `luminosity` tricks
(`get_turfs_in_range`), so light stops at opaque turfs per source. On Southern
Cross: 15,893 sources, 47,197 corners, 29,904 lighting objects; 7 s at boot,
1.1 s in the brig blast.

### Option A: light propagation as a Rust core grid field

A light field in the core, like heat: per-turf RGB, sources as bodies with
position, range, power and colour. Propagation is a bounded flood/shadowcast
per dirty source on the core's worker threads, using the opacity bits the core
already has for gas geometry (walls, doors, windows) and directional opacity.
The field publishes a dirty-turf list per frame; DM applies only those turfs'
overlays, in batches, from a small set of cached appearances (quantised
colour and intensity per corner).

- Accuracy: wall occlusion is exact per turf and per source, as now; soft
  corners come from sampling the four corner values in the field. Same look.
- CPU: DM work becomes "apply N dirty overlays"; propagation moves off the
  main thread. Boot: one bulk source registration per chunk and one field
  solve; the 4.5 s of `update_corners` and 1.9 s of object updates leave DM.
- Memory: corners and lighting objects stop being DM datums (47 k + 30 k
  datums with lists and an appearance each); the field is a few bytes per
  turf in Rust (393 k turfs x RGB x 4 corners as u8 ≈ 5 MB). But it adds to
  the Rust heap that is already the process's memory ceiling (§0.1).
- Atom counts: no change to atoms (lighting objects are already datums with
  underlays); removes ~77 k datums.

### Option B: client-rendered lighting

Lights as emissive or plane-based overlays: each source carries a light
sprite (a radial gradient) on a lighting plane; the lighting plane master
multiplies it over the game plane; walls draw an emissive blocker mask.

- Accuracy: occlusion is the problem. A radial sprite passes through walls;
  masking it needs per-source shadow geometry (per-wall shadow overlays or
  per-turf occluders on the lighting plane), which reintroduces per-turf
  objects, or accepts light bleeding through walls. For a station game where
  darkness behind a wall matters (maintenance, breaches, the brig), that is a
  visible regression.
- CPU: near-zero server cost for static lights; clients pay per-frame
  blending (fine on modern clients, but BYOND's renderer is CPU-side and
  large planes with many overlays cost frame time for low-end players).
- Memory: one overlay per source instead of per-turf state; the least server
  memory of the three.
- Atom counts: one overlay per source (~16 k) plus shadow casters if
  occlusion is wanted.
- Gameplay reads of light (`get_lumcount` for darkness checks, shadowlings,
  plants, cameras) lose their server-side data and need a separate estimate.

### Recommendation: A

Keep server-side light values (gameplay reads them), keep exact wall
occlusion, and move the propagation to the core where the opacity grid
already lives. DM keeps only the batched overlay writes. Do it after §0.1's
memory fix, and size the field as u8 per corner channel. B is worth keeping
for purely cosmetic light (emissive glows, screens), which already uses
emissives.

## 6. Estimates

Savings scaled to the clean boot (mean 120.7 s). Items overlap a little
(appearance caching also speeds walls); the total is not additive to the
second.

| # | Item | Evidence | Saves (boot) | Saves (brig blast) |
|---|---|---|---|---|
| 0 | Memory headroom: bring the Rust boot peak (1.85 GB) down, or move to a 64-bit server | 15 of 21 explosion boots died, most on Rust allocation | — (correctness) | — |
| 1 | `setup_rust_pipenets` list join instead of string `+=` | 26.7 s self, one call | **~26 s** | — |
| 2 | Space and other no-state turfs skip `Initialize()` (type tables, §3.1) | `/turf/space` 29.7 s instrumented, 96 µs x 310,652; transit, sky and unsimulated add ~8 s | **~18 s** | — |
| 3 | Rules and registries bound per type and chunk, keyed without `REF` (§3.3) | rules 15.5 s + `REF` 9.1 s instrumented | **~9 s** | ~0.8 s (rules settle) |
| 4 | Turf init as table data: air template, luminosity, material, multi-z (§3.1) | `/turf/open/Initialize` 14 s, `update_material` 4.1 s, multi-z 2.7 s, instrumented | **~8 s** | small |
| 5 | Appearance caching and batched smoothing (§3.5, §4.2) | `add_overlay` 5.5 s, wingrille/windows/walls ~13 s, instrumented | **~6 s** | ~0.3 s |
| 6 | Non-map caches: assets, holomaps, wiki (§1.8) | 8.5 s measured | **~7 s** | — |
| 7 | Lighting as a core field (§5, option A) | 7 s SSlighting + 3 s in Atoms | **~7 s** | ~1 s |
| 8 | `setup_allturfs` walk folded into chunk bind | 2 s self | ~2 s | — |
| 9 | Batched destroy with per-set domain hooks (§4.4) | contracts 5.2 s, destroy 1.0 s, messages 0.7 s | — | **~6 s** |
| 10 | Interaction-only setup deferred (§3.4) | parts 4.4 s, radio 1.7 s instrumented | ~3 s | — |

With 1–8 and 10, boot goes from ~121 s to roughly **35–45 s**; items 1, 2
and 6 alone get it under 75 s. The brig blast's main-thread work goes from
~14 s to ~6 s (and its tick overruns with it).

## 7. Order

1. **Item 1** (pipenet string join): one proc, no design, 26 s. Measure with
   `bench --scenario=boot_profile`.
2. **Item 0** (memory): the explosion scenario is unreliable until it is fixed,
   and it is the live map's ceiling. Find what peaks at 1.85 GB during boot
   (the `rust_*_mb` phase metrics in `boot_profile` give the tags).
3. **Item 6** (asset, holomap, wiki caches) and the `should_refresh` static
   bug: independent of the rewrite, small.
4. **Item 9's contract hook** (report per epoch): 5 s off every big explosion;
   the rest of batched destroy follows the lifecycle sweep (Phase 2b).
5. **Type tables** (items 2, 4, 5): the table builder, then space and
   unsimulated turfs, then open turfs, then walls and windows with smoothing.
   Add the ratchet lint (§3.6) with the first table.
6. **Chunked materialize** (items 3, 8): lands with LC-refs part 1 (Phase 1c)
   because it replaces `REF`-keyed registries.
7. **Lighting field** (item 7): after the Rust core consolidation (Phase 0b)
   and item 0.
8. **Deferred interaction setup** (item 10): alongside the latent rollout (3d).

## 8. Reproducing

```
tools/build/build.sh bench -DCITESTING_FULL_MAP --scenario=boot_profile,explosion_dense --runs=3 --warmup=0
tools/build/build.sh bench -DCITESTING_FULL_MAP -DBENCHMARK_DEEP_PROFILE --profile --scenario=boot_profile --runs=3 --warmup=0
tools/build/build.sh bench -DCITESTING_FULL_MAP -DBENCHMARK_DEEP_PROFILE --scenario=explosion_dense --runs=3 --warmup=0
tools/build/build.sh bench -DCITESTING_FULL_MAP --profile --scenario=explosion_dense --runs=3 --warmup=0
```

Run the boot and explosion scenarios in separate invocations: a boot whose
explosion dies of §0.1 loses its boot results too. `--arg=x=128 --arg=y=178
--arg=z=2` pins the explosion site.
