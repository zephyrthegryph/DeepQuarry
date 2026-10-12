# Staleness findings (2026-10-12)

The work list for the reactive-closure fix lanes (`doc/rewrite/final_api.html` section 7, "Reactive closure"). Produced by the staleness checker
(`code/engine/change/staleness.dm`) run over `dq_staleness_*`, `dq_life_*`, `dq_stat*`, `dx_*stat*`, `dq_generated_deps*`, `dq_power_wakes*`, `dq_draw_*`,
`dq_boot_gate`, `dq_look_state_pin` and `dq_look_tree_pin`. Nothing here is fixed by the checker's commit.

**How it is enforced.** `GLOB.staleness_known` in `staleness.dm` holds one row per finding below (kind, holder type with subtypes, thing). A report matching a
row is logged as `STALENESS|known|...` and does not fail the test; any other report fails the current test. When a root cause is fixed, delete its row (and its
section here) in the same commit. When the list is empty, set `GLOB.staleness_enforce_all` to TRUE and delete the flag's guard: the checker is then fully
enforcing. `tools/ci/known_failures.txt` is not used.

**Reading a finding.** "Cached" is what the engine served (the stat var, or the stat record); "fresh" is `stat_compute()` recomputed from scratch at the same
moment. "Culprit" is what the checker could name. In strict mode it snapshots a stat's declared reads after every clean check, so it names the var that moved
with no publish; where a stat has no recorded reads (a constant plus a raw write of the stat var itself) it says so.

## Coverage of this run

| Kind | Checked | Findings |
|---|---|---|
| stat (served by `stat_value()`, swept for direct var reads) | every cached stat of every tracked holder in the run | 4 root causes below, plus 1 class that is exempt (teardown) |
| draw (served from cache after a write the graph says nothing reads; swept) | every swept atom at the end of each test and each presentation drain | none |
| `derive()` value | every swept atom with a derived table | none |
| keyed image (`look_cached_image()` hits) | every hit | none |

The draw, derive and image checks found nothing in this set. That is a result about this set (mostly draw tests, which write through setters), not a proof for
the 1,859 `draw_untracked` sites: those are exercised by tests that change the untracked input mid-test, and few do.

## 1. A stat var written raw by game code (invisibility on pipes and terminals)

- **Root cause.** `invisibility` is an engine-owned stat var. `hide()` assigns it directly (`code/ATMOSPHERICS/pipes/pipe_base.dm:304`,
  `code/modules/power/terminal.dm:30`: `invisibility = i ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE`). The stat layer's cached value is never rewritten.
- **Cached / fresh.** 101 (hidden) / 0.
- **Culprit.** The stat var itself; no declared read moved ("written outside the stat layer").
- **Types.** `/obj/machinery/atmospherics/pipe` simple and manifold, hidden and visible (supply, scrubbers, black, plain): 9 leaf families; `/obj/machinery/power/terminal`.
  Hundreds of instances per look-pin world.
- **Tests.** `dq_look_state_pin` (all 4 shards), `dq_station_alarm_component_is_sealed`; any test that lays pipes or a terminal.
- **Read path.** The sweep: `staleness_check_ref <- staleness_sweep <- staleness_drain_step <- appearance_drain`, and at the end of a test.
- **Fix direction.** `hide()` becomes a contribution or a hold on the `invisibility` stat (a pipe under a floor), written through `hold()`/`release()`; mechanism 1 of
  the closure makes the raw write a build error.
- **Known row.** `stat /obj/machinery/atmospherics/pipe invisibility`, `stat /obj/machinery/power/terminal invisibility`.

## 2. Door density and opacity written raw (airlocks)

- **Root cause.** `density` and `opacity` are stats (final_api section 4). Door state changes write the vars directly instead of holding the stats
  (`code/game/machinery/doors/door.dm` sets them as type defaults; the cached value diverges from the composed one after door code assigns them; the exact writer was not traced).
- **Cached / fresh.** density 0 / 1; opacity 0 / 1 (the door is closed again but the var still says open, or the reverse).
- **Culprit.** The stat var itself.
- **Types.** `/obj/machinery/door/airlock/external` (and the door tree).
- **Tests.** `dq_draw_dir_published_by_a_native_turn`, `dq_draw_table_connections_are_tracked`, `dq_draw_floor_variant_is_rolled_once`, `dq_static_entry_constructors`,
  `dq_static_entry_inheritance`, `dq_static_entry_errors`.
- **Read path.** End-of-test sweep and presentation drain.
- **Fix direction.** Door open/close become `hold(density, ...)` / `hold(opacity, ...)` with the door's state as source.
- **Known row.** `stat /obj/machinery/door density`, `stat /obj/machinery/door opacity`.

## 3. A lapsed status hold leaves the stat set (`blinded`)

- **Root cause (unverified).** `blinded` is a `LIFE_CYCLE` status (`code/library/mob/statuses.dm:22`) and the var `/mob/blinded`. `life_status_update_sight()` calls
  `set_blinded(1)`; once the hold's life cycles run out the stat is not rewritten, so `has_status(STAT_BLINDED)` keeps answering 1. Whether the expiry timer or the
  clock the test advances is at fault was not traced.
- **Cached / fresh.** 1 / 0.
- **Culprit.** None of the stat's reads moved; the status hold expired.
- **Types.** `/mob/living/carbon/human`.
- **Tests.** `dq_life_alive_fact_skips_stages`, `dq_life_transforming_human_aborts`.
- **Read path.** `stat_value <- has_status <- life_status_update_sight <- life_step <- sequence/life/run_step`.
- **Known row.** `stat /mob blinded`.

(`blinded` on carp, mice, robots, observers and the TTS voice cached null or "" against a fresh 0. That is not staleness: nothing recomputed the stat because
nothing contributes to it, and every reader sees falsy. The checker treats null, "", 0 and FALSE as one value.)

## 4. Exempt by design: a read during teardown (`trait_holds`)

Not on the known list; the checker skips any entity that is `QDELING`. Recorded because it is a real ordering fact: `/datum/capability/lib/climb/on_holder_destroy`
(and the closet, mouse and radiation-clothing capabilities) call `remove_trait()`, whose first line `has_trait()` reads the keyed `trait_holds` stat after the
holder's own holds were taken apart, so it answers from a list that still names the trait (cached `{"trait_climbable":1}`, fresh `[]`). Harmless today
(`remove_trait` finds nothing to release). It was 291 reports across about 30 `dq_draw_*`, `dq_life_*` and `dq_state_*` tests. If a capability ever acts on that
answer in a destroy hook, it acts on a trait it no longer holds.

## Failures seen that are not staleness

These fail on `80f838d71b` with no checker (the same run on an unmodified checkout): `dq_draw_turkeygirl_follows_nutrition` (turkeygirl state), `dx_deps_output_writes_state`
(`refresh_flush` still queued after 20 passes), `dq_look_state_pin` (75 + 72 + 72 + 51 snapshot rows differ) and `dq_look_tree_pin` (`DECLARE ... is not an entry or a
capability` on the metroid and syndicate mobs). `dq_state_latent_round_trip` failed on 2 of 6425 types (`/image` has no codec: `emotions.joymask_designs`,
`tactical_sec_vis.tac_sec_vis_anim`) in the checker's run; it was not in the baseline run, so whether master fails it was not confirmed.

## Not measured

Only the tests above ran. Any other test that lays a pipe, a terminal or a door, or runs a human through `life_status_update_sight`, will log a `known` finding. A
new kind of staleness in an unmeasured test fails that test; read its `FAILURE` text, which carries the type, the stat, both values, the culprit and the read path.
