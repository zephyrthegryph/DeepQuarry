# Machinery follow-up, 7 October 2026

This batch retires the remaining targeted legacy declaration families in `code/game/machinery/` and `code/modules/power/`, preserving the current master operation, request and topic APIs. Verification is still in progress; this draft is not a claim that the branch is ready to land.

Latest runtime verification: `real-initializer-focused.log` passed all twelve focused tests with a clean boot gate. The strict emag regression verified the populated generated read table and all six native/legacy notifications. ID insertion, repeat restart, menu ordering, change hooks, power-hit declarations and ready-light colour also passed. A lazy `dview_mob` initialization produced a state-leak warning in the magnet fixture; fixture setup now warms the persistent cache before global snapshots and needs a focused rerun. Snapshot review remains pending: the documented multi-item menu filtering does not authorize every removed single-item disabled row. No whole-file pin approvals or broad blessing are accepted on that basis.

## Scope and counts

| Declaration family, including handwritten equivalents | Before | Current active sites |
|---|---:|---:|
| Interactions | 42 | 0 |
| Emag reactions | 7 | 0 |
| Damage reactions | 9 | 0 |
| Repeating declarations | 4 | 0 |
| OM field family | 40 | 0 |
| Topic actions | 19 | 0 |

The raw macro-only prewave inventory at `568191936c^` is 32 interaction macros, 7 emag macros, 6 DAMAGE_REACTION invocations, 4 repeat macros, 32 OM_FIELD-prefixed invocations and 19 topic rows. The full-family totals also count handwritten interaction/reaction declarations and OM_DERIVE_FIELD/OM_FLAG_FIELD forms. Current source searches find no active target forms in either folder; a cell subtype comment still describes the previous declaration ordering.

No files under the protected `code/modules/combat_ai/` or `code/library/mob/` paths differ from origin/master. Framework classification fixes and shared vehicle/field compatibility are included outside the two target folders where needed.

## Master integration and interfaces

Merge `e7784f5458` incorporates master batch 5, including current topic dispatch and pending-operation behavior. The earlier engine self-contained branch was already pushed independently; this machinery branch builds on that integration rather than repeating it.

Master integration introduced 12 engine layering findings, all corrected through actual interfaces. The existing default `topic_allowed()` (TRUE) and `topic_forward()` (null) implementations moved from the old topic dispatcher into engine inputs. Three genuine transport hooks delegate downstream: prompt `focus_transport()` handles modal/TGUI update and focus; `op_topic_resolve_ref()` retains the existing scoped resolver; `op_topic_rights_denied()` retains every administration log and notification. Topic dispatch order, pending-request focus and multiple-modal intent are preserved. `batch5-engine-layering-fixed.log` confirms both external_dependency and semantic_model are zero. No exemptions or ALLOW annotations were added.

## Behavior and topic work

The 19 topic rows comprise 16 ordinary Orion actions and three VV actions (gear add-pack, jukebox add/remove track). Each type has one composition block. Orion retains its existing game handlers; its existing UI close/killcrew handlers share the topic inputs. Numeric topic args have matching handler formals and retain the shared handlers' payload behavior.

VV actions use current typed rights requirements and asks. Only voluntary cancellation of the final optional artist step can add an already-complete jukebox track; early cancellation, other interrupt reasons and failed fresh rights checks cannot. Direct compatibility gear/jukebox helpers remain for existing callers, while new topic effects use the native operation flow. Tests explicitly distinguish framework admin context from actual client transport.

Gear prompts retain busy state during selection and dispensing, release it on cancellation, and reacquire it after answered-prompt dismissal before animation. Doorbell label cancellation retains the original opening fingerprint. Repeat conversions retain real restart triggers after parking. Alien cell subtype self-use now precedes inherited charging/draining as the previous subtype declaration did, eliminating an operation clash. Camera status, breaker lock and privacy cooldown gates use actual tracked writes. Guest-pass eligibility uses its real tracked expired flag rather than a possibly stale sprite, with a regression asserting that rendering cannot reactivate an expired pass.

## Tests and current verification

Only focused tests are run, centrally and serially. No full suite was run for this batch.

The 54-test focused run (`final-fix-focused.log`) compiled with zero DM errors, passed the boot gate and passed 49 assertions-based tests. The subsequent 19-test run (`remaining-fix-focused.log`) passed 17 tests, including all four power refusals, three public washer regressions, console access gates, repeat restart behavior and scratch-global restoration. Its two remaining failures were a gear-dispenser inheritance clash in the pin sweep and doorbell click selection; the later run verifies those corrections. Neither run was a clean passing run.

The later `public-routing-notification-focused.log` run passed 15 of 19 tests with zero compile errors and a clean boot gate. It verified the doorbell fix, book insertion, alarm activation, breaker prompting, DX menu ordering, operation resolution and existing change-hook behavior. Its failures exposed a later Virgo beacon subtype clash, two ID routes intercepted by the generic computer item fallback, and a missing projected native dependency; the aborted pin also left gravity changed. The corresponding fixes preserve subtype/tool intent, use the existing held-item specificity rules, guard hop-free read rows and dispose pin-owned allocations before restoring gravity. Their focused rerun is in progress.

