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

Targeted analyzer tests passed before the repair of named remote-hook classification. Final verification results will be recorded here after the combined repair pass. The first final-run attempt stopped in generation before DM compilation because the message-instance fixture called an unannotated global; it now samples a preexisting message instance. Static checks also found remote-hook classification, volatile reads and test include placement issues, which were repaired together.

No full suite, shards, workspace Rust suite or `dq_look_state_pin` was run. Logs and the explicit focus list are under `data/codex-machinery/requirements-protocol-1008/`.
