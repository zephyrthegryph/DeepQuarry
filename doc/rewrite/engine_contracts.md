# Engine contracts (E0)

What step E0 of the rewrite (`final_api.html` section 19) delivers, so that E1 to E6 each have their inputs and outputs named.
Nothing here has runtime behaviour except the test driver's own bookkeeping. Engines do not start in E0.

## File map

| Path | What |
|---|---|
| `code/__defines/engine/markers.dm` | Declaration markers (`CAPABILITIES`, `ACTION`, `STAT`, `SCHEMA`, `SYSTEM_ACCESSOR`, `STAGE_DEF`, `STATE_GRAPH`, `RESOURCE_DEF`, `SOURCE_DEF`, `CAPABILITY_DEF/TYPE`, `cap_keys`, `BUNDLE`). Each expands to nothing: a declaration in the final syntax compiles and is skipped until the generator reads it. |
| `code/__defines/engine/vocabulary.dm` | `ACT_*` outcomes and filters, `OP_*` effect reports, `ORIGIN_*`, `REACH_*`, `AUTH_*`, `INTENT_*`, keeps, `REQ_*` outcomes, resume policies, `DRAIN_MAX_PASSES`, `KERNEL_PHASE_S`, `LANE_WORLD`. |
| `code/__defines/engine/test_hooks.dm` | The engine-to-driver seam: `TEST_REC_*`, `TEST_ROLL`, `TEST_LANE_BUDGET`, `TEST_EVAL_COST`, `ENGINE_STUB`, `E0_GATE`. In production every one compiles out. |
| `code/contracts/ids/` | Hand-assigned stat, source, tag, resource, capability and stage ids (the generator keeps what is there). |
| `code/contracts/acts/` | The five context types (`/datum/act/op|eval|notice|timer|request`) on `/datum/act` and `/datum/act/action`; `/datum/op_result`; the world-action act types and past-tense notices. Vars only; all pooled (`/datum/pooled`). |
| `code/contracts/accessors/` | `SYSTEM_ACCESSOR` declarations (names only). |
| `code/engine/<engine folder>/stubs.dm` | One stub per public proc, final signature, reports `ENGINE_STUB` and returns null. |
| `code/tests/driver/` | The test driver and the recorder. |
| `code/tests/engine/fixtures.dm` | Test-only capability registry and fixture types. The capability lists are written in the final syntax as markers. |
| `code/modules/unit_tests/dq_e0_*.dm` | The ten proofs and the alias shim around them. |

The contracts and defines are included right after `code\__defines`, before `_helpers` (compile order 2). Engine stubs are included before
`code\_generated`. `code\tests\_tests.dm` is included just before `_unit_tests.dm` and is guarded by `UNIT_TESTS`.

## The driver

Real from E0 (pure bookkeeping): `test_rng`/`test_rolls`/`test_roll`, `test_budget`, `test_notice_count`/`test_notice_queued_count`,
`test_spill_count`, `test_logs`, `test_record`/`test_recorded`, `test_driver_reset`, `test_counters_reset`.
Stub-backed: `test_click`, `test_ui`, `test_menu`, `test_answer` (E6 inbox, then E2), `test_drain`, `test_phase`, `test_time` (E6).

`/datum/op_result` (key, outcome, reason, rolled, origin) is plain and never pooled. The engine fills it as the op ends; an op still waiting
returns it with a null outcome and the same pending op fills the same record later.

