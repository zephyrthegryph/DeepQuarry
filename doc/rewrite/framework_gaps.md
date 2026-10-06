# Framework gaps and needed changes (2026-10-06, origin/master 63a0492e26)

Status marks (rewrite/lane-b): **DONE** = landed on that branch.

Confidence: **V** verified by reading code, **L** likely, **S** speculative. Line numbers approximate.

## A. Ownership and relations

| ID | Where | Problem and reasoning | Change | Conf |
|---|---|---|---|---|
| A1 | `code/engine/declare/relations.dm:323` `rel_take` | Branches only on `!isnull(member)`/`!isnull(key)`; a member that happens to be null falls through to "take everything". DM can't tell omitted from passed-null, so the API itself is the trap. All current call sites are guarded, but every new conversion risks it. | Add `rel_take_all(E, var)` (always returns a list). Make `rel_take` with a member/key a member-only take; null member = no-op returning null. Codemod the ~2 intentional take-all sites (grinder.dm:181, coil.dm:134). | V |
| A2 | `rel_take` vs `own_take_all` (own.dm:365) | Unset lazy list: `rel_take` → `own_take` → null; `own_take_all` → `list()`. Result shape depends on runtime state, not declaration. Blocks converting 68 `own_take_all` sites whose consumers need a list (damage_batch.dm:86, cards.dm:376, tarot.dm:29/83, revolver.dm:312, message_server.dm:325, component.dm:390). | Branch on the declared shape (OWNE_LIST flag, as own_move does), and make `rel_take_all` return a list for all list declarations. | V |
| A3 | `code/datums/ownership/own.dm:306` `own_take_member` | Nulls the var whenever it empties; `own_take_all`/`own_clear` call `own_list_emptied`, which keeps a `= list()` var as an empty list. Taking the last member singly breaks `.len`/`+=` on eager lists. | Replace with `own_list_emptied(holder, var_name)`. | V |
| A4 | `relations.dm:311` `rel_clear` | No policy passthrough, so an explicit delete over a CONTAINED/SPILL/KEEP declared policy (bike/built, cryopod, robot mmi, ~20 sites) can't use the final form. | Add `policy = null` to `rel_clear`, forward to `own_clear`. Prefer declarations (A5) where the override is static. | V |
| A5 | `code/datums/ownership/table.dm:~233` | A subtype's `owns()` entry replaces the parent's policy (last wins), but `starts` is only stored when non-null, so a subtype can't remove an inherited `starts`. That's why `bike/built` creates a cell and immediately deletes it. | `starts = STARTS_NONE` sentinel (or `no_starts(var)`) that overrides; `own_init_starts` skips it. Then bike/built declares no cell. | V |
| A6 **DONE (a, b, c and the mecha, robot, redgate and soulcatcher sites)** | 24 `destroy_qdel_owned` sites (`tools/ci/decl_baseline.txt`) | Cleanup written by hand in `on_destroy`. Missing declarative pieces: (a) a conditional policy *with a destination* (mecha parts → wreckage when wrecked); (b) conditional spill-on-death successor (robot mmi); (c) symmetric back-links (redgate target, soulcatcher gem); (d) plain policy declarations for the rest. | Add `if_var` + transfer-target policy; use `rel_one(..., back =)`; plain `owns(policy=)` for the simple ones. | V (sites), L (forms) |
| A7 | `rel_*` dispatch | Dispatches OWN → list_state → rel_view using different tables; a var declared in two tables has undefined precedence. | Boot-time assert or lint: a var is declared in at most one table. | S |
| A8 | Dynamic var-name sites (codecs.dm:110/121, serializer.dm:506, fabricator.dm:258, gas_watch.dm:104, revolver.dm:313) | The analyzer can't resolve the declaration, so conversion is blind. | Trace each type's `ownership()` chain by hand; pin the policy with a unit test before converting. | V |

## B. Stats and holds

