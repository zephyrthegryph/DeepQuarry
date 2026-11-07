# Compiled op dispatch

Status: slices 1 and 2 in `code/engine/parts/resolve.dm`, `provider.dm`, `dispatch.dm`; slices 3 and 4 open (below).
Design it serves: `final_api.html` section 8 "Resolution", "Resolution cost"; section 9.

## The question

Item use measured 15 ms per use, a right-click menu 31 ms, a melee hit 6 ms (`active_play`, November 7). Is the op system badly designed?

The authoring model is fine: one `op()` declaration gives the click, the menu row, the AI's `perform_op()`, the refusal reason and
the explain trace, and none of that has to change. The execution model is what costs: every click re-derives at click time what is
fixed for its input shape, builds a record for every candidate, sorts them all, and works out refusal material nobody asked for.

## What a click cost (profiled, `perf/active-play` fc095aec32, `--profile`)

The profiler inflates call-heavy code (every call pays its overhead), so the absolute numbers are high; the shares and the counts hold.

`ap_item_us_per_use` (14.9 ms) is not one op: it is a pickup, two toggles and a drop. The op resolver is 2.6 ms of each toggle.

| Stage (per toggle, `attack_self` -> `op_resolve_click`) | ms | calls |
|---|---|---|
| candidate collection (`op_collect_side` self, `op_rows_for` 39 string keys, `op_index_of_def` walk of ~36 grants) | 0.37 | 3 + 39 |
| pass 1 filters (`op_add_cand`, `op_silently_dropped`, `/datum/op_cand` records) | 0.22 | 6 cands |
| providers (`providers_for` walking every grant's `provides()`, the `hands()` condition) | 0.70 | 1 (2 scans) |
| reach gates | 0.18 | 4 |
| sort | 0.06 | 1 |
| pass 2 `when()` | 0.01 | 1 |
| op context (`op_act_for`, pooled act fill) | 0.17 | 1 |
| requirements (`op_require_reason`: three `settle_for_reads`, purity guard) | 0.18 | 1 |
| run and effects (`op_do`, the switch) | 0.18 | 0.4 (60% refused in Require) |
| end (`op_end`: refusal told, log, `op_done` notice, release) | 0.22 | 1 |

| Stage (per melee hit, human on human, toolbox, harm) | ms | calls |
|---|---|---|
| candidate collection | 0.53 | 3 + 37 |
| pass 1 (`op_add_cand` 52, `op_silently_dropped` 52, `op_cand_pass1` 51, 64 `datum/New`) | 3.45 | 52 cands |
| providers | 0.63 | 1 |
| reach gates | 0.07 | 2 |
| sort | 0.03 | 1 |
| pass 2 `when()` + op contexts | 0.33 | 2 |
| requirements | 0.25 | 1 (the hit is refused: no `op_do`) |
| end (refusal told) | 0.25 | 1 |

49 of the 52 melee candidates are the target's stance variants (`stance(I_HELP)`, `stance(I_DISARM)`, ...): a fact of the input shape,
dropped only after a record was made for each. The menu read builds every candidate of the target with no intent filter, runs `when()`
and every requirement (three `settle_for_reads` each) for each, and its cache key holds the act generation of the actor and the target,
which a human bumps on almost every state change, so it misses.

Bench artefacts found on the way: every melee hit is refused in Require (the phase measures a resolution plus a refusal, never damage),
and most toggles are refused. `active_play` now records the outcomes (`ap_melee_outcomes`, `ap_item_toggles_switched`).

## Search at click time that is a lookup

| Work | Today | Fixed by |
|---|---|---|
| A holder's rows for a shape | a string key per index (1 + one per grant: ~37 on a human), a walk of every activation | the side rows, interned per holder until its capability generation moves |
| Shape gates (origin, authority, binding kind, intent, `stance()`, `gesture()`) | per candidate, after its record | applied once when the side's compiled table is built |
| Order by intent rank, tier, side, declaration | an insertion sort of every survivor | the table is pre-ordered; three sides merge by (rank, tier, side) |
| Providers | every grant's `provides()` walked per click | the holder's provider rows interned with the side rows; only their `when()` asked |
| Winner | pass 1 for every candidate, then pass 2 | best first: a group's gates, then `when()`, stop at the first that answers |
| Refusal reasons, near miss | built on every click | only when nothing answers and the reason is to be told (the full resolver) |

What stays per click because it is an instance fact: a tool's quality, `held == holder`, an `at_target()` filter on the target, reach
and exposure, `when()`, the path to a space, Require. Those are the work a click fundamentally needs.

What is fine: the op compiler (`plan.dm`), the plans and the indexes (built once per type, inherited by subtypes), the requirement and
condition grammar, the pooled act, the two-pass split itself, and Require/Do/End. The design (section 8 "Resolution cost") already says
"pass 1 builds the ordered candidate list from an interned index keyed by intent and held type": master interned by part of that key.

## The model

- **Shape**: (side, origin, authority, gesture and its intents, held type, actor stance). `op_side_rows(holder, ...)` merges the holder's
  table rows and each running grant's rows for the shape (no stance), interned on the type's index for a holder with no grants, else in
  `rx.op_dispatch_memo` until `set_capability_generation()` drops it (every attach, end and restack moves it; the activation count guards
  the window inside an attach). The full resolver reads the same rows, so `op_resolve()` is the same resolution, cheaper.
- **Compiled side table** (`op_fast_side()`, `dispatch.dm`): the shape rows the shape's gates let through (`op_fast_row_rank()`: origin,
  authority, actor-side binding, keyed bindings, intent rank, `stance()`, `gesture()`), stably ordered by (rank, tier desc, collection
  order) and split into groups that tie on rank and tier. Interned beside the shape rows by stance.