**Report calls each engine adds** (the recorder's store belongs to E6, which replaces `test_rec_event()`; the calls are fixed):

| Macro | Caller | Row (`kind`, `entity`, `key`, `from`, `to`) |
|---|---|---|
| `TEST_REC_OUTCOME(key, outcome, reason, actor)` | E2, when an op ends | outcome, actor, key, reason, outcome |
| `TEST_REC_LOG(key, outcome, origin, actor, target, text)` | E2, with the log line | log, actor, key, outcome, text (also queued for `test_logs()`) |
| `TEST_REC_RESOURCE(event, resource, holder, amount, op_key)` | E2, reserve/commit/release | the event, holder, resource, op key, amount |
| `TEST_REC_TRANSFER(item, from, to, slot)` | E2/E1, slot moves | transfer, item, slot, from, to |
| `TEST_REC_ACTIVATION(event, definition, source, holder)` | E1, attach/detach | the event, holder, definition, source |
| `TEST_REC_NOTICE(type, outcome, queued)` | E4, delivery or queueing | notice or notice_queued, type, outcome |
| `TEST_REC_DELTA(entity, key, from, to)` | E3, a tracked var or stat of a named entity changes | delta rows, kept only for entities named in `test_record()` |
| `TEST_REC_SPILL(key_chain)` | E3, a marked pass stops at its budget | spill |

`TEST_ROLL(percent)` is what `chance()` draws; `TEST_LANE_BUDGET(lane)` is what the drain reads; each stat evaluation charges `TEST_EVAL_COST`.

## Stubs by engine

| Engine | Stubs |
|---|---|
| E1 declare | `e0_grant`, `e0_revoke`, `e0_granted`, `built`, `built_material`, `explain_type`, `explain_activations`, `schema_range_text` |
| E2 parts | none left: see "E2 (landed)" |
| E3 stats | `hold`, `hold_until`, `hold_override`, `release`, `release_all`, `held_by`, `held_by_source`, `hold_left` |
| E4 actions | none left: `ACT_TRY`, `act_done`, `act_cancel`, `act_outcome_to_op` and the notices are real (see "E4 (landed)") |
| E5 | none left: `night_shift_active` is generated (`code/engine/_generated/system_accessors.dm`, `analyze gen system_accessors`) |
| E6 kernel | none left: the kernel forms and the inbox are real (see "E6 as built"). What still reports to the driver is E2's side of them: `input_resolve_click`, `input_resolve_menu`, `input_resolve_ui` and `request_op_resume` |

## Name clashes (what E0 chose)

| Final name | On master | Choice |
|---|---|---|
| `perform_op`, `action_options`, `screentip_for`, `grant`, `revoke`, `granted` | live legacy procs with other shapes | stubs are `e0_*`; `dq_e0_aliases.dm` aliases the final name around the proofs only. Each engine deletes the legacy proc and the alias. |
| `cap_of` | legacy `cap_of(atom, key)` | not stubbed; E1 replaces it in one change |
| `TRACKED`, `SYSTEM_DEF`, `MSG_DEF` | legacy macros | no marker; final-form lines are in comments |
| `AFF_CONTROL` | `MANIPULATE \| INTERFACE`, with `AFF_INTERFACE`/`AFF_TELEKINESIS` | untouched; E2 redefines when it deletes the legacy bits. `AFF_ATTACK`, `AFF_OBSERVE` added |
| `/datum/notice/hit` | live notice | E4 renamed the legacy one `/datum/notice/legacy_hit` (its callers follow) and `hit` is the action's notice (field `packet`) |
| `KERNEL_PHASE_*` | K,N,U,D,P,R,G = 1..7 | `KERNEL_PHASE_S` = 8 outside the live range; E6 renumbers |
| `LANE_*` | five lanes | `LANE_WORLD` = 6, unknown to the scheduler until E6 |

## E6 as built (kernel completion, increments 1 and 2)

| Piece | Where | Notes |
|---|---|---|
| Phases K, S, N, U, D, P, R, G | `code/__defines/kernel.dm`, `code/controllers/kernel/kernel.dm` | `KERNEL_PHASE_S` (2) renumbered the rest; phase S has no scheduler piece and is never shed. Phase K runs its work items first (the input inbox), then the hosted services. |
| `LANE_WORLD` | `code/__defines/om.dm` | A sixth OM lane (`OM_LANE_COUNT` 6, share 0.05 taken from background), latency class L2. |
| `test_time`, `test_phase`, `test_drain` | `code/tests/driver/kernel_clock.dm` | Real. `kernel_test_begin()` / `kernel_test_end()`, `test_driver_begin()` / `test_driver_end()`; see doc/testing.md "The kernel clock". |
| The recorder store | `code/tests/driver/recorder.dm` | Rows carry `seq` and `at`; bounded at `TEST_RECORD_MAX`. |
| Systems: `phase`, `roles`, `lazy_only` | `code/controllers/kernel/system.dm` | `phase` is the default phase of a system's `every()` items; a join with a role the system did not declare (when it declares any) is a CRASH. |
| The input inbox | `code/engine/kernel/inbox.dm` | `SYSTEM_DEF(input)`, `/datum/input_event` and its kinds (click, menu, ui_act, topic, say, point), `input_submit()`. Replaces SSinput, SSverb_manager, the speech controller and the click holdback. `inbox_click`, `inbox_ui`, `inbox_menu` build driver events; the resolver seams `input_resolve_click/menu/ui` are E2's. |
| Requests | `code/engine/kernel/requests.dm` | `open_request()` (a macro over `request_open()`; the final API spells it `request()`, which BYOND's preprocessor cannot take as a function-like macro name), `/datum/request` with the kinds `/datum/prompt`, `/datum/io`, `/datum/client_query`, `request_end()`, `request_answer()` (= `test_answer`). The op engine's resume is the seam `request_op_resume()`. |
| `job()` | `code/engine/kernel/jobs.dm` | Chunked one-shot jobs on a percent-of-tick budget; die with their owner. `JOB_MORE`, `JOB_DONE`. |
| `safe_call()`, `try_parse_json()` | `code/engine/kernel/safe.dm` | `/datum/result` (ok, value, error). |
| `kernel_urgent()` | `code/controllers/kernel/urgent.dm` | `request_urgent()` renamed. |

Name clash: the communicator's `request()` is now `request_connection()`.

## Proofs and what each waits for

| Proof | Stubs it reaches today (so the engines that must build it) |
|---|---|
| 1 door density | E2 `perform_op` |
| 2 two mirrors | E1 grant/revoke, E4 ACT_TRY/act_done |
| 3 phase shift and species | E2 perform_op, E6 test_time/test_drain, E1 granted |
| 4 capture holds | E6 inbox (UI) and request answer |
| 5 refused insert | E6 inbox click, test_time |
| 6 click/UI/AI | E6 inbox click and UI, E2 perform_op |
| 7 caches | E2 action_options/screentip_for/perform_op, E6 inbox click, E1 grant, E6 test_drain/test_time |
| 8 cascade | E3 flip (SYSTEM_DEF/SYSTEM_ACCESSOR), E4 notice chain, E6 test_time/test_drain |
| 9 construction | E6 inbox click, E1 built/built_material |
| 10 schema | E6 inbox UI, E1 `schema_range_text`, E5 ui-types doc comment |

(Exact messages: run `bash tools/dq_focused_test.sh 'dq_e0_proof/*'`.)

## Choices where the design was ambiguous or not expressible in DM

- Declaration lines cannot be compiled (`CAPABILITIES(...)` references `op()`, `hand()`...). They are no-op markers that swallow their arguments.
- `ACT_TRY` is a macro with a table lookup in the design; E0 has `e0_act_try(holder, act_type, ...)` taking the act type path.
- `grant(E, mirror_plating(reflect_chance = 45))` is not DM before E1: fixtures build a spec datum with `e0_mirror_plating(45)`.
- `test_answer(actor, value | REQ_*)` cannot tell the value 2 from `REQ_CANCELLED`; an outcome is the named argument `outcome =`.
- `test_ui(actor, window, ...)`: the window is identified by the entity hosting it, passed as `window`.
- The test species is `/datum/e0_species` with a learned `species` relation, so no real species machinery is built.
- Hit and notice-chain steps use fixture helpers over the stubs, because `chance()`, ACT_TRY and the hooks do not exist.
- ids are hand-assigned integers until the generators exist.

Not in E0 (named in section 19 but outside the task given): the compiled-table schema and entry struct, the `_generated` file formats, and the E5 query interface. They belong with E1 and E5, whose stubs above name the entry points.

**E5 (landed).** The query interface is the semantic layer of the analysis engine, `tools/analyze/src/sem/` (README section "Semantic layer"): `analyze gen` writes `code/engine/_generated/` (`reads.dm`, `system_accessors.dm`), and the other engines add their generators as `tools/analyze/src/gens/<name>.rs` on the `Generator` API. The lints `sem/keys`, `sem/reads` and `sem/handlers` resolve the ids and keys inside declaration markers, check generated reads, handler signatures, context fields, context escape, ACT_TRY pairing and purity. `READS_AS` and `READS_FROM` are markers (`code/__defines/engine/markers.dm`). E4: `ACT_TRY` has to survive macro expansion as a call (`ACT_TRY`, `act_try`, `e0_act_try`) for the pairing check; add another expansion name to `[lint."sem/handlers".lists] try_calls` in `tools/ci/lint_scopes.toml`.

**E1 (landed).** The declaration engine is `code/engine/declare/` (entries, capability definitions, the table builder, scoped activation, relations and the `rel_*` verbs with `LIST_STATE`, value schemas, state graphs, explain tools). The markers `CAPABILITIES`, `CAPABILITY_TYPE/DEF`, `cap_keys`, `STAGE_DEF`, `SOURCE_DEF`, `STATE_GRAPH` stay no-ops in DM; `analyze gen declare_ids` writes the ids they declare (`code/engine/_generated/ids.dm`, included early) and `analyze gen declare` the constructors, registration rows, state-key accessors and each type's `declared_entries()` (`declare.dm`); README, "Semantic layer". The contracts no longer carry numeric stat, source or stage ids (the generator assigns them; the capability ids the contracts give by hand are kept). Where the final syntax has no DM spelling, E1 chose: `link(A::a, B::b)` is rewritten by the generator (`link` is a BYOND keyword); `configure(CAP_X, "sel", p = v)` is rewritten to `configure(<constructor>("sel", p = v))`; the schema'd tracked var is `TRACKED_SCHEMA(T, v, schema)` (the legacy two-argument `TRACKED` stays), with `schema_text()` and `schema_path()` for the schema kinds BYOND owns (`text`, `path`); `not`, `all_of` and `any_of` as condition combinators are `cond_not`, `cond_all`, `cond_any` until E2's requirement language lands. The legacy `grant`, `revoke`, `granted`, `cap_of`, `without` and `stage` keep working: the final name dispatches on its first argument and falls back to `legacy_*`.
### E6 database and path transport (increment 5)

- `open_request(owner, /datum/io/sql/<kind>, handler, field = value...)`: a kind sets `query` (`:field` binds the request's var of that name, once, in order; `bound_fields()`), `row_type` and `expects_rows`. Rows come back as `row_type` datums; no match is `REQ_NO_RESULT`; no connection or a refused query is `REQ_TRANSPORT_FAILED` with `last_error`. `sql_write(query, params)` replaces `om_sql_write` for fire-and-forget writes. `db_query_now()` is the only blocking call.
- `open_request(owner, /datum/io/path, handler, start = turf, goal = turf)`: SSpathing runs one search at a time on a detached worker; no path is `REQ_NO_RESULT`; a goal on another z-level is `REQ_TRANSPORT_FAILED`.
- Not done in E6: the legacy `NewQuery()`/`Execute()` callers (still baselined sync_sql sites) and `dq_pathfind()` stay on their old paths.


**E3 (landed).** The stat layer is `code/engine/stats/` (defs, rules, contributes, store, recompute, status, vars_write), its constants `code/__defines/engine/stats.dm`, and `analyze gen stats` (`code/engine/_generated/stats.dm`, from the `STAT(T, name, RULE, ...)` markers; ids from `declare_ids`).

- A stat's effective value is a plain var, written only by the engine (`virtual = TRUE` declares no var: read it with `stat_value(E, STAT_X)`; the base stats of `/atom`, `/obj/machinery` and `light_range` are virtual, `/mob/living` ones are vars). A stat is composed from the type's own var default (a type-level contribution at default priority), the type's `contributes()` entries whose `when()` gates hold, and the holds, by the rule in `rules.dm`.
- Holds: `hold`, `hold_until`, `hold_override`, `release`, `release_all`, `held_by`, `held_by_source`, `hold_left`. The source is a live datum or a `SRC_*` id; null or text is a build report. A timed hold outlives its deleted source unless `bound`; an untimed one dies with it. `vars_write(E, name, value, source = SRC_VV)` on a stat is `hold_override` at `PRIORITY_ADMIN`.
- Statuses (`units =`) have a companion `STAT_<NAME>_IMMUNE` ANY stat (`immune_to`). The verbs are `stat_status_at_least/set/adjust/end/remaining` and `stat_has_status` (over holds on `HOLD_CLOCK_BIO`); the final names `status_*` stay with the legacy `/datum/proc` family until its ~700 callers migrate in phase 3 (an unqualified call inside a datum proc would resolve to the legacy proc).
- Settle rule, as built: a stat var read is current on the next line. A write recomputes the entity's own stats and the stats that read them (rank order) inline, `contributes_to` targets inline, one-relation hop readers inline when the edge is single-valued; collection edges, `SYSTEM_ACCESSOR` reads and multi-hop reads are marked (`GLOB.stat_marked`) and `stat_drain_marked()` recomputes them in rank order at the start of phases D, P and R under the lane budget shared by one kernel pass (`stat_tick_begin()`); what does not fit spills to the next drain (`TEST_REC_SPILL`). Initial evaluation at init is silent.
- Hooks into master code: `changed()` (var inputs), `own_field_changed()` (relation inputs), `rx_teardown()`, `engine_holder_init()`, the kernel's D/P/R phases and `test_slot()`, `condition_id_holds()` (a stat id is a condition).
- Not in E3: the legacy contribution store (`code/datums/om/contribution.dm`) stays authoritative for its `EFFECT_*` ids until phase 3; `BF_*` body-factor ids and the `/mob/living` status stats are phase 3 content; `grant()` of a SET stat's token is `hold(E, STAT_X, token, source)`.
- E5 integration: `contributes(STAT_X, PROC_REF(x))` reads come from `generated_reads_table`; a FORMULA stat's reads are written by hand (`reads = list(...)`) because a formula is not a hook handler. `analyze` now also treats the relation entries of `CAPABILITIES` blocks (`ref_one`, `owns_many`, `link`) as declared relations, and the system accessors and stat vars of test fixtures are generated inside `#if defined(UNIT_TESTS)`.
- `apc_flip_50` (`code/modules/benchmarks/apc_flip.dm`): one APC channel over 50 machines, per flip: old path (real machines running the body of `power_change()`) 0.82 ms, inline recompute 0.84 ms, marked plus drain 1.20 ms.

**E4 (landed).** The action and hook engine is `code/engine/actions/` (`act.dm`, `hooks.dm`, `notices.dm`, `change.dm`, `twins.dm`), its forms `code/__defines/engine/actions.dm`, and `analyze gen actions` (`code/engine/_generated/actions.dm`, from the `ACTION()` lines of `code/contracts/acts/world_actions.dm`) and `analyze gen event_twins` (`event_twins.dm`, from `tools/dx/codemods/om_event_map.json`).

- `ACTION(name, typed fields..., FIXED, notice =)` generates the act type, `act_<name>(holder, fields...)` (what `ACT_TRY(E, name, fields...)` expands to) and the past-tense notice with the same fields; a `hit/projectile` style name inherits its parent's fields (`act_hit_projectile`); a FIXED action has no act and `PUBLISH(E, name, field = v)` is `publish_<name>()`. A field called `origin` is `origin_turf`. The `op` action keeps the op context as its act and gets only `/datum/notice/op_done` (E2 sets `op_key`, which `on_op` filters on).
- `act_<name>()`: ACT_PASS when `act_wanted()` finds nothing (no hook of the action on the holder's table or activations, and no listener for its notice for any outcome, legacy `on_notice` and the OM event twin included); else `act_begin()` (depth cap), then `act_resolve()`: needs (the requirement language is E2's: `act_needs_refusal()` is the seam), the first `instead` in order (`when()`, `chance()` and `then()` parts; other parts reach `act_run_part()`, E2's), then every `adjusts()` (`field` is text, scale before by). `act_done(A)` ends ACT_COMMITTED and `act_cancel(A)` ACT_REFUSED, each delivering the notice only to listeners that asked for the outcome (`on_notice(..., outcome =)`, values combine with `|`; an outcome nobody asked for builds nothing), then releasing the act. `ACT_FINAL(F, field, local)` is the act's field, or the caller's local on ACT_PASS.
- A `/datum/notice` is a `/datum/act/notice` (parent_type) and pooled; it is also the context its handlers get (A.holder the entity whose entry runs, A.target the publisher, A.source the activation's source, A.outcome, the typed fields). A notice delivered by the engine also reaches the legacy `on_notice()` reactions of its holder, and a legacy `publish()` reaches the hooks, so both sides hear one occurrence.
- Depth: `GLOB.act_depth` counts running handlers. A nested notice published at depth 8 is queued (`GLOB.notice_late_queue`), delivered at the next drain point (`act_drain_point()`, called from `stat_drain_point()`, the start of the kernel's D, P and R phases) and reported through `act_report()` (a runtime that fails a test build; a test captures it in `GLOB.act_report_capture`); a nested action at depth 8 is not taken, ends ACT_REFUSED ("too deeply nested", `TEST_REC_OUTCOME`) and reports the same way.
- Hook forms: `extend(/datum/act/x, instead(...) | adjusts(field, by =, scale =, when =) | needs(...))` (parts are `/datum/entry`s, declared in `CAPABILITIES` and copied by the generator, which writes `adjusts(packet.amount, ...)` as `adjusts("packet.amount", ...)`), `on_notice(/datum/notice/x, parts..., outcome =)`, `on_op(key, parts..., outcome =)` (an `on_notice` of `op_done` with `op =`), `on_change(cond, ENTER | EXIT | ANY, parts...)`, `hook_capability(entries...)`, `observe(source, /datum/notice/x, listener, parts...)` and `unobserve()`, and `while_slotted(SLOT, entries..., on =)`, which now takes any entries (those that are not capabilities are wrapped in one `hook_capability`). The final names dispatch on their arguments and fall back to `legacy_on_notice`, `legacy_on_change`, `legacy_observe` and `legacy_unobserve`. `then(PROC_REF(x))` names a proc of the holder, `then(CAP_PROC(x))` a proc of the capability datum; `then()` and `chance()` are shared with E2's op parts.
- Hooks of an activation are `/datum/hook` records on `rx.hooks` (applied by the entry engines of the kinds `extend`, `on_notice` and `on_change`, removed by the one teardown path); a type's own are compiled once per table (`hook_table_of`, `act_plan_static`). Stacking decides which activations run (a shadowed activation's hooks are skipped); a static hook of a capability that has activations on the holder is represented by them. `on_change` is evaluated at the drain; a type-level one watches through `rx_readers()` (`hooks_watching()`), an activation's through `rx_watch_adjust()`; a read through a relation hop watches the relation var itself (E3's hop reverse index serves stats).
- `PUBLISH(E, name, ...)` and `WANTS(E, TYPE, outcome)` are the final macros; the legacy forms are `PUBLISH_LEGACY(E, /datum/notice/x, args)` (positional `take_notice()`) and the rx tables. `/datum/guard_ctx` is now a `/datum/act/action`. `/datum/op_ctx` is E2's to replace with the op context.
- The twins (`twins.dm`): `GLOB.event_twin_notice` maps an after-fact OM event to its notice and the notice's fields (renamed with a trailing `_` when the generated notice could not use the event's field name, which now includes the act context's own `holder`, `target`, `outcome`, `cap`, `activation` and `op_key`). `OM_EMIT` of such an event also publishes the notice, and delivering the notice also emits the event, each only when the other side has a listener (`om_wants()` asks `event_twin_wanted()`; `notice_wanted()` asks `notice_twin_wanted()`), and the bridge does not bounce. The map's last row deletes this file's rows (step A7).
- Counters for tests and metrics: `GLOB.act_taken`, `notice_taken`, `notice_late`, `act_too_deep`.
- Not in E4: the hit entry points (`bullet_act`, `receive_damage()` ...) still run the legacy damage path (A6 converts them to `ACT_TRY(src, hit_projectile, packet)`); the `Moved()`, `Crossed()` and `Bump()` adapters; `needs()` requirements and the other Do parts (E2); the ledger's slot moves do not call `activations_slot_enter()` yet (E2's `slot()` and `put_in()`).

**E2 (landed).** The part engine is `code/engine/parts/` (`part.dm` the part constructors, `cond.dm` conditions and requirements, `plan.dm` the op compiler, `provider.dm` providers and the actor and reach gates, `resolve.dm` candidates and ordering, `inputs.dm` the click, menu, UI and topic inputs, `run.dm` the four stages and the pending op, `resource.dm` reservations and adapters, `explain.dm` the explain tools, `prompts.dm` the few prompt kinds the engine itself asks), its constants `code/__defines/engine/parts.dm`, and `analyze gen ui_types` (README, "Semantic layer").

- An op is `op(key, parts...)`; every part is an interned `/datum/entry/part` subtype whose stage hooks are procs on its type. The compiler folds an op and what is addressed to it (tool profile, own parts, group extends, key extends) into one `/datum/op_plan`, cached on the type's table (`T.op_index`; a granted capability's ops in `T.op_def_indexes`). Table build reports a plan problem (an effect above `asks()`, a `captures()` with no workflow step, a requirement with no reason, two ops with the same input, intent and tier) through `table_error()` with the op's file:line.
- Resolution (`op_resolve`): candidates from the target, the held item (`at_target`, `in_hand`) and the actor; pass 1 runs the cheap gates (actor gate on `acts_via`, origin, authority, the binding's input, intent, providers and reach), pass 2 the `when` conditions. Order: intent rank, tier, target before held before actor, declaration order, then `priority(above/below)`. The menu (`action_options`) and the screentip share it; a menu read is memoised per entity set and invalidated by an epoch (`op_changed()`: `changed()`, capability key publication, provider set changes).
- The engine (`op_begin`): Require (implicit `req_capable`, bay, `needs`, costs availability, the pre-checks of effects), Wait (a `/datum/pending_op` that holds holder, target, actor and held through declared relations with `OTHER_DELETE_ME`, so deleting one cancels the op with feedback; keeps re-checked every `WAIT_RECHECK_INTERVAL`), Do (reserve, `chance()`, effects reporting `OP_*`, commit or release, feedback, log, `op_done`). `perform_op`, `action_options` and `screentip_for` dispatch on their argument shape and fall back to `legacy_perform_op`, `legacy_action_options` and `legacy_screentip_for`; `req`, `all_of` and `any_of` likewise (`legacy_req`, `legacy_all_of`, `legacy_any_of`). The legacy `req_empty_hand`, `req_self_held`, `req_access`, `req_stance` and `req_heard` datums gained `holds(A)` so `needs()` takes them.
- The input seams: `input_resolve_click` (a player's click on a target with no op of the new engine still runs the legacy mob click, and a click on one that has ops resolves among the new ops and the legacy `DECLARE_INTERACTIONS` entries in one pass), `input_resolve_menu`, `input_resolve_ui` (`arg()` schemas validate before Match; `arg(name, from = nameof(v))` takes a tracked var's schema), `op_topic`. `request_op_resume` is now a no-op: the pending op is the request's owner and resumes through its own handler.
- Where the design is not expressible in DM, E2 chose: `do()` is `run_effect()` (`do` is a keyword); `A.step("name")` is `A.step_answer("name")` (`step` is a keyword); `chance(p, else = ...)` is `chance(p, otherwise = ...)`; `asks(..., fields = list(name = value))` names the request's fields (a proc with `...` takes no free named arguments); `captures(...)` takes up to eight fields and `resume =`; a UI or topic handler is `x(datum/act/op/A, args...)` with the declared args after A (the `sem/handlers` lint counts them); `TAG_X | TAG_Y` is not supported (the numbers collide), a list of tags is; `AFF_CONTROL` keeps its legacy value, so `remote()` asks for `AFF_INTERFACE`.
- Not in E2: the bay and compartment capabilities (`cover`, `compartment`, `cell_bay`: phase 2), `every()` and hook entries (E4/E6), the state-graph edges as ops (`construction.build:<stage>`), the `ACT_TRY` pre-check of `put_in()` (E4: `slot_precheck()` is the seam and the insert goes through the containment ledger directly), real notice delivery of `op_done` (counted for the recorder until E4), the purity guard around requirements (`op_pure_begin()`), and the admin verbs "Explain Interaction", "Explain Type" and "List Pending Ops" (the procs behind them are `explain_click`, `explain_type`, `op_pending_all_text`).
- E0 proofs: 1, 4, 5, 6 and 10 pass. 2 waits for E4 (`ACT_TRY`), 3 for `every()` and the phase-shift capability, 7 for the library's cover, compartment and cell bay (and a real telekinesis grant), 8 for E4's notice chain, 9 for the construction edges.
