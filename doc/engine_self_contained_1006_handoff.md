# Engine self-contained extraction: 1006 handoff

Status: Final lint, explicit ratchets and focused tests passed. No full suite was run.

## Base and integration

Branch: `codex/engine-self-contained-1006`. The extraction started from master `e73f620`; master batch 4 through `1cf77b9d89` was merged by `208b4f4f1b`. Do not lose the batch-4 machine condition/stat conversions, removal of the old machine periodic special cases, READS_FROM(E) in stat_value(), registry mirror hooks, or the newer downstream relation identities. Stats/lifeforms merge audit found those substantive intents preserved.

## What moved

Actual generic implementations now live under engine actions/change/declare/hooks/io/kernel/lifeforms/parts/present/refs/state/stats/time. Content-facing work remains behind real implemented downstream adapters: native binding and lookup; physical/item slot transport; machine/body/access policy; operation ranking and legacy operation transport; progress/UI/sound/appearance transport; timed-task and request context policy. Canonical APIs call the moved implementations. Old OM spellings remain downstream forwarding aliases where old callers still exist; wrappers do not own another implementation or change arguments/order.

Against the currently fetched origin/master, the working diff changes 140 engine files by folder: actions 8, change 6, declare 15, hooks 4, io 2, kernel 10, lifeforms 6, parts 18, present 11, refs 25, state 19, stats 5, time 11. These are changed-file counts, not claims that every file is newly extracted.

Every() gains explicit phase/lane delivery and budgeted member sweeps while retaining default intervals, gating/parking, cancellation and timescale behavior. Per-member work snapshots weak handles, rechecks membership/deletion, yields through kernel work, and avoids an interval backlog. Operation held-provider typing uses a genuine action interface and borrowed reference declaration; original inventory field/tool metadata remains with its item owner. Ranking and catch-all distinctions remain downstream and stable.

## Real base-field cleanup

The post-merge cleanup removes moved per-instance fields instead of renaming their baseline identities. Runtime caches use existing lazy reaction state and actual accessors. Appearance look key, overlays, hidden/granted verb decisions, sweep participation, set bits, filters and visible-content caches moved into rx_state; read-only probes do not allocate it. Renderer cleanup order is unchanged.

Declaration-only latent-safe, latent-contents, idle-delay and slot-hook policies now use an actual inherited type metadata registry: 219 explicit declarations migrated to production/test registration hooks. Queries follow real parent_type without constructing a content prototype, retain explicit FALSE subtype overrides, and retain default values. The normal definition-registry startup initializes the policy registry; tests can make private registries. The analyzer recognizes those actual registrations so state/storability checks continue rather than silently disappearing. Obsolete base-var annotations are removed when the original field disappears.

Other field cleanup in this working batch includes native/runtime ownership and containment storage; the root agent should finalize its exact list from the staged diff.

## Independently confirmed baseline reductions

Counts below were read from the actual baseline files and git show origin/master, counting nonblank noncomment rows. They are removals only, with no added identities:

| Lint | origin/master | Working baseline | Removed |
| --- | ---: | ---: | ---: |
| base_vars | 981 | 912 | 69 |
| instance_list | 48 | 0 | 48 |
| sys/dx_review | 211 | 205 | 6 |

The strict engine-layering rule has no baseline or ALLOW escape. The corrected semantic scan recorded 1,524 external dependencies (`corrected-before-layering.log`). The earlier weak 790-count scan missed reopened downstream declarations and is not the authoritative starting count. Corrected findings by engine folder: actions 27, declare 89, io 2, kernel 71, lifeforms 15, parts 1133, present 42, stats 14, time 131. The confirmed final lint run (`data/codex-self-contained/batch4-lint-final2.log`) reports engine_layering external_dependency 0 and semantic_model 0, all ratchet lints passing, zero unused ALLOW annotations, zero DreamChecker diagnostics, and clean TGUI checks.

## Regression coverage and fixes

New focused tests cover periodic phases/lanes/parking, revoked activations and sweeps, yielding member rechecks, action/legacy policy adapters, binding ranking, held-provider identity/deletion/pool reuse, inherited type metadata, and appearance cache allocation/take-back. Relevant new names include:

- dq_every_options/phase_lane_and_parking; revoke_ready_activation; system_members; member_sweep_yields_and_rechecks; revoke_member_sweep_continuation.
- dq_engine_policy_callback_compatibility; request_context; biological_clock; insert_transport; binding_ranking; tool_provider.
- dq_type_metadata_inheritance; dq_look_cache_lifetime.
- dq_destroy_transaction_runtime_ledger_order; dq_destroy_transaction_runtime_ledger_abort; dq_capability_runtime_aborted_data_cleanup; dq_destroy_transaction_late_abort_hook_once.

Existing foundation, timing, containment, codec, lifecycle, operation, world-wake, appearance, UI and storage tests were selected as appropriate by the root agent. Exact focus manifests/logs are under data/codex-self-contained.

Timer argument resolution now restores its scratch nulled counter before invoking a callback, including exceptional resolver exit; deleted-argument debug logs and actual timer counters remain. The existing deleted-list-argument regression checks restoration of a deliberate nonzero sentinel. Latency diagnostics and lifecycle test snapshot caches are restored through normal test teardown; assertions and production diagnostics are retained.

Runtime ownership cleanup also preserves the declared disposal position of nested containment ledgers. If teardown aborts before ownership cleanup, declared policies still dispose children; mandatory runtime cleanup runs even when an earlier child or registry hook faults. Capability-instance data is forgotten after completed or aborted deletion, while LETMELIVE retains it. The late-phase guard avoids repeating a completed destroy hook after a later phase faults. Regressions assert actual owned ledger/data deletion, ordering, detached runtime state, and exactly one destroy-hook invocation.

## Verification

The first inspected 90-test run finished with 89 passing and one failing test, plus state-isolation diagnostics (`data/logs/run1/tests.log`): an ownership orphan and test-state isolation findings were reported. Isolation and ownership fixes were applied afterwards. The subsequent 24-test focused run (`data/codex-self-contained/batch4-focused24-tests.log`) passed all 24 tests with a clean boot gate and no state-leak or ownership-orphan diagnostics. The earlier full analyze run also failed base_vars before real field cleanup.

Confirmed final lint is clean: zero DreamChecker diagnostics, clean TGUI, hard engine-layering zero, all analyzer ratchets passed, and no unused ALLOW annotations. Both final focused compiles had zero DreamMaker errors and 29 existing unused-variable warnings. After the 24-test pass, six focused lifecycle tests passed on the final source, including the late-abort exactly-once hook regression. Both runs had clean boot gates and no state-leak or ownership-orphan diagnostics. The explicit `check_ratchets.sh` wrapper also passed on this final source.

The two changed analyzer behaviors also have filtered Rust tests: inherited latent metadata registration and runtime capability payload holder identity both passed. No full test suite, shard sweep or E0 tier was run. Only this branch will be pushed; master remains the integration owner's responsibility.