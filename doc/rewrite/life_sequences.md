# Sequences, and Mob Life on them

Status: **[built]** (S0) on `rewrite/s0-sequence`: the kernel primitive, the Life sequence definition (no mob runs
it yet), `on_change(at_most =)`, the Life edge generator, focused tests and a bench. The waves that move Life onto it
(S1-S4, section 7) are **[planned]** except S2, which is **[built]** (section 7a). Code: `code/controllers/kernel/sequence.dm` (runner, wakes, parking, audit),
`sequence_table.dm` (steps, tables, order, the edge generator), `sequence_state.dm` (frame, state),
`code/modules/mob/living/life/life_sequence.dm` (`/datum/sequence/life`). Tests:
`code/modules/unit_tests/kernel_sequence.dm`. Bench: `code/modules/benchmarks/life_sequence.dm`.

## 1. Why a sequence

A work item ([scheduling_and_kernel.md](scheduling_and_kernel.md) section 2) runs one handler per member. That is
stage-major: every member runs step A, then every member runs step B. Mob Life is entity-major: one mob breathes,
metabolises, takes its body's status, then runs the steps that read that status, all sharing one frame (its gates,
its environment, what an earlier step decided), before the next mob starts. The object-model pipeline runner
(`code/datums/om/pipeline.dm`) did that with stage flyweights, families, variants, plans and facts. A sequence is
the kernel's version of it, built from the kernel's own parts: membership, the one timer, `READERS`/`publish_change`,
the shared graph validator and the spread sweep.

## 2. The primitive

`/datum/sequence` is a definition (one per type, `sequence_def()`): `interval`, `step` (fixed step in seconds, 0 for
variable), `max_catchup`, `clock` (`CLOCK_BIO` for Life), `lane`, `runlevels`, `park_after`, `min_relevance`,
`wake_all`, `table_proc`, `frame_type`, `profile_stride`, and the procs `anchors()`, `conditions()`, `admit(E)`.

