# Requirement retirement handoff (2026-10-15)

> 2026-10-17 refresh: merged current `origin/master` at `82f2b87547cf` on `5963d97922`.
> The production `REQ_*(` inventory is 141 lines on that master and zero after this merge; the boolean-requirement baseline remains zero.
> Master’s internal-storage admission guard, pilot constructor test and private-notes setter are preserved; acceptance preference setters remain in place.
> No change against master remains under `tools/dmb`, build tooling or `code/engine/change`.
> The earlier receipt below is historical. A new lane-ready proof is pending on this merged code; 80 explicit selectors include the changed acceptance/constraint/consent tests and both mandatory pins.

Branch: `codex/req-burndown`. Final lane-ready verification is pending; this document does not claim a stamp or a completed gate.

## Admission integration (October 17)

Merged master 077c0abc73 (rewrite/admission) in 55b1007765. Its native actor requirement parts and deletions of the old requirement/context/adapter types are retained verbatim; no retired type is resurrected. The remaining content conversion still removes all 141 production REQ_* call lines. The three historical admission branches listed below remain abandoned, with their useful content consolidated here rather than replayed over the new admission engine.

Verification now excludes all look-pin tests and uses --no-pins for both lane-ready and landing. Only the published compiler is used; it is never built or published by this lane. Final proof remains pending.

## Dropped during the October 17 refresh

Master's look producer, sweep and verified look-key record are retained verbatim. This drops the old telecube cleanup and related harness edits rather than reviving the rejected sampling/seed change. No appearance snapshot is re-blessed for this retirement; any future harness proposal is separate. The earlier receipt below describes historical code.

## Superseded branch disposition (October 17)

- `codex/requirements-hard-ban-1010` at `745ab207ba` is abandoned: only its historical handoff commit remains outside master.
- `codex/acceptance-final-1011` at `d70998e600` is abandoned: the 149-table cohort and consumer migration are consolidated in this requirement retirement.
- `codex/acceptance-retirement-1011` at `15b5df8158` is abandoned: its final acceptance cohort is consolidated here; current master's constructor fixes are retained.

Keep those refs as historical evidence; do not merge their obsolete tooling, producer changes or duplicate admission conversions separately.
## Result and counts

| Inventory | Before | After |
|---|---:|---:|
| Remaining acceptance declarations | 173 | 0 legacy tables |
| Mechanical / semantic declarations | 149 / 24 | 0 / 0 legacy tables |
| Retired requirement/holder/predicate macro definitions | 81 | 0 |
| Retired exact names covered by the hard ban | 0 | 81 |
| Live `req_bool(...)` | 0 | 0 |

The predicate and system-requirement compilers, table adapters, includes and unused stance helpers are removed. Native acceptance handles wearer/mover/slot context, ordered refusal reasons, overrides, subtype dispatch, actual equipment and consent consumers. Remaining boolean effect-facing consent helpers inspect native refusal results; they are not a second requirement protocol. Numeric unit formatting and the three real formatting helpers retain their actual consumer roles. Request-result enums such as `REQ_ANSWERED` and `REQ_CANCELLED` remain legitimate; the ban matches the exact 81 retired names rather than an unrelated prefix. No baseline or ceiling was raised.

## Behavior proof and documented changes

Old-code evidence is committed in `d99315344b`: 29 fit snapshots (232 rows), 160 acceptance-type snapshots covering all 173 declarations, and a real item-override snapshot. The shared old-code repair run passed both acceptance/override selectors (`20261015T220049_fcc8559302.json`). This is baseline evidence, separate from final-code verification.

`intended_changes.md` records the only acceptance corrections: malformed syndicate-gripper union data from `0dfa07f646`, numeric refusal text incorrectly reduced to literal `size`, and impure saddlebag/Avida admission previews. Preview requirements are pure; real equipment still applies sprite changes through synchronous equipment notices and setters. Only the documented malformed-union and numeric-refusal pin rows are refreshed.

Master metadata causes are recorded separately: `f13b84652d` deleted the dead Mecha/Ripley `ai_use_equipment` key; `2136172edc` introduced the living `devour` key. Those key inventory updates preserve expanded menus and clicks. No runtime row is a permissible re-record cause.

Shared constructor repairs restore behavior exposed by master's typed-reference declarations in `5b0a2f09d0`: internal storage rejects a non-item owner before linking it and completes the valid owner link/name before construction returns; cloning's absent scanner is null rather than zero. Real regressions cover rejected/accepted construction, the gripper subtype, independent owner lifetime and scanner disappearance. Pilot-slug destination selection now excludes deleted/no-turf helms while retaining one entry per valid helm, including multiplicity on a shared turf. These are source fixes, not runtime golden blessings.

## Verification and remaining limitation

Coordinated earlier native gates passed generation, production compilation, DreamChecker, ratchets and analyzer regressions. The later native run after master `3097a36445` passed those static gates and 50 focused tests; its two failures were a timer-fixture deadline assumption and compiler-dependent look-state sampling. The timer fixture was corrected to advance a real deadline slot and assert keyed delivery.

The look-state producer caps the first 24 vars before filtering its unchanged 3,202-type analyzer plan. Native and DreamMaker enumeration orders select different probes: the native diagnostic contained 229 removed and 112 added rows in nine root files. Those goldens remain unchanged. This is a retained compiler/test-producer limitation, not proof of changed appearance or a claimed fix. The final repair gate explicitly uses the supported DreamMaker cross-check backend; any resulting receipt must be described with that backend.

The active final repair gate is pending at source `a80ffc…`; root will replace this paragraph with its exact receipt, backend, commit, test counts and failed selectors after it ends. Its explicit selectors are in ignored `data/codex-req-burndown/final-repair-selectors.txt`; mandatory `dq_requirement_protocol_pin` and `dq_conversion_pin` are included. No full suite was run. Existing fixture state-leak warnings are not silently dismissed or claimed fixed by this acceptance work.

## Completed lane-ready receipt

Lane-ready passed on gated source a80ffc964ae5 and recorded look keys at b0951efab3: 52 passed, 0 failed; result JSON data/test-runs/20261016T025845_a80ffc964a.json. Production compilation had 0 errors, DreamChecker 0 diagnostics, ratchets and analyzer tests passed. Both mandatory pins, both appearance pins, the actual keyed pilotslug timer regression and menu-order checks passed. DreamMaker was explicitly selected; native look-sampler iteration remains a separate unresolved diagnostic with unchanged appearance goldens. Existing fixture STATE LEAK warnings remain visible. This handoff-only follow-up relies on the documented docs-only stamp carry rule, checked before pushing.

October 17 verification selection: use normal-tier representatives for constraint declaration/equipment/storage/suit-storage catalogues, containment fuzz and rule thresholds. The earlier catalogue run was interrupted and supplies no stamp. The actual requirement and conversion pins remain selected; all look tests are excluded. Final proof must be a complete lane-ready run.
