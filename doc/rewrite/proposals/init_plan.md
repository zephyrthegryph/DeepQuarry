# Plan: init under 100 s, and near-zero runtime cost for the slow types

**Date:** 2026-11-07. Measured on master `6cd027a9f6` / `4ad2e8b828`.

## Where the time goes today

**The live test server.** Init took **326 s**: **273 s** setting up map objects (InitializeAtoms) and 53 s in everything else.

**Atoms by count:**
- 539k atoms on the map, about 490 µs each.
- 303k of them are space turfs.

**The 270 µs per atom is spread thinly, not one slow function.** Each atom makes about **177 small engine calls** (about 1.6 µs each). There are three causes:

1. **Per-type facts are worked out again for every object.**
   - Every atom does about 31 table lookups to answer questions whose answer is the same for every instance of its type: does it have setup rows, which stats it has, its traits, its init plan.
   - About 15 functions exist only to test one bit and call the next.
   - A plain space turf makes 63 calls; it should make about 6.
2. **Construction isn't silent, although the design says it is** (`final_api.html` §6–7).
   - Writes an object makes to itself while it's still being built are published as live changes. They trigger readers, stat updates, hops and redraw marks for an object nobody can see yet.
   - That is 785k of these at startup.
   - Then `stat_holder_init` recomputes everything from scratch anyway, so the work is done twice and the first copy is thrown away.
   - Every atom also publishes a "created" notice that almost nothing listens to.
3. **Per-object records are built eagerly.**
   - **Hook baselines:** one per hook per object, keyed by text.
   - **Stat to-do lists:** a sorted list per object.
   - **Sensors:** a firedoor builds 9 sensors (27 datums plus 18 relation writes) that arm nothing.

   Meanwhile the "is there work?" checks use global name lists that are too broad, so 97% of writes take the full slow path.

**How the slow types add up** (profiled seconds; real time is about half):

| Type | Count | Boot cost | Why |
|---|---|---|---|
| Firedoors | 1,961 | 24.6 s | 9 dead sensors per door; power join; area pairing written twice; a separate light-blocker atom each |
| Supply/scrubber pipes | 6,949 | ~19 s | join the power system though they draw 0 W; colour and renderer set by tracked writes; operable stat nobody reads |
| Air alarms | 444 | 6.9 s | 7 sensors armed before thresholds load, then re-armed; own copy of the threshold table; whole-room election per alarm |
| Lights | 1,358 | 13.8 s | a real bulb item and a real emergency battery built per fixture |
| Cable coils | 2,704 | 6.3 s | material stats recomputed per coil (same answer for every coil) |
| Locker and box contents | 25k items | 81 s | each item is a full nested init; reagent holders are 1.2 ms each |

The cable and pipe *networks* are already built in one native (Rust) pass. The cost is the DM objects around them.

## Target architecture

1. **One compiled plan per type.**
   - InitAtom fetches it once by integer index and runs only the steps that type has.
   - Setup rows are called by proc path, not by name.
   - Inert types, like space, fixed-fabric and transit turfs, take a short path of flags, appearance and bulk registration.
2. **Construction is silent.**
   - One "under construction" flag is checked first on every write path.
   - At birth, the object does everything once: stats (or computed on first read), followers, hook baselines, first draw, the created notice if anything wants it, and materialize.
   - Objects that already exist still publish normally.
3. **State records are lazy and shared.**
   - Baselines, stat records, capability data and index rows stay empty until the first write that differs from the type's template.
   - Compile-time defaults (`initial()`) replace per-instance writes of per-type constants, such as the luminosity, opacity and path weight that every turf writes, and the air every space turf writes.
4. **Rust owns the bookkeeping indexes.** That covers the reverse relation index, sensing subscriptions (one per object instead of 9), contribution sums such as area power demand, and pending-change sets. Each is one bulk call per frame.
5. **Owned items are data until used.**
   - A light's bulb and battery, an alarm's wires and board, and machine parts are fields on the owner.
   - A real item is made only when someone takes it out, or when the owner is destroyed.

## Slices, in landing order

The gates are engine call counts from the deep `boot_profile` / `mapload_init` runs, because those don't depend on machine load. Atoms seconds are also tracked. Each slice gets focused tests and the boot gate.

### Engine (per-atom framework)

