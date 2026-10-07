# Machinery follow-up, 7 October 2026

## Round 2 merge checkpoint

Master `eac3bc655d` is merged in `4e247bcd36`. The sole conflict was lifecycle setup: the engine-owned compatibility hook and master's plain-datum repeat arming are both retained. Timer deleted-argument handling, source-owned holds, read-once/slot APIs and ghost windows came from master unchanged. The focused runner now uses the pinned shell entry point on Windows.

Generation passes. DreamChecker reports zero diagnostics. Enabled engine layering remains zero. Ratchets still report ten unknown admission reads and one custody relation hop; none were exempted or baselined. The merged 66-test run compiles with zero errors, passes boot, and passes 64 tests. The two failures are the pin comparison (4,765 rows) and menu-order golden (282 scenarios); no state leaks were reported. These are not clean overall gates.

All six targeted declaration/field families and the 19 topic actions remain at zero in machinery/power. Old gas watches and their hub are absent; machine power and conditions already use stat contributions. The seven requested player prompt paths use asks. Sixty-five other direct requests remain in 29 files, chiefly separate UI/callback/consent paths; the obsolete gear admin helper accounts for one and will be removed on the final branch. The atmospheric retention field still needs its explicitly requested Use label.

The only accepted snapshot changes in this branch remain the 36 airlock/vending/APC scenarios adding master's documented default menu ops and 87 missing-card Emag row removals. Causes are the integrator classes in intended_changes.md; no further captures were blessed at this merge. The checkpoint is pushed as requested; unresolved gates and the gravity/stage follow-up are carried into codex/machinery-final-1007.

This batch retires the remaining targeted legacy declaration families in `code/game/machinery/` and `code/modules/power/`, preserving the current master operation, request and topic APIs. Eleven semantic findings and unapproved snapshot differences prevent a clean handoff; the branch is not ready to land.

Latest completed runtime verification before the final master merge: twelve focused tests passed, followed by eight focused tests with a clean boot gate and no state leaks. Fixture setup warms the persistent `dview_mob` cache before global snapshots. The eight-test run's restored missing-card Emag expectations have since been superseded by master's explicit integrator policy; the final 66-test run checks that policy. Snapshot review remains pending; no broad blessing has been performed.

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

Merge `07e9cfc4a7` incorporates master `2173eed369`, preserving master's machine-pipeline retirement, machine stats, gas APIs and timer deletion policy alongside the engine extraction. Read generation retains master's 300-row chunks and assembles them through exactly one real global initializer. Two focused generator Rust regressions pass.

The broad five-family declaration ban remains intact. A separate OM-field ban applies only to machinery and power, preventing the merge from accidentally banning unconverted fields in other folders. Both bans reject inline waivers. The focused scope/waiver regression passes.

Master explicitly authorizes removing legacy missing-card Emag menu rows. Actual held exhausted cards retain their refusal. Robot Blocked and cell item-menu corrections preserve the older disabled rows without swallowing ordinary physical clicks; final runtime verification is pending.

Master integration introduced 12 engine layering findings, all corrected through actual interfaces. The existing default `topic_allowed()` (TRUE) and `topic_forward()` (null) implementations moved from the old topic dispatcher into engine inputs. Three genuine transport hooks delegate downstream: prompt `focus_transport()` handles modal/TGUI update and focus; `op_topic_resolve_ref()` retains the existing scoped resolver; `op_topic_rights_denied()` retains every administration log and notification. Topic dispatch order, pending-request focus and multiple-modal intent are preserved. `batch5-engine-layering-fixed.log` confirms both external_dependency and semantic_model are zero. No exemptions or ALLOW annotations were added.

## Behavior and topic work

The 19 topic rows comprise 16 ordinary Orion actions and three VV actions (gear add-pack, jukebox add/remove track). Each type has one composition block. Orion retains its existing game handlers; its existing UI close/killcrew handlers share the topic inputs. Numeric topic args have matching handler formals and retain the shared handlers' payload behavior.