| ID | Where | Problem and reasoning | Change | Conf |
|---|---|---|---|---|
| B1 | `code/engine/stats/store.dm` vs `code/datums/om/contribution.dm` | Two hold stores with separate `held_on` and override logic. On source death the stats store keeps timed unbound holds running; the OM store releases everything. The same effect can sit in both with different expiry. | Convert `om_hold`/`om_apply` callers to `hold()`; delete contribution.dm. Until then, a test that destroys a source holding both and asserts the intended rule. | V (stats), L (OM) |
| B2 | `store.dm:130` `stat_hold_place` | Lookup keys on (stat, source, key), not the override flag, so hold then override-hold for the same source appends a second row; `release` may drop only one. | Replace the existing row's value/flags, or key on the flag and release all rows for the source. Add a hold → override → release test. | V (dup), L (leak) |

## C. Timers and `every()`

| ID | Where | Problem and reasoning | Change | Conf |
|---|---|---|---|---|
| C1 **DONE** | `code/datums/capabilities/timed.dm:96` → `code/datums/reactions/timer.dm` → `code/datums/om/timer.dm` | `after()` is not engine code; it is a wrapper over the OM timer store. The OM folder can't be deleted until timers move. | Move the timer store into `code/engine/time/` (the doc's planned folder); `after()` becomes native. | V |
| C2 | `code/engine/actions/every.dm:67,76,198` | The gate (`when`) and `every_interval()` run outside the try, and re-arming is the last statement. One runtime in a gate stops that `every()` for the instance's life. Mass conversion of ~110 periodic files would make this common. | Re-arm before running the gate, or put gate and interval inside the try. | V |
| C3 | `every.dm:51` | `every_interval` calls the handler-style proc with `null`, but the documented signature takes `datum/act/A`. A handler reading `A.holder` runtimes, then C2 kills it. | Pass a pooled context. | L |
| C4 | `timer.dm:29,703` | A deleted datum argument arrives as null and the handler still runs (only `after_if_alive` drops the call). Every `after()` handler taking a datum must null-check. | Lint, or a form that declares required arguments. | V |
| C5 **DONE** | `timer.dm:25,55,65` | Unkeyed world timers locate by ref text without a token check; a reused ref could fire on the wrong datum. | Always record a token. | S |
| C6 **DONE** | `timer.dm:686` | The fire loop rescans the owner's whole timer list for every pop. That is quadratic for an owner with hundreds of timers (global/world owner). | A heap or sorted insert. | V (perf) |

## D. Actions, notices, `on_change`

| ID | Where | Problem and reasoning | Change | Conf |
|---|---|---|---|---|
| D1 | `code/engine/actions/act.dm:95-109`, `hooks.dm:399` | `act_depth`/`act_chain` are incremented around hooks and actions with no restore on runtime, and nothing ever resets them. After 8 runtimes in action hooks, every `ACT_TRY` is refused as too deeply nested and all notices queue late, server-wide, for the rest of the round. **Highest-severity finding.** | Save and restore in `act_begin`/`act_end`; also reset both at the start of each kernel tick (phase K) as a backstop, with a log line when the reset is non-zero. | V (code), not run |
| D2 | `notices.dm:163-173` | `notice_drain_late` sets a draining flag and delivers outside a try; a throw leaves the flag set and the late queue never drains again. | try/finally-style flag clear. | L |
| D3 | `notices.dm:89,165,172`, `change.dm:217` | Late-queue rows hold strong refs (hard deletes) and drop notices for holders deleted while queued, including their dying notice. Pass exhaustion (8) is silent. | Weak holder refs; log pass exhaustion; decide whether dying notices are exempt. | V |
| D4 | `change.dm:227,234` | `on_change` conditions and value reads in the drain run outside the try; one throwing condition aborts the drain and strands pending entries. | Move inside the try. | L |

## E. Kernel, requests, systems