One work item per sequence, `/datum/work_item/sequence` (phase P, the sequence's lane, clock and run levels), sweeps
the sequence's **membership**. Its sweep is spread over the interval like a cadence's (`run_item_spread()`), so a
large population costs a slice per tick. For each member it turns the elapsed time (on the member's clock) into
frames (fixed step, at most `max_catchup`), asks `admit(E)`, and runs the frame loop, which keeps the pipeline
runner's word-bit fast path: every step while none sleeps, else a walk over the awake bits of each 16-bit word.

`seq_start(E, path)` / `seq_stop(E, path)` put an entity on a sequence. Its `/datum/seq_state` (per sequence and
entity, in `E.seq_states[seq.idx]`) holds the table, the sleep bits, the idle-frame count, relevance, its own
contributors, the fixed-step accumulator; it is dropped on `seq_stop()` and on teardown (`rx_teardown()`).

## 3. Steps and tables

Steps are procs on the entity type. The type lists them in its table proc (for Life, `/mob/living/proc/life_steps()`),
composed like `reactions()`:

```dm
/mob/living/life_steps()
	. = ..()
	. += seq_step(PROC_REF(life_breathing), after = LIFE_INPUT, when = list("placed", "alive"),
		reads = list(CHANGE_MOB_LOC, nameof(losebreath)), should_run = PROC_REF(life_breathing_due),
		rewake = BREATH_STEADY_RESAMPLE, woken_by = "Moved; equipping internals")
```

- A subtype changes a step by **overriding its proc** (and `..()` for the parent's code). That replaces the
  pipeline's families, variants and plans: there is nothing to resolve.
- `seq_step()`, not `step()`: `step()` is BYOND's movement proc.
- A handler takes the frame: `handler(F)`. Its return is ignored except `STEP_ABORT`.
- The composed table of an entity is its type's table proc, plus the same proc on each **capability** of its type
  that defines it (a contributed step runs on the capability as `handler(E, F)`, `should_run(E)`), plus the entity's
  own **contributors** (`seq_extra_add(E, path, contributor)`: a trait state, a component; same calling convention),
  plus the sequence's anchors. It is built once per key: the type, `seq_plan_key()` (Life: the body plan) and the
  contributors' types. `seq_replan()` after the key's state changes.
- A contributed step's key is `"[contributor type]:[handler]"`; an entity step's is the handler name.

### Order: `after =` edges only

No `order` numbers. A step names what it runs after. **Anchors** (`seq_anchor()`, named no-ops) give the bands:
`LIFE_INPUT`, `LIFE_BODY`, `LIFE_MIND`, `LIFE_OUTPUT`, `LIFE_TAIL`, each after the one before. An anchor is a
**barrier**: the solver passes it only when no step is ready, so `after = LIFE_BODY` means "in the body band", and
every body step runs before any mind step without a step naming another band's steps. Steps no edge orders run by
key (`sorttextEx`, deterministic). An `after` target missing from a table (a step of another mob type, an absent
contributor) orders nothing there; the table records it in `unresolved`. Each table is validated with the shared
`graph_validate()`; a cycle is an error, and its steps still run (a bad table must not silence a mob).

The solver is `seq_order_keys(nodes, deps, anchor_set)`: Kahn's algorithm, ready steps before ready anchors, then
the lowest key.

### Deriving today's order (S3's aid)

`seq_derive_edges(plans, band_of, anchor_chain)` derives the edges that reproduce a known order exactly.
`life_sequence_edges(entities, trait_stages)` feeds it every plan the Life pipeline has built, plus each entity's
plan alone, with each trait stage and with all of them, and returns `list(edges, plans)`; `seq_check_edges()` checks
every plan comes out in today's order; `life_sequence_edge_report(edges)` renders one line per step to paste from.
An edge is added only where the key tie-break would be wrong (an earlier step whose key sorts after): one edge to the
latest earlier step present in every plan the step is in covers every such inversion up to it, and an inversion
after that gets a direct edge. So the edges hold when steps are missing from a table. The step keys are the stage
family paths under `/datum/om/stage/life`, `"/"` as `"_"` (`breathing`, `trait_diabetic`); S3 uses those keys, or
re-runs the generator with its own. `kernel_sequence_life_order` locks it: every plan of the current pipeline
(human, mouse, each trait) is reproduced by the solver the tables use.

## 4. Sleeping and waking

`should_run` replaces `idle()`: default TRUE (a step without one never sleeps on its own). It is asked **after**
every run (FALSE: the step sleeps) and **before** a woken step runs (FALSE: back to sleep without running), the same
predicate with one polarity, as `work_item.runnable()`. Contract: cheap, read-only, correct for an entity that isn't
running (the audit asks it of sleeping steps).

A step's `reads` are `publish_change()` keys (text; `native()` specs give their keys) and change channels (numbers).
Wakes:

- **Keys.** A table registers its keys with `READERS` on the entity's type (`seq_register_reads()`), so TRACKED
  setters, `timed_set` and the ownership accessors publish them. `publish_change(E, key)` ends in
  `seq_publish(E, key)`: the key maps to the positions that read it, their sleep bits clear, a parked member rejoins.
- **Channels.** `changed(E, channel)` (and `om_raise_change()`, the `OM_CHANGED()` setters) reach
  `om_dispatch_change()`, which calls `seq_channels(E, bits)` first: the steps whose reads include one of the bits
  wake. `E.om_listen` carries its sequences' channels (`seq_listen_mask()`, folded into `om_recompute_listen()`), so
  the ~290 producer sites stay unchanged. `wake_all` channels wake every step. `seq_wake(E, path)` is the explicit
  wake.
- A wake that arrives while that entity's frame runs waits in `pending` and is applied when the frame ends (a step
  that already ran this frame and slept runs next frame; one not reached yet was awake anyway).
- **Rewakes** use the one timer: `rx_after(E, delay, seq_rewake, "seq:[idx]:[key]")`, a TIMER relation keyed by
  entity, sequence and step, on the member's own timer clock (world time for a `CLOCK_WORLD` sequence). A rewake
  **runs** the step on its next frame without the pre-check (its work drifts with time, which no read announces:
  AFK, ambience, a steady-state resample). A parked member comes back for it and parks again as soon as the step
  sleeps (it counts as one idle frame already). `seq_stop()`/`seq_replan()` cancel them.

### Conditions

`conditions()` returns `seq_condition(name, check, reads)`: a proc on the frame type and the reads that can flip it.
Compiled to bits per table; `when = list("placed", "!in_stasis")`. Evaluated lazily, cached per frame
(`F.cond(name)`, `F.forget(name)` after a step changed what one reads). A step blocked only by conditions that have
reads sleeps (their reads wake it: the pipeline's `fact_covered`); one blocked by a condition without reads (nothing
announces it, Life's "placed") stays awake unless its own `should_run()` is FALSE.

### The frame

`/datum/seq_frame` is pooled (`/datum/pooled`). Typed fields replace facts: Life's frame has `stasis`, `status_ok`
(the status step's result, which `set_fact("status_ok")` was) and `environment()` (the air, read once per frame).
`begin()` runs at the start of every scheduled frame; `reset()` when it goes back to the pool and after each member
of a sweep. The sweep reuses one frame member after member; `run_step_now()`, the audit and `seq_run_frame_now()` take
a scratch one.

`STEP_ABORT` (`return F.abort()`) stops the frame: the steps after it don't run and nothing sleeps this frame (the
pipeline's `OM_ABORT_FRAME`; `OM_ABORT_REST` has no user and no equivalent). `admit(E)` is the whole-frame guard.

## 5. Parking, relevance, time, the audit, cost

- **Parking is membership.** A member is in the sweep only while it has an awake step and is relevant. After
  `park_after` frames in a row with every step asleep it leaves (`member_leave`, O(1) swap-remove) and joins the
  sequence's parked list (the audit's sample); a wake rejoins. Its execution token goes with it, so it comes back
  with one interval, not a catch-up.
- **Relevance.** Below `min_relevance` (`om_observe()`) a member is out of the sweep; `CHANGE_RELEVANCE` puts it back
  unless it is parked. Life: `RELEVANCE_NEAR` (a low-priority mob on a z-level with no living player).
- **Time.** A member's elapsed time is read on the sequence's clock (`work_clock_now()`): with `CLOCK_BIO` stasis
  stretches the frames (at rate 0.1 a frame every ten cycles, at 0 none). Outside its run levels nothing runs and
  nothing accumulates; resuming is not a catch-up.
- **Missed-wake audit.** `seq_audit()` runs with the pipeline audit (SSbehaviours' `audit_step` work item: same interval, the
  `OM_PIPELINE_AUDIT` config flag, the "Toggle Pipeline Audit" verb, always on in test builds). A sleeping step whose
  `should_run()` holds, with its conditions passing and no rewake pending, is a missed wake: it logs
  `MOB_HIBERNATE_AUDIT: MISSED WAKE ...`, fails the unit test run, and wakes the step. Test builds snapshot a step's
  var-backed reads when it falls asleep and name the ones that changed without a publish.
- **Cost.** `profile_stride` times every Nth frame per step into cost slots (one per step key);
  `kernel().metrics()["work"][key]["sequence"]` carries them with the frame, park, wake, breach and miss counters.

`life_wake()` / `life_hibernate()` (named by older docs) do not exist on this tree: Life's producers call
`changed()`. The only writers of a state's sleep bits, parking and sweep membership are the procs in
`code/controllers/kernel/sequence.dm`; their field names (`bits`, `asleep`, `parked`, `idle_frames`) are covered by
`check_grep.sh`'s "idle and park state in one place" rule.

## 6. `on_change(at_most =)`

`on_change(reads, handler, at_most = N)`: after a delivery, changes within N deciseconds are held and delivered once,
with every key they named, when the window ends (a keyed world-time timer; `rx_at_most_admit()` in
`reactions/delivery.dm`). It replaces the reactive pipelines' `min_interval` for S2. A static reaction only
(`observe()` delivers every drain). `busy_retry` (a stage that still had work ran again) has no equivalent: a
handler with more to do schedules it with `after()`.

## 7. The waves

| Wave | Moves | Deletes |
|---|---|---|
| **S0** (this) | The sequence primitive, `/datum/sequence/life` (no mob on it), `at_most`, the edge generator, tests, bench | nothing |
| **S1** | The machine pipeline dissolves: each machine stage becomes a reaction on the machine (`on_change`, `every`), `machine_active` becomes membership (a machine is in the sweep only while it has work), `drawn_from` declares its power reads | `/datum/om/pipeline/machine` and its stages |
| **S2** [built] | `life_derive` (canmove), `life_present` (HUD) and `life_vision` become `on_channel` reactions on `/mob/living` with `at_most = LIFE_PRESENT_MIN_INTERVAL`; `refresh_hud()` / `refresh_vision()` call the handler | the three reactive Life pipelines (deleted) |
| **S3** | The main Life stages become procs on `/mob/living` and subtypes, declared in `life_steps()` with the edges `life_sequence_edges()` derives (keep `kernel_sequence_life_order` green); `idle()` becomes `should_run()` returning `!(old body)`; `rewake_delay()` becomes `rewake`; run_if facts become `when`; `ctx.set_fact("status_ok")` becomes `F.status_ok`; `ctx.fact("environment")` becomes `F.environment()`; trait stages become contributors (`seq_extra_add()`); mobs `seq_start()` Life where they attached the pipeline; `recompose_life()` calls `seq_replan()` | `/datum/om/pipeline/life`, `/datum/om/stage/life/*` |
| **S4** | Docs; `check_grep.sh` rejects `/datum/om/stage` | `code/datums/om/pipeline.dm`, the OM plan/variant/fact code, the stage adapter, `life_sequence_plans()`/`life_sequence_edges()` |

### 7a. S2 as built

- **Channels as change keys.** Life's producers call `changed(src, CHANGE_MOB_*)`: they raise channel bits, not var
  keys. `on_channel(bits, handler, at_most =, when =)` (`code/datums/reactions/reactions.dm`) is `on_change()` over
  `CHANNEL_KEY(bit)` keys; the type table keeps `chan_mask` / `chan_reactions`, `om_recompute_listen()` folds
  `chan_mask` into `om_listen`, and `om_dispatch_change()` calls `rx_channels()` (`reactions/delivery.dm`), which
  queues the reaction for the drain with a key per raised bit. No producer changed.
- **The three reactions** (`living_systems.dm`, "Reactive output"): canmove on `CHANGE_MOB_STATUS | STAT | EXPLICIT`
  (no `at_most`: the derive pipeline had no `min_interval`); HUD on `HEALTH | STATUS | LOC | EQUIPMENT |
  LIFE_WAKE_ALL`, `at_most = LIFE_PRESENT_MIN_INTERVAL`; sight on `STATUS | EQUIPMENT | CONDITIONS | HEALTH |
  LIFE_WAKE_ALL`, same `at_most`.
- **`requires has_client` is the HUD's `when`** (`life_hud_wanted()`), asked when the channel is raised: a clientless
  mob queues nothing. `life_sets` became `when` too (`life_canmove_wanted()`, `life_vision_wanted()`): robots derive
  canmove reactively but draw HUD and sight only from `robot_interface`, as before.
- **Stage variants are proc overrides** on the mob types (`life_canmove()`, `life_hud()`, `life_vision()`, the
  `life_hud_*` helpers); the "placed" gate is `life_placed()`.
- **Rewakes and busy_retry** are keyed `rx_after()` timers (`"life_hud"`, `"life_vision"`, the human's
  `"life_hud_full_refresh"`): an idle pass arms its `*_rewake_delay()`, a pass that is not idle (a type with its own
  HUD, a remote-view listener on sight) runs again `LIFE_CYCLE` later. `refresh_hud()` / `refresh_vision()` call
  `life_hud()` / `life_vision()` directly and arm nothing, as `om_stage_run_now()` did.
- **One behaviour change:** the reactive pipelines shared `/datum/om/frame/life`, whose `begin()` advances the stasis
  clock, so every HUD, sight or canmove frame advanced it as well; the reactions take no frame, so only Life frames do.
- Tests: `life_om/derive_and_present`, `life_om/hud_gate_has_client`, `life_om/hud_at_most_coalesces`,
  `life_om/npc_vision_follows_inputs` (`dq_life_om_tests.dm`).

S3 decision points:

- **Stasis.** Today the Life frame runs at world time and `begin()` calls `body.advance_stasis()`; biology stages
  skip paused frames (`run_if NOT_OF(FACT("in_stasis"))`). `/datum/sequence/life` is `CLOCK_BIO`, so stasis stretches
  the frames themselves and its frame's `stasis` only says whether stasis applies. Do not keep both, or biology slows
  twice. With the bio clock, the non-biology steps (AFK, ambience, movement and grabs) slow too: move them to
  reactions first, or make them tolerate it, or set `clock = CLOCK_WORLD` and keep `advance_stasis()` in `begin()`.
- **Pre-check.** A woken step now asks `should_run()` before it runs; the pipeline ran every woken stage once. A
  stage whose `idle()` is always TRUE and relies on a rewake (AFK, ambience) is fine (rewakes run without the
  pre-check); one woken by a channel that must run once regardless needs a `should_run()` that says so.
- **Keys.** The derived edges assume the generator's keys; renaming steps means re-running it.

## 8. Measured

`tools/build/build.sh bench --scenario=life_sequence`: a Life-shaped sequence and the pipeline runner with the same
30 steps over five bands, Life's gates, a frame `begin()` hook, a fixed step and no parking; ns per mob-frame, best
of 7 rounds, 2000 mobs per engine. "runner": the frame loop called directly; "scheduled": the pipeline's ring on a
test scheduler against the sequence's spread sweep on a test kernel. Gate: sequence <= 1.05 x pipeline.

S0 run (virgo_minitest, BYOND 516.1687; the bench's absolute ns carry its TICK_USAGE conversion, compare ratios):

| Shape | Runner: pipeline / sequence | ratio | Scheduled: pipeline / sequence | ratio |
|---|---|---|---|---|
| awake (30 of 30 steps work) | 103167 / 81951 | 0.79 | 107524 / 88436 | 0.82 |
| mixed (10 of 30) | 45936 / 39352 | 0.86 | 50175 / 46169 | 0.92 |
| idle (0 of 30, parking off) | 4312 / 4688 | 1.09 | 6315 / 9288 | 1.47 |

Awake and mixed pass the gate: the sequence is cheaper per frame (no per-stage flyweight dispatch through
`idle()`, no `idle()` call for a step without `should_run`). The idle shape misses it by ~0.4 us (runner) and ~3 us
(scheduled) per mob-frame: a frame whose every step sleeps still pays the sweep's per-member path, where the ring
paid one call. In service that shape does not occur (such a member parks after `park_after` frames and costs nothing:
it is out of the sweep); it is left as a known gap. What was done to get here: the sweep inlines its per-member path
(`/datum/work_item/sequence/sweep()`, a new `work_item.sweep()` hook in `run_item()`), the execution token lives on
the member's state, `admit()` is asked only with `admit_guard`, the frame end is inline, and the sweep's frame is
reset once per pass.

## 9. S3 as built (rewrite/om-life, L1 of om_retirement.md)

- Every Life stage is a proc on its mob type; `life_steps.dm` declares them (`tools/dx/codemods/life_stage_steps.py`
  wrote it, with derived `after =` edges checked against every plan the pipeline could build). Trait stages are
  contributed steps (`life_steps()` on the trait state, `seq_extra_add()`). The pipeline, its frame and the edge
  generator are deleted; `kernel_sequence_life_order` went with them (the tables are the order now).
- **Stasis**: the sequence runs on `CLOCK_WORLD`; `begin()` advances the body's stasis counter and biology steps skip a
  paused frame (`when = "!in_stasis"`), as the pipeline did.
- **Pre-check**: event-driven steps (run once per wake, no state says there is work) are `seq_step(..., once = TRUE)`.
- **Suspension**: `admit()` skips a suspended mob (`admit_guard`).
- **Rewakes**: one timer per member (`seq:<idx>:rewake`) for its soonest step due time (`state.rewake_at`), on its own
  clock. Per-step keyed world-clock timers all landed on the global owner's single list and dominated a 512-human bench.
- **Dispatch**: `typed_dispatch` sequences call steps through `run_step()`/`ask_step()`; Life's are a generated switch
  (`life_dispatch.dm`, `tools/dx/life_dispatch_gen.py`). A by-name `call()` on a human costs ~15-20 us (its proc table);
  the switch ~1.4 us.
- **Bench gate**: `life_sequence` now pins the pipeline's cost against a reference runner (section 8's gate without the
  pipeline). `life_sweep` (real mobs, same machine, back to back): h512 kernel 327 ms/s for 2563 frames against the
  pipeline's 373-392 ms/s for 2286-2517; mix 104 against 142-171 ms/s.
- **After the stat moves** (relevance, suspension and the bio clock are stats; trait disabilities, shakes and the mob
  repeats are every(); October 6 2026): `life_sequence` ratios awake 0.81/0.78, mixed 0.85/0.88 (runner/scheduled), idle
  0.99/1.26 (the known idle gap above: `life_sequence_gate_failures` 1, the idle scheduled path, as at S0's 1.47).
  `life_sweep`: h512 149.8 ms/s for 3413 frames, mix 33.4 ms/s (the body migration also took its stages out of Life).
