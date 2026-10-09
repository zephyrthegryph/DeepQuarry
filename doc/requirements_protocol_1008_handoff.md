# Requirement protocol handoff (2026-10-08)

Branch: `codex/requirements-protocol-1008`, fresh from `origin/master` at `6daab63fe8`, followed by `tools/dq_merge_master.sh`. Push this branch only; no master merge or push.

## Scope and behavior

`req(PROC_REF(x))` now allows only null and refuses with the callback's text or message path/instance. `because` overrides the wording, including an explicitly empty silent reason. Invalid boolean/numeric callback answers fail closed. Type/list requirements retain their existing behavior. `holds()` and the engine's stage `require()` remain boolean views for dispatch; `check()` exposes null-or-reason on native and compatibility requirements. The click resolver is unchanged.

Existing boolean callbacks use the explicit `req_bool` constructor and a separate boolean requirement subtype. Their bodies are unchanged outside the machinery conversion scope. This compatibility transition is necessary to keep existing TRUE/FALSE callers working after `req` changes meaning, and is counted rather than hidden: the new `requirement_bool` fingerprint ratchet starts with 871 existing production rows. Only its new baseline was seeded; existing baselines were updated shrink-only. Analyzer callback roles, return checks, purity/read discovery and condition normalization recognize both protocols, including boolean window `remote` hooks and their separate reasons.

Current master had four adapters absent from the earlier branch, so the complete comparable inventory was **43**, not 39. All 43 native delegates are converted: 39 merged null-or-reason callbacks and four declarative requirements, across 27 machinery/power files. The historical comment-tagged subset fell from 24 to zero. Selection-only checks still fall through; refusal wording, silent effect-decline cases, operation keys and priorities are preserved.

`dq_actor_can_act` is not equivalent to `req_capable`: it requires a living actor and uses `INCAPACITATION_DEFAULT` (restraint/full buckling), whereas `req_capable` checks the action stat and accepts nonliving providers. Converted callbacks preserve the former checks instead of substituting a different policy. Nuclear `extended` is tracked and its runtime write uses its setter; prison-shuttle policy flags are tracked as well. Volatile map/material/custody reads use the existing `read_once` form. No new ALLOW annotation was added. Two now-unused material-read annotations were removed.

## Remaining legacy

Two old frame helpers, `accepts_board` and `has_all_components`, remain solely because `code/datums/capabilities/frame_ladder.dm` and existing old-helper tests still call them. Native frame requirements no longer delegate to them and have real board/component regressions. The construction-retirement lane can remove the shared helpers with its last callers. No compatibility alias or synthetic action wrapper was added, and `code/datums/interactions` was left untouched.

Other direct boolean callbacks outside the 43-delegate inventory remain explicit `req_bool` debt. They are covered by the new ratchet rather than claimed converted.

The plain-click window/loading defect is proposal-only in `machinery_plain_click_ranking_proposal_1008.md`, with supported, unsupported, refused, selection-fallthrough, empty-hand and harm cases. No ranking or priority change was made.

## Pins and verification

Old behavior was recorded green before source conversion: 29 types, 2,603 rows, focused result `data/test-runs/20261009T020113_ebfc16d7e9.json`; captures committed in `732159d6df`. These scoped captures are compared after conversion. No pin rows have been re-blessed.

The preceding branch's approved repair batch passed all eight tests, result `data/test-runs/20261009T015422_e4eb0ec495.json`, and its updated handoff was pushed in `893e715442`.

Final verification on clean source commit `c742a87ac6`: DM compile 0 errors and 50 existing warnings; DreamChecker 0 diagnostics; full lint and ratchets pass; focused result `data/test-runs/20261009T022526_c742a87ac6.json` reports 21 passed, 0 failed, 0 skipped, zero runtimes and a clean boot gate. The 29-type, 2,603-row pin comparison passed unchanged. Three new engine protocol groups and two new frame regressions passed, along with the existing computer, occupant-slot, sticky floor-light, frame round-trip, fabricator/stale and refusal/asks compatibility tests. The selection contained 22 names, but `round2_menu_refusal_restore/pandemic` is an abstract base and did not execute; its beaker/syringe behavior cases were not run. Pandemic admission remains covered by the scoped conversion pin.

Four targeted analyzer tests passed (three library tests and one semantic integration test), including distinct callback return protocols, purity/reads, remote hook classification and the new ratchet. Cargo stayed scoped to dq-analyze, one command at a time with two jobs and the shared target/cache.

The first final-run attempt stopped in generation before DM compilation because the message-instance fixture called an unannotated global; it now samples a preexisting message instance. Static checks also found remote-hook classification, volatile reads and test include placement issues; these were fixed together in the permitted repair pass. There was one actual final DM compile and one actual focused test world after the old-code pin capture.

No full suite, shards, workspace Rust suite or `dq_look_state_pin` was run. Logs and the explicit focus list are under `data/codex-machinery/requirements-protocol-1008/`.

## Batch-20 merge repair (2026-10-08)

The branch now contains both `origin/master` at `df1683f171` and `codex/machinery-prompts-reqs-1008` at `893e715442` by ancestry. Merge conflicts preserve master's draw work, the prompts branch's kiosk claims/passenger consent/cycler starts shock and approved reentrant cancellation guard, and the new requirement protocol. Only this combined branch needs integration.

Master's CableLayer adapter returned a boolean, which the new protocol reads as a refusal; the bomb-tester selection had the same protocol mismatch. Both now use direct null-or-reason callbacks preserving the original `cable || on` and `!tank1 || !tank2` predicates. Real-object regressions cover loaded/empty/running CableLayer states and tank-slot transitions. The prompt merge also converted kiosk patient/panel and cryopod passenger/adjacency/self-entry checks to null-or-reason. The full callback audit found 44 production constructor lines, including repeated/inherited callbacks, with no remaining boolean `req(PROC_REF(...))` callback. Boolean `remote` hooks are a separate deliberate protocol.

Correct rebuilt-analyzer checks reported no new `requirement_bool` sites from either master merge. The baseline shrank **871 -> 870**, never increased. No new ALLOW or ceiling change. The first cached analyzer did not contain the requirement lint; its pass was discarded, the branch analyzer rebuilt with two jobs in the shared target, and all checks repeated with the correct binary.

CableLayer and bomb-tester pin files are unchanged and `dq_requirement_protocol_pin` passes. The only requirement pin reconciliation is the cryopod's thirteen already-reviewed `Put grabbed victim in` menu rows, copied byte-for-byte from the prompts branch's existing `last_timed_1008` capture, with the cause recorded in `intended_changes.md`. No new capture/bless run was used.

Final verification on `9e5917c902`: compile **0 errors / 50 warnings**, lint and DreamChecker **0 diagnostics**, ratchets pass; focused result **43 passed / 0 failed / 0 skipped**, clean boot, in `data/test-runs/20261009T044323_9e5917c902.json`. This includes both scoped pins, protocol/composition/menu tests, the two new real-machine regressions, concrete pandemic cases, and kiosk/passenger/shock/self-entry tests from the merged prompts branch. No full suite, shards or `dq_look_state_pin` ran.

Before the final `df1683f171` instruction, the earlier merged-tree compile also passed but its focused world exited during boot without any test results. Its logs are preserved in `data/codex-machinery/requirements-protocol-1008/boot-exit-before-df168/`; no cause was established and that attempt is not counted as a pass. The final updated-master run above completed cleanly, so no failure-only rerun was necessary. Final logs: `df168-{ratchets,lint,focused}.log` in that same data folder.