| ID | Where | Problem and reasoning | Change | Conf |
|---|---|---|---|---|
| E1 | `code/engine/kernel/requests.dm:126-139,359,384` | Owner death is found only by a 1 s sweep; meanwhile the prompt stays up, the request holds a hard ref, and a late answer at :359 doesn't test `QDELETED(owner)`. The op side does cancel properly (run.dm:456-576). Whether the pending op is torn down before the request's handler is skipped is untraced. | End requests from the owner's `on_destroy` (a relation) instead of sweeping; add `QDELETED` to the answer path; a test that kills owner/target/actor mid-prompt. | V (sweep), L (ordering) |
| E2 | `request_open` | A request with no timeout pins its owner until the owner dies; the sweep is the only backstop. | Require a timeout (assert or lint). | V |
| E3 | `runechat_service.dm:16-19` | Pops from the end of an append-ordered queue, so chat bubbles are delivered newest-first. | Index cursor. | V |
| E4 | `vis_overlay_service.dm:30` | The snapshot walk reads `overlay.unused` without a null guard; an entry removed since the snapshot runtimes. | Null guard. | L |
| E5 | `turf_cascade_service.dm` | `remaining -= next` is O(n) per step. | Index cursor. | V (perf) |
| E6 | SSair, machine_service, explosion_service | Not audited for yield and cursor correctness. | Audit. | — |

## F. Missing forms (block finishing the migration)

| ID | Missing | Blocks | Change |
|---|---|---|---|
| F1 **DONE** | **Actor-kind requirement**: no `req_actor_kind(types, because=)` in `cond.dm` (only alive/conscious/capable/adjacent/rights) | Items/structures sites gated on "is a silicon/ghost/etc. clicking" | Add it to cond.dm. |
| F2 | **Player-proximity relevance**: no "only while players are nearby" gate | Item and structure periodics that should park when nobody's around | A relevance stat contributed by client proximity; `every(when = STAT_RELEVANCE)` parks on it. |
| F3 **DONE** | **Ghost view on ops**: `observer()` exists, but `by(AFF_OBSERVE)` for ops and a read-only view output don't | Reagent dispenser and synthesizer ghost view, hydroponics ghost harvest | Build `by(AFF_OBSERVE)` + view output. |
| F4 | **Prompt mid-action / resume policy**: `asks(..., resume = CAPTURE)` exists, but there's no policy for an op interrupted while a prompt is open; multi-step flows (32 sites) | om_ask retirement; 10 machines kept whole (cable/floor layer, holoposter, mass driver, point defence, requests console, fax, conveyor...) | Define interruption semantics plus a flow form. |
| F5 | **Gas watch replacement**: no engine form for `om_watch` gas | 14 files, pipenet | Gas-change publish form. |
| F6 | **AI brain / behaviours**: no engine form for combat AI; looping sounds need a capability with `every()` | `om_attach` remainder | Design the AI form. |
| F7 | **Machine pipeline**: replacement is "machines → stats + `every(when=)`", not built | 25 files | Its own track. |
| F8 **DONE** | **Timers into the engine**: see C1 | Deleting `code/datums/om` | — |

Replacements that **exist** and only need caller conversion: `wait()`/`silent_wait()`/`claims()` for `om_task_timed`/`om_busy` (prove `claims()` covers `om_busy`); `open_request`/`asks` for simple `om_ask`; `ACTION()`/`PUBLISH` for `OM_EMIT`; `every()` for `DECLARE_PERIODIC`/`DECLARE_REPEAT` (after C2/C3); `/datum/io/*` for `om_io`; `granted_verb()` and `grant()` for `om_grant`.

## G. Layering, lints, docs

| ID | Where | Problem | Change |
|---|---|---|---|
| G1 | `code/engine/library/spaces.dm` (sole file) | An engine file under a "library" folder naming `/obj/item/cell`, `/obj/item`, `/mob/proc/tk_ready`. That is engine → content. | Move it into `code/engine/parts/` (or similar); push the content-typed bits (cell bay) into `code/library/`; delete `code/engine/library/`. |
| G2 | `code/engine/kernel/inbox.dm:97,159`, `lifeforms/input.dm:134` | `var/obj/item/held` in the engine. | Type it `/obj` or `/atom/movable`. |
| G3 | tools/analyze | No layering lint covering `code/engine/**` → library/content. | Add one. |
| G4 | Near-zero legacy forms with no ban: `DECLARE_VERB` (4), `EVENT_HANDLER` (1), `DECLARE_UI`/`UI_ACT` comment residue, `om_after` (~7–38) | Cheap wins. | Convert the last callers, then hard-ban (per AGENTS §3b). |
| G5 | `final_api.html` §19 (still "0b, clean base (now)"); AGENTS §3a (`wait`, `asks`, `open_request`, `granted_verb` marked new); `completion_plan.md` (09-27, links a missing migration_plan.md) | Agents plan from wrong state. | Update §19 and the AGENTS table; archive completion_plan.md. |
| G6 | `om_retirement.md` §7 counts disagree with fresh greps (`OM_EMIT` 110 vs 13 files; `om_attach` 44 vs 12) | Unclear progress. | Recount with a script and record the command. |
| G7 | `rel_remove` doc comment ("disposed of by on_destroy") vs `rel_take` ("keeps it") | Misleading. | Fix wording. |

## Suggested order

1. D1, C2, D2, D4: cheap robustness fixes that stop one runtime from silently disabling whole subsystems.
2. A1–A5: fix the ownership API before more Codex-style mechanical sweeps (adds `rel_take_all`, `STARTS_NONE`, `rel_clear(policy)`).
3. E1–E3, B2.
4. F1–F3, then C1 (timers into the engine).
5. F4–F7 as design tracks.
6. G5 docs, then G1–G4.

## Notes on what landed (rewrite/lane-b)

- **F1**: `req_actor_kind(types, because =, not = FALSE)` in `code/engine/parts/cond.dm`; works in `needs()` and in `when()`. Converted: every
  `req(T, of = ON_ACTOR)` / `cond_not(req(T, of = ON_ACTOR))` site under `code/game`, `code/modules` (33 files), the AI slipper's locked panel
  (`any_of(req_is(locked, FALSE), req_actor_kind(silicon))`, no proc), the robotics console's arm and nuke (the old "silicon detected" bail-out is now the op's refusal).
- **F3**: `by(AFF_OBSERVE)` already existed as the `observer()` binding (the ghost mob provides it). New: `interface(..., observe = TRUE)` adds the read-only
  `ui_observe` op (`extend("ui_observe", needs(...))` gives it the window's requirements; an observer's tgui state is update-only). The reagent dispenser and
  synthesizer use it (their `declare_interactions` ghost view is gone); the hydroponics tray's ghost harvest is the `ghost_harvest` op (`observer()` + `asks(yes_no)`),
  and `/datum/ghosttrap/proc/candidate_refusal()` is the pure form of `assess_candidate()`.
- **A6**: `owns(..., policy = OWN_HAND_OVER, successor = nameof(var), successor_var = nameof(x.var))` (declared as `owns_one/owns_many(on_destroy = ON_DESTROY_HAND_OVER,
  successor =, successor_var =)`): the value moves to the successor and is added under its var; with no successor it is deleted. `owns_one/owns_many(only_if = nameof(flag),
  otherwise = ON_DESTROY_X)` is the declarative conditional policy (`if_var`). Used by: mecha cell, tank and internal components (to the wreckage), the robot's MMI
  (`mmi_ejects`: spilled once the borg had a mind and a place), redgate (the existing `links()` pair clears both sides at teardown; `toggle_portal(closing = TRUE)`),
  and the soulcatcher brainmob (`ref_one(gem)`; `container` was already a declared view). The `destroy_qdel_owned` baseline lost those sites.
  Back-links (c): `links()` already generates the symmetric back-link, so no new `back =` form was needed.
- **C1, C5, C6**: the timer store moved to `code/engine/time/` (`handles.dm`: handles and weak arguments; `timers.dm`: the store, the clock and the wheel behaviour;
  `after.dm`: `after()`, `after_if_alive()`, the keyed forms), the record layout defines to `code/__defines/engine/time.dm`; `code/datums/om/timer.dm` and
  `code/datums/reactions/timer.dm` are gone. World-clock timers name their owner by handle (generation is the token), keyed or not. The fire loop pops a per-owner
  min-heap (`rec.timer_heap`, lazy deletion, compaction) instead of rescanning the owner's list; `rec.timers` keeps its id-sorted layout.