- **Walk** (`op_click_resolution()`, `op_fast_more()`): the groups of the three sides merge by (rank, tier, side). A group's rows get
  their instance gates (`op_cand_pass1()`, unchanged), its survivors are ordered by binding specificity (`op_specificity_sort()` on one
  run is exactly the full sort's run), and the walk hands them to `op_resolution_winner()`, which stops at the winner. A shape with a
  relative priority or a click order makes the whole order first and moves it with `op_order_relative()`, as `op_resolution_sort()` does.
  Decline and `passes()` chains continue the same walk (`op_resolution_next()`).
- **Refusal on demand**: with no winner and a reason to tell, `op_resolve_click()` asks `op_resolve()` for the near miss and the gate
  reason it has always given. A quiet click (a player's, which falls through to the legacy handling) computes none.
- **What does not take the compiled path**: no gesture (a menu read, a pick or UI press by key), `ORIGIN_SYSTEM`, `ORIGIN_MENU`, and an
  actor the actor gate refuses; they resolve with `op_resolve()`, which explain, the tests and `perform_intent()` keep using.
- **Parity**: the unit-test build compares every compiled click with `op_resolve()` (order and winner) and raises a runtime on a
  difference (`op_click_parity_check()`), so every click test is a parity test. `GLOB.op_resolver_legacy` runs the old collection, for a
  bench to measure both in one run.

## Slices

1. Dispatch rows and provider rows interned per holder; the key path reads `by_key` (no walk of every op a grant brings). Gate: the op,
   menu, click-order, keybind and ability tests green; `active_play` item toggle and melee down.
2. Compiled click: shape-gated, pre-ordered side tables, best-first walk, refusal on demand, parity in tests. Gate: as 1, plus
   `dq_op_compiled_*`; melee resolution from 52 candidate records to the few that reach their group.
3. Zero allocation per click: the walk keeps flat state in a pooled resolution (no `/datum/op_cand` per row; the winner's record is pooled
   with it), the reach gate's lists become scratch, and `op_begin()` does not re-test the `when()` the walk just tested. Gate: `datum/New`
   per click in a `--profile` run at most one (the `op_result`).
4. Menu cache per (actor, target, held), validated by the reads its rows recorded (`op_menu_record_reads()`, the lookup read scope) and
   the provider generation, not by the act generation that every human state change bumps; `settle_for_reads` once per menu, not per row.
   Gate: `ap_menu_warm_us` near zero, `ap_menu_cold_us` down, `dq_read_once_menu_*`, `dx_menu_order*`, `dq_ops_menu_*` green.

## What the Rust side could own

Nothing on the hot path yet. The candidate tables are DM datums and the gates call DM procs (conditions, reach, requirements), so a
crossing per click would cost more than the walk now does. If the shape tables were ever flattened to integers (plan ids, binding kinds,
tiers, ranks), the static part of dispatch (shape filter and order) could be built in Verdigris at boot and read through one call; the
instance gates would still be DM.
