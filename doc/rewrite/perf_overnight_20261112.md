# Overnight profiling: boot, init, idle, supermatter explosion (2026-11-12)

Tool: `tools/build/build.sh bench --scenario=boot_profile,idle,major_events --arg=events=supermatter --profile` on the unit-test map
(virgo_minitest), one measured boot per run, machine shared with other lanes (CPU ~60 %), so timings carry about ±15 %.

## Baseline (master 83863dafb9)

| | value |
|---|---|
| init_seconds (kernel init) | 64.7 s |
| Atoms / Static entries / Early Assets / Assets / Atmospherics / Lighting | 31.2 / 11.6 / 3.9 / 2.8 / 2.6 / 2.1 s |
| booted private memory | 1501 MB (Rust heap 26 MB, peak 84 MB) |
| idle 60 s: tick avg / p95 / p99 | 5.6 / 11 / 21 % |
| idle: native_step / sched_core / appearance_drain | 10.5 / 6.0 / 1.3 ms/s |
| supermatter explosion (60 atmos cycles, 29.6 s): tick avg / p95 / p99 / max | 28.5 / 86 / 97 / 106 % |
| supermatter: appearance_drain / native_step / sched_core | 22.1 / 10.6 / 15.7 ms/s |

Top boot self time (profiled): entry_signature 4.0 s (65 k calls), benchmark_early_private_mb 4.2 s (bench-only probe), InitAtom 3.5 s
(204 k), asset_cache_build_key 3.1 s (1 call, hashes the .rsc; 0.43 s on a warm file cache), type_trait_table_build 2.3 s (25 calls) plus
type_trait apply_args 1.1 s (63 k), space_appearance 1.1 s (184 k), boot_created_hold 0.9 s, stat_type_build 0.9 s.

Supermatter explosion: 6.0 s of 8.8 s kernel time is explosion_step -> ex_act over 5166 turfs (~1.1 ms per turf), spread over
ChangeTurf (3.0 s), qdel/destroy_transaction (2.3 s), integrity damage (2.0 s), adjacency recompute (0.7 s). No single hot proc.
Worst tick: one Explosions slice at 416 % (one epoch not split). Idle: nothing above 0.4 s self in 60 s (vg_frame, kernel dispatch).

## Fixes

1. **Type traits per declaring entry** (fdd9f47665). type_trait_table_build built one `/datum/type_trait` per type table that declares the
   kind; interned entries mean most subtype tables hold the parent's very entry. Now one trait per distinct entry (atom_rules 5100 -> 977
   traits). Static entries init 11.6 -> 8.2 s, booted private memory 1501 -> 1436 MB (-65 MB), apply_args drops out of the profile.
   Same commit range: `look_layer_rows` on `/datum/capability` became `var/tmp` (a first-draw cache changed an interned capability's
   signature and failed dq_interned_entry_signatures_unchanged).

Tried and dropped: naming interned children by a serial in entry signatures (shorter nested text). Measured no change (entry_signature
4.24 s vs 4.03 s): a probe showed signatures average 200 characters (12 MB over 60 k), none over 20 k, so nesting is not the cost.

## Open leads

- entry_signature 4 s: genuine per-declaration work (45 k entry_make + 20 k part_make), string building; needs a cheaper interning key.
- Explosion epochs not split under the tick budget (416 % tick).
- First closet of each type pays 100-190 ms in after_init (create_spawn_contents: first instances of their item types).
- asset_cache_build_key hashes the whole .rsc on a cold file cache (3.1 s).

## Round 2 (perf/overnight-r2-1, base 7c37894f7c)

Same bench command, two sequential runs (before / after), machine CPU ~65 % from other lanes.