| # | Slice | Gate | Atoms after |
|---|---|---|---|
| E1 | No-behaviour-change fixes: exact lifecycle bits, a write memo that returns which parts have work, direct pool reset, a "wanted" bit for the created notice, init frame as a flag, stat to-do list per type, generated `New` | pre-init entries 507k → ≤150k; full-path writes 97% → ≤50%; `stat_relation_changed` 483k → ≤200k | ≤245 s |
| E2 | Per-type plan, one lookup per atom, setup rows by proc path | ≤25 calls per space turf (63); lookup calls 16.5M → ≤3M; on/off parity test | ≤225 s |
| E3 | Silent construction plus the birth step, behind a toggle | startup publishes 785k → ≤150k; full-map census identical with the toggle on and off; hook-firing census reviewed | ≤190 s |
| E4 | Lazy and template records: baselines, stats, Rust sensing | baselines 16 s → ≤3 s; sensing 15.5 s → ≤3 s | ≤170 s |
| E5 | Inert-turf flyweight, compile-time defaults, no air write on space | ≤30 µs per space turf (166) | ≤155 s |
| E6 | Generated relation setters and the Rust edge index (Codex's change-graph lane) | `rel_set` 86 s → ≤30 s | ≤145 s |
| E7 | Delete the old discovery path; add a ratchet on calls per atom | ≤6 calls per space turf | — |

### Slow types (content)

| # | Slice | Saves (real) |
|---|---|---|
| T1 | Lazy flat sense record: no record when there is nothing to arm | ~7 s |
| T2 | Zero-draw machines (pipes) leave the power model | ~3.5 s |
| T3 | Material blueprint memoised per type and material (coils, cells, tanks, pipe items) | ~2.5 s |
| T4 | Alarms: thresholds as a preset, shared table, one election per room | ~2 s |
| T5 | Pipe presets, no light blocker, hidden pipes drawn on reveal; firedoor single area relation and shared blocker | ~2.5 s |
| T6 | Light bulb and battery as fixture data | ~2.6 s |
| T7 | Batched power join at map load | ~4 s |
| T8 | Reagent starting templates per type | ~6 s |
| T9 | Wires and boards created on first use | ~1–2 s |
| T10 | Air-pipe ports and node matching in Rust | ~14 s (Atmospherics init 17.9 s → ~4 s) |

### Outside Atoms

- **Once-per-type table builds, about 20 s real:** `build_own_table`, `table_build` and `stat_type_build` run on the first instance of each type. Move them to a build-time compile or a boot cache.
- **The other 53 s** of non-Atoms subsystem init: profile it per subsystem and cut it the same way.

### Needs your OK

**L1. Fill locker and box contents during the 2-minute lobby countdown**, instead of before the lobby opens. The items are still real, and whatever isn't filled by round start gets filled then. It takes about 25 s off time-to-lobby. Your containment doc says contents are made at init, which is why this needs your sign-off. It is not the old latent system: there is no collapse, no sweep, and no eligibility list.

## Expected result

| | Atoms | Total init |
|---|---|---|
| Today | 265–273 s | 316–326 s |
| After E1–E5 + T1–T9 | ~130 s | ~180 s |
| + E6–E7, the per-type table cache, T10 | ~95 s | ~135 s |
| + lobby fill (L1) and trimming the other subsystems (39 s → ~30 s) | ~70 s | **~100 s** |

Reaching about 100 s takes everything above, including the lobby fill or an equal cut elsewhere. Without the lobby fill, plan on about 125–135 s.

## Runtime cost of the same types

- **Firedoors:**
  - Idle cost is already zero.
  - A fire alarm closes doors at about 2 ms each, so a station-wide alarm stalls about 2–2.5 s in one frame.
  - Rust signature sensing makes each door close one command (~0.1 ms), so the whole station takes ~0.2 s.
- **Pipes:**
  - The per-tick cost is zero, because Rust simulates them.
  - The boot settle draws every pipe, hidden ones included, which costs 0.8 s. With T5 it draws only visible pipes.
  - Each pipe also holds a 0-value row in its area's power demand, which T2 removes.
- **Air alarms:** they scan for 9 s after boot, then wake only when a gas band is crossed. That's already cheap.
- **Lights:**
  - Idle cost is about zero.
  - An APC light-channel flip costs about 1 ms per light.
  - Night shift rebuilds all 1,358 light sources in one frame. The fix is a batched light pass, and later lighting counted in Rust.
- **Coils:** no runtime cost.
- **Engine:**
  - E1–E3 make every runtime write cheaper too, because the write memo skips the parts with no work.
  - Item use and menus are separate: the compiled op-system agent (`op_compiled.md`) covers them.

## Who does what

- **Engine slices E1–E5 and E7:** the engine research agent.
  - It owns `code/engine/**`, except `parts/` and `refs/hops.dm`.
  - It also owns `code/library/capabilities`, `code/library/lifecycle` and `code/world/systems/atoms*`.
- **Slices T1–T6 and T8–T9:** the slow-types agent.
  - It owns `code/content`, `code/domains`, `code/library/machine` and `code/library/reagents`.
  - It is already started.
- **T7, T10, the per-type table cache and the other subsystems:** the boot agent.
- **E6:** Codex's change-graph and `.dmt` lane.
- **Item use and menus:** the compiled op-system agent, in `code/engine/parts`.

## Note: the look verdicts (2026-11-08)

The boot settle samples one draw per type to learn whether its default look is empty. The verdicts are not cached across boots: the verdict file (`data/look_verdicts.json`) is gone and each boot samples again (see [../draw_on_change.md](../draw_on_change.md) section 3).