The subsequent `hopless-routing-focused.log` run passed 9 of 11 tests. Both ID routes, repeat behavior, menu ordering and existing change hooks passed. The pin sweep completed without declaration clashes or state leaks and reported 5,790 differing snapshot rows. Review identified incidental obstruction captures from earlier targets plus unrelated master conversions; no broad snapshot blessing was performed. The remaining notification failure exposed the generated-table initializer collision introduced by this branch's large-table workaround. The generator now declares raw list storage and one real initializer, with explicit runtime assertions that the table is populated before checking subscriptions and all six notifications.

`real-initializer-lint.log` records zero DreamChecker diagnostics and passing Biome/TypeScript checks, zero handler signature findings and enabled engine layering at zero. Its only failing lint is the eleven semantic read/ownership findings described below. The corrected initializer passed all twelve focused runtime tests. The official `current-ratchets.log` confirms the same eleven failures and passing capability-map generation/selftest; it is not an overall passing ratchet run.

The subsequent `menu-isolation-focused.log` run passed all eight explicit tests with zero compile errors, a clean boot gate and no state-leak warnings. It verifies six preserved single-item disabled rows, seven missing/exhausted-card Emag rows, per-target snapshot disposal (including the orphan inactive AI core), gravity restoration, magnet cache setup and existing doorbell/breaker/firealarm public clicks. Firealarm's enabled empty-hand Trigger menu is retained. Actual-card charge checks are unchanged. Cell hand-related menu refusals and the robot Blocked menu remain under review; no pin files have been blessed.

New or updated focused coverage includes:

- `dq_hc_computers/orion_topic_dispatch_and_schema`: real headless native transport refusal plus an explicit transport fixture that retains consciousness/incapacity/distance checks, real event mutation and numeric schema rejection.
- `dq_hc_struct/jukebox_topic_artist_cancel_and_early_cancel`: real track creation and early/final cancellation behavior.
- `om/interim_gear_pack_actor_refusal`: public unauthorized VV dispatch cannot reach the privileged effect.
- `dq_hc_computers/guest_pass_deactivation` and `guest_pass_expired_state_gates_deactivation`: actual self input, answer effects and stale-rendering expiry safety.
- `dq_hc_struct/doorbell_cancel_keeps_fingerprint`, `gear_prompt_cancel_releases_busy`, and `gear_answer_stays_busy_through_animation`.
- Computer emag/EMP, power-hit, camera-bug and repeat parking/restart behavior tests added earlier in the batch.
- Rust operation-condition and scheduled-callback classifier regressions preserve the actual context contracts rather than changing gameplay conditions to satisfy analysis.

Generation passes, and DreamChecker reported zero diagnostics after resolving the scoped-field compile seams. Final focused runtime checks and ratchets remain pending after the latest dependency and input-priority fixes. Official baseline updates reduced analyzer-reported `silicon_entry` sites from 139 to 130 (unique baseline fingerprints: 121 to 112) and `system_boundary` from 301 to 300, with no added fingerprints. The remaining real producer/ownership barrier must be resolved before handoff: native/context dependencies and removal-policy reads must use genuine current producers or interfaces, without fabricated read annotations, baseline additions or exemptions.

The complete semantic check identifies ten unknown reads and one containment hop: camera shredding depends on combat mode, anatomy and unarmed damage; camera bashing depends on weapon injury kind; AI-upload eligibility depends on native z; Santa eligibility depends on native ckey; robot camera-view blocking depends on native client state; floor-light removal depends on its direct parent's removal policy; both suit-cycler insertion guards depend on clothing icon overrides. These need real producers, including ownership coordination for protected/shared hooks. They have not been suppressed.

Shared field storage is now scoped to actual machine families, with existing defaults and custom setters preserved. The eight state owners retain their saved values; the floor-weld capability uses a concrete rung interface. Ordinary emag state uses actual capability storage, while the deployable barrier retains numeric stages. The ready-light setter retains its colour update. Compatibility channel metadata remains only for existing appearance/read consumers. Ten additional direct writes use existing setters, and forty unused vent-map attributes were removed without changing current power defaults.

The tracked lint now distinguishes exact AST named arguments and associative list keys from actual field assignments, including real assignments on the same line or inside parentheses. Six focused Rust regressions and the ten-fixture tracked selftest passed on that implementation. Two now-unused handler annotations were removed, and fabricator insertion/rejection/window priority uses explicit tiers without increasing the relative-priority ceiling.

Additional review corrected held-item shadowing in nine machine families and the security/skills consoles while preserving tool priority and existing effects. New public-click tests assert exact ID/book custody, alarm activation and breaker prompting. Literal refusal text now uses typed message declarations instead of being interpreted as a proc name. The emag notification fix follows actual native capability-key and legacy capability-state producers, with strict tests for both direct write paths; it does not substitute a virtual read annotation for those producers. Verification of these latest changes is in progress.

The pure `is_emagged()` accessor moved into the existing `code/library/access/emag.dm` file. Its name and behavior remain unchanged. The analyzer's original engine/legacy opaque traversal boundaries are retained; only explicit global accessor metadata contributes the real argument-root dependency. Generator tests check the actual declared numeric capability-key spelling, and context tests keep value getters pure while notice callbacks retain their reaction role.

Two pre-existing accessor contracts remain incomplete: `capability_data()` and `capability_extras()` have empty `READS_FROM()` metadata and no matching `OP_KEY_CAP_DATA`/`OP_KEY_CAP_EXTRAS` change publisher. They were left untouched; merely naming an argument would not establish a notification producer. The purity wrappers also do not unwind their depth on every crashing requirement path; the typed-refusal correction removes this batch's triggering crash, but the general exception-unwind gap needs a framework follow-up.