| | before | after |
|---|---|---|
| entry_signature self / total | 2.9 / 3.3 s (round-1 4.0 s self) | 1.25 / 1.6 s |
| stat_type_build total (2641 calls) | 2.05 s | 1.36 s (stat_declared_on 589 k -> 5.7 k calls) |
| Static entries init | 6.4 s | 5.5 s |
| init_seconds | 52.8 s | 51.0 s |
| booted private memory | 1489 MB | 1443 MB (noise band) |
| Atoms init | 32.2 s | 33.9 s (noise; no change aimed at it) |

Fixes:

2. **entry_signature joins once**: the signature was built by `+=` per argument, each step a new long string interned by BYOND; it now
   collects parts and joins them once.
3. **stat_type_build asks only declaring types**: `stat_defs_declared_under()` indexes declaring type -> defs; a type with no stats skips the
   registry walk. This is part of the "first locker per type" cost (first instance of each item type builds its stat view).

Explosion (lead 1): the epoch already yields per turf under the tick budget (TICK_CHECK after each turf, atom batches and deferred flushes).
The 416 % tick did not reproduce in two runs (worst 168 % / 178 %, kernel tick log). New EXPLOSION_SLOW tracing logs any single step or work
item over 15 ms: the worst single items were one turf at 23 ms (plating at the map edge, space at 49,16,4); steps run 15-29 ms. So the
remaining overruns are per-turf cost, not missing yields. Per-turf cost is flat: ChangeTurf 1.2 ms (2345), destroy_transaction 0.4 ms
(4807), deal_damage 0.8 ms (2348), ReplaceWithLattice 1.6 ms (949); no proc dominates. Not changed this round.

Not done: asset_cache_build_key (a cheaper key needs the .rsc to be content-addressed by the dmb; unverified for the native compiler, and the
cost is cold-cache only), type_trait_table_build (1.2 s self: 25 kinds x every type written into per-kind type maps; could key by table
instead), vg_hook_register_world_turfs (1.1 s in one Rust call), memory (no per-type duplication found in the time).

## Round 3 (perf/overnight-r3-1, base a33050d936)

Same bench command (`boot_profile,idle,major_events --arg=events=supermatter --profile`), plus `memory_report` (settle 10 s, idle 0).

Fixes:

4. **Type trait tables keyed by type table** (8e54e292a7): the build wrote one row per type for each of 25 kinds (about 220 k rows);
   it now writes one row per declaring table, and `type_trait_of()` reads the type's table first (one more list read per call, inlined).
   Boot profile: type_trait_table_build 1.2 s self (round 2) -> 0.19 s self / 0.25 s total. `dq_type_trait_tables_equal_scan` compares
   the per-table build, read per type, with the scanning original.
5. **Explosions hold adjacency recomputes** (9b93c42906): each changed crater turf recomputed its 4-8 neighbours at once, so most members
   recomputed several times per epoch. `adjacency_hold_begin()` (at start_resolve) queues them, deduplicated by slot, and
   `adjacency_hold_drain()` runs each once, tick-checked, after the deferred turf updates (`ADJACENCY_HOLD:` log line per drain). Supermatter:
   adjacency_recompute 14.4 k -> 4.9 k calls (0.51 -> 0.14 s), edges_changed 13.1 k -> 3.8 k, step_epoch 4.28 -> 3.78 s total, worst tick
   129 % -> 93 % (one run each; the call counts are deterministic, the timings carry the usual noise). Test: `dq_lifeform_adjacency_hold`.

Surveyed, not changed:

