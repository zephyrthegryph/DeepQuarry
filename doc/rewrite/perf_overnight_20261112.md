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