VV actions use current typed rights requirements and asks. Only voluntary cancellation of the final optional artist step can add an already-complete jukebox track; early cancellation, other interrupt reasons and failed fresh rights checks cannot. Direct compatibility gear/jukebox helpers remain for existing callers, while new topic effects use the native operation flow. Tests explicitly distinguish framework admin context from actual client transport.

Gear prompts retain busy state during selection and dispensing, release it on cancellation, and reacquire it after answered-prompt dismissal before animation. Doorbell label cancellation retains the original opening fingerprint. Repeat conversions retain real restart triggers after parking. Alien cell subtype self-use now precedes inherited charging/draining as the previous subtype declaration did, eliminating an operation clash. Camera status, breaker lock and privacy cooldown gates use actual tracked writes. Guest-pass eligibility uses its real tracked expired flag rather than a possibly stale sprite, with a regression asserting that rendering cannot reactivate an expired pass.

## Tests and current verification

Only focused tests are run, centrally and serially. No full suite was run for this batch.

The post-merge 66-test run compiled with zero errors (42 DreamMaker warnings), passed the boot gate, and passed 64 tests. `dq_conversion_pin` reported 4,852 differing rows; `dx_menu_order` reported 318 differing scenarios. All new behavior regressions passed, including menu policy, strict native/legacy emag notifications, actual ID insertion and the engine every() options. This was not an overall passing run.

The four-test cleanup rerun passed both fixture isolation tests and the firedoor behavior assertion. The pin sweep retained its 4,852 differences but no longer leaked `act_taken` or initialized the status-policy cache inside the test. Prompt restoration now surrounds door fixture setup. The subsequent two-test run confirms those prompt leaks are gone and reduces menu differences from 318 to 282; its isolated door query exposed a separate lazy `dview_mob` cache warning. Door fixture construction now warms that production cache before global snapshots. `door-isolation-focused.log` passes the final isolated firedoor test, with zero compile errors, a clean boot gate and no state-leak warnings.

Only 36 airlock/vending/APC menu scenarios were regenerated with the official golden renderer: click survivors and original menu ordering match, with only master's documented base-menu additions. Exactly 87 documented missing-card Emag rows were removed across seven pin files; every other pin row was retained. No whole-file blessing was performed. The remaining menu differences include 182 held-argument pickup scenarios whose fixture places the alleged held item on the turf, requiring setup/API tracing before approval.

`final-checkpoint-lint.log` reports zero DreamChecker diagnostics and passing Biome/TypeScript on the final source. `final-checkpoint-ratchets.log` confirms enabled engine layering at zero, corrected scoped bans and passing capability-map generation/selftest. Both commands fail solely on the ten unknown reads and one relation hop listed below. No lint allowance, baseline addition or ceiling increase was used. The machinery branch is kept locally pending these blockers; the previously completed engine branch remains pushed separately.

The following earlier run notes are historical; post-merge results above supersede their pending-verification statements and temporary missing-card Emag expectations.

### Post-merge baseline accounting

Exact committed baseline fingerprints compared with master `2173eed369`:

| Lint | Master | Branch | Removed | Added |
|---|---:|---:|---:|---:|
| base_vars | 981 | 912 | 69 | 0 |
| instance_list | 48 | 0 | 48 | 0 |
| silicon_entry | 111 | 102 | 9 | 0 |
| system_boundary | 301 | 300 | 1 | 0 |
| dx_raw_delay | 6 | 5 | 1 | 0 |
| dx_review | 178 | 171 | 7 | 0 |

Total: 135 fingerprints removed, none added. The base_vars, instance_list and six dx_review removals belong to the inherited engine extraction, rather than the machinery sweep. The latest official updater removed nine silicon entries and two stale timer/review entries. No fingerprints were hand-rekeyed.

The remaining semantic barrier is ten unknown reads and one relation hop. The unarmed-attack damage finding is a variable-name-only write-index false positive: unrelated `damage` writes and locals taint the configuration field. A proper analyzer fix needs typed write provenance with conservative handling of unknown receivers. The other findings require genuine shared mutation producers or ownership interfaces. Cell Charge/Drain menu parity also needs a truthful hand interface covering robot module selection; ordinary slot occupancy cannot substitute for that state.

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