- Explosion per-turf cost after fix 5 (0.65 ms per turf in the profile): ChangeTurf 1.7 s (replaced_by -> destroy_transaction 1.2 s,
  of which rel_clear 35 k calls 0.58 s, own_clear 0.35 s: real disposal of the old turf's relations), integrity damage 1.25 s
  (settle_integrity_crossings 0.62 s), ReplaceWithLattice 0.98 s (a new lattice InitAtom each). rel_clear on an already-null var is cheap
  (rel_kind + list_state_of + rel_view_clear total ~0.15 s), so a null fast path would save little.
- vg_hook_register_world_turfs: 0.82 s for 262 k turfs, about 3 us per turf: ~10 byondapi var reads plus a held copy of `contents` per
  turf (verdigris/ffi/src/gas/mod.rs boot_turf()). Reading the per-type vars once per type would break map-edited turfs; skipping the
  contents copy for empty turfs needs a list-length read in the byondapi wrapper. Not done (Rust build and ABI check; small gain).
- Memory (memory_report, minitest): 1426 MB private, of which the DM model estimate is 109 MB and Rust 26 MB; the rest is BYOND's own
  (262 k turfs, appearances, resource cache, code). Largest DM owners: /turf/space 184 k instances (stored vars: flags, _air, luminosity,
  refresh_queued DEP_PARKED on 87 % by the lazy draw design), type tables 500 k list entries (~10 MB), entries 311 k (~10 MB), globals 12 MB
  (type_trait_tables 2.5 MB before fix 4). No per-instance list that should be lazy shows up among the top owners.
- Idle (60 s): 5.6 % tick average; native_step 6.9 ms/s dominates (Rust frame). DM side ~1.3 ms per tick of kernel bookkeeping, no hot
  proc above 0.4 s. The largest avoidable-looking item, `set_times_fired()` publishing on every system run (5.8 k state_changed per minute,
  0.3 s), is tracked because the MC health panel's ui_data reads it, so it stays.

## Round 4 (perf/overnight-r4-1, base b145ff4465)

Same bench command (`boot_profile,memory_report,major_events --arg=events=supermatter --profile`), one run before and after; the machine
ran at 45-100 % CPU from other lanes, so timings swing by more than a third between runs (Atoms 27.5 s before, 41.6 s after with fewer calls).
Memory and call counts are the reliable measures here.

Memory. The memory_report early notes put DreamDaemon at 1121 MB before the first global initializes: the .dmb load, before any DM proc
runs. init_and_turfs.md §0.5 found the cause: BYOND keeps a slot for every (type, inherited proc) pair, about 23.5 bytes each. A census
on the unit-test build (`typesof(/x/proc)`): /datum 217 procs over 53 k types, /atom 451 over 22 k, /atom/movable 200 over 20.8 k, /obj 190
over 19.2 k, /obj/item 272 over 12.9 k, /mob 997 over 1.3 k: about 31 M pairs, ~730 MB. A /datum proc costs ~1.2 MB, an /atom proc ~0.5 MB.

6. **Mob statuses and pronouns off /datum**: the 19 `status_*`/`has_status` procs (mob statuses, code/library/mob/statuses.dm) moved to
   /mob, and the 20 pronoun procs (`p_they` ..., `REPLACE_PRONOUNS`) to /atom; /client and /datum/mind define their own (the mind's moved to
   code/content/mob/mind.dm). /datum 217 -> 178 procs. Memory at the first global 1121 -> 1076 MB, booted 1485 -> 1395 MB (one run each;
   the booted figure includes noise from boot transients). Three unarmed-attack messages called the attack datum's pronouns ("presses its
   ...") and now use the attacker's or target's.
7. **Space appearances carry luminosity 1**: luminosity is part of the appearance, so `appearance = dust` in space_appearance() reset each
   space turf to 0 and turf_instance_setup() wrote it back to 1: 184 k set_luminosity() calls and appearance changes per minitest boot. The
   skybox's base space appearance now has luminosity 1 (and /turf/space the type default).

Surveyed, not changed:

- Remaining proc-table cost: the biggest levers are leaf type count (data-only leaves into variants, another lane) and /atom's 471 procs
  (52 generated `set_<var>` setters of TRACKED atom vars alone are ~26 MB). Other /datum procs used by one family (space_* ledger, standing_*,
  graph_refund, acceptance_*) are engine hooks by design; each would be ~1 MB.
- Atoms init per atom (boot_phase timers, `--arg=boot_phase_timers=1`): the timers inflate nested phases several-fold (Atoms 62 s), so their
  per-phase costs (power_area attach 2.7 ms, flooring rel attach 0.24 ms) do not survive the plain profile (stat_relation_changed 0.19 s
  total, install_flooring 1.07 s over 6.8 k floors). No per-type-cacheable step stood out beyond what ctor plans already cache.
- Supermatter: one profile showed capture_args 2.47 s self over 76 type_every timers, almost all in the profiler's "over" column (time past
  the tick budget); older runs show nothing like it, so it reads as a scheduling artefact of the loaded machine, not code cost. Explosion
  per-turf work is unchanged from round 3 (ChangeTurf 1.9 s / 2356, deal_damage 1.8 s / 2356, ReplaceWithLattice 1.05 s / 919).

