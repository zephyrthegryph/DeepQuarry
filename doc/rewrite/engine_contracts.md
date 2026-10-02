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
| E2 parts | `e0_perform_op`, `e0_action_options`, `e0_screentip_for`, `perform_intent`, `explain_click`, `assert_resolves`, `res_spend` |
| E3 stats | `hold`, `hold_until`, `hold_override`, `release`, `release_all`, `held_by`, `held_by_source`, `hold_left` |
| E4 actions | `e0_act_try`, `act_done`, `act_cancel`, `act_outcome_to_op` |
| E5 | none left: `night_shift_active` is generated (`code/engine/_generated/system_accessors.dm`, `analyze gen system_accessors`) |
| E6 kernel | none left: the kernel forms and the inbox are real (see "E6 as built"). What still reports to the driver is E2's side of them: `input_resolve_click`, `input_resolve_menu`, `input_resolve_ui` and `request_op_resume` |

## Name clashes (what E0 chose)

| Final name | On master | Choice |
|---|---|---|
| `perform_op`, `action_options`, `screentip_for`, `grant`, `revoke`, `granted` | live legacy procs with other shapes | stubs are `e0_*`; `dq_e0_aliases.dm` aliases the final name around the proofs only. Each engine deletes the legacy proc and the alias. |
| `cap_of` | legacy `cap_of(atom, key)` | not stubbed; E1 replaces it in one change |
| `TRACKED`, `SYSTEM_DEF`, `MSG_DEF` | legacy macros | no marker; final-form lines are in comments |
| `AFF_CONTROL` | `MANIPULATE \| INTERFACE`, with `AFF_INTERFACE`/`AFF_TELEKINESIS` | untouched; E2 redefines when it deletes the legacy bits. `AFF_ATTACK`, `AFF_OBSERVE` added |
| `/datum/notice/hit` | live notice | no `hit` notice or fields in the contracts; E4 retires it |
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