## Round 5 (perf/overnight-r5-1)

8. **Filter procs off /datum, dead base procs deleted**: the 8 filter procs (`add_filter` ... `remove_filter`) moved to /atom
   (code/library/helpers/filters.dm; no image or non-atom caller existed), `get_filter_index` (no caller) deleted; on /atom the dead
   `InsertedContents`, `containment_blast_exposure` and `flash_lighting_fx` (with its 3 overrides and `mob_light`) deleted, and
   `get_voidsuit` moved to /mob/living/carbon. Estimated from the pair cost (not re-measured): ~9 MB.
   Not done: moving `add_traits`/`remove_traits` off /datum makes the generator emit `add_traits`/`remove_traits` for
   /datum/species `traits`, which turns that list tracked and fails the tracked lint in species.dm/gene.dm.
   Biggest remaining levers are generated: the 8 tracked-list ops for /datum `open_tguis` (~10 MB) and the `set_<var>` setters on /atom;
   both belong to the analyze generator. Most other narrow /atom procs land on /obj, which saves only ~66 KB each.

## Round 6 (perf/overnight-r6-1)

9. **Generated list ops only where named**: `gen tracked_lists` now writes a tracked list's `add_`/`include_`/`remove_`/`set_<v>_at`/`clear_`/
   `insert_`/`swap_`/`cut_` op only when some source file names it (a call, a `PROC_REF()`, a string; generated output does not count). The
   version var is still written for every list. Generated ops 2944 -> 494 procs; /datum `open_tguis` keeps `add_`/`remove_` (6 /datum procs
   gone, ~7 MB), /obj/item 32 -> 2, /obj 16 -> 4, /obj/structure 16 -> 0, /turf 8 -> 0, /area 16 -> 4, /mob 48 -> 8, the rest on leaves
   (/obj/belly alone 413). Estimated from the pair cost: ~25-30 MB.
10. **vg_bind_/vg_reconcile_ stubs on /atom/movable**: the 8 per-domain default stubs the verdigris bindings generator wrote on /datum moved
   to /atom/movable. Their only callers are /atom/movable's `vg_bind()`/`vg_reconcile()`; native code never calls them by name (the Rust
   side reaches DM through the free `/proc/vg_bind_<row>` rows and the frame outbox). The generator now refuses a per-type bind on a type
   that is not an /atom/movable. Net ~5 MB (8 x (1.2 - 0.47) MB).

Surveyed, not changed: generated `set_<var>` setters. Only 8 auto-tracked setters sit on /atom (plus 18 hand-written `SETTER(/atom, ...)`),
all on their declaring type and all called; setters are reached by name (`call(holder, "set_[v]")` in modes.dm, lifecycle.dm, view
variables), so "emit only if called" is unsafe for them. The one dead one is `/datum/set_open_tguis` (the TRACKED macro writes a setter for
lists too; ~1.2 MB). Not re-measured on a booted world: master at b1eb979362 does not compile (events.dm `set_bankrupt` undefined, from
the reads lane), so no boot measurement was taken; the lane compiled with that one line patched locally (not committed) and passed 12 focused tests (boot gate, tracked lists, staleness, ui fixtures, verdigris binds, atmos).
