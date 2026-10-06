# Codex OM retirement handoff

Date: 2026-10-06. Worktree: `E:/projects/dq-wt/codex-om-retirement-1006`.
Branch: `codex/om-retirement-1006`; starting integration commit: `9a28a84008`.
Current status: the eligible work in all four assignments is complete, including the timer follow-up below. Reserved APIs/domains and non-handler fixes remain documented for their owners. Only this private branch is published. Counts distinguish actual conversions from pre-existing zeroes; the initial timer section records historical evidence, superseded by the follow-up section.

## Task 1: runtime verb grants and revocation

Committed as `cb29b95966` (Migrate runtime verb grants and source revocation).
The committed diff removes **54 production mutating-helper call lines in 23 production files**. Each removed line has one matching mutation call. The earlier 52-site audit was an undercount; it is superseded by this direct committed-diff count.

Selected callers now grant/revoke native `granted_verb()` entries with their original target and source. Bulk providers were inspected as actual lists/null or literal lists, rather than assuming arbitrary helper values were lists. Malfunctioning AI source cleanup walks an activation snapshot and preserves research/hardware source distinctions. Timed ticket hides retain the client verb holder and original lifetime.

The following broader lexical counts include lookup helpers and ordinary generic state/ability adapters. They are **token occurrences**, not a count of remaining runtime-verb migration tasks:

| Application helper | Base | Committed HEAD |
|---|---:|---:|
| `om_grant` | 20 | 3 |
| `om_grant_each` | 15 | 0 |
| `om_grant_for` | 4 | 1 |
| `om_revoke` | 5 | 3 |
| `om_revoke_each` | 14 | 0 |
| `om_revoke_all_of` | 3 | 0 |
| `om_grant_sources` | 3 | 3 |
| `om_grant_target` | 3 | 6 |
| Total | 67 | 16 |

The extra `om_grant_target` occurrences are explicit existing client-holder lookup at native call sites; they are not additional verb mutations. Remaining mutations/read helpers serve traits (`code/_helpers/traits.dm`), abilities (`code/datums/abilities/ability.dm`) and the generic state adapter (`code/datums/reactions/state.dm`). Engine/OM implementation and tests are separate from this application table and were not counted as migrated content.

Counting method: batched `git grep` at the base and committed HEAD for the eight exact helper names followed by `(`, excluding comment-only lines, proc declarations, tests, generated files and the identified framework folders. This is a reproducible lexical count, not an exhaustive DM AST proof. The 54/23 conversion count comes directly from the committed diff, not subtraction of mixed inventories.

Known native limitation: verb definition identity is path-based; hidden/name are parameters. Arbitrary same-source/path mixed named/show/hide grants do not have a universal equivalence proof. The selected actual callers were checked for that collision; this does not authorize unrelated future conversions.

Added real regression types include `retire_alien_evolve_without_adult_hides_verb`, `retire_robot_default_and_subsystem_verbs`, `retire_malf_source_verbs` and `retire_timed_hidden_verb`. Existing grant-source/list/hide/declaration/named/turf fixtures remain relevant. Final verification results are recorded below rather than inferred from source review.

## Task 2: I/O inventory, test migration and DX delivery bug

Committed as `afcb95b5d3` (Refresh native I/O tests and repair DX weak delivery).

**`om_io` and `io_request` were already zero at the starting integration commit and remain zero.** The 82/24 figure in `doc/rewrite/om_retirement.md` section 7 is stale for this branch. No production I/O migration credit is claimed for renaming APIs that were already absent.

Actual transport is `io_job()` and native `/datum/io/*` requests. The reviewed providers have distinct contracts:

| Provider | Payload | Result/error handling |
|---|---|---|
| SQL | Query plus associative parameters | Rows/affected/insert ID; native request translates declared rows, no-result and transport failure |
| HTTP | Method, URL, body, headers | Response/status/headers or transport error |
| rust-g job | Already-started job ID | Raw completion text or error |
| Pathing | Separate system queue | Separate native request/provider contract |

Job cancellation clears callback delivery; it does not cancel backend execution. Deleted owners/context arguments drop completion; queue concurrency and real-time timeout policy remain unchanged. Internal handle capture, guarded-call transport, prompt/flow adapters and backend implementation were deliberately left alone.

The test changes replace the old flow replay fixture with actual native two-stage I/O continuations, use the real fake-backend transport lane, and drive time through the kernel test driver. They preserve observable result/error/dropped-owner assertions. Native first-stage effects run once; these tests do not pretend to preserve the legacy three-prefix-replay implementation.

A real DX bug was exposed: `dx_exec_wrap()` produced a dictionary keyed `om_h`, while `rerun_unwrap()` recognized `rerun_h`. Live datum callbacks therefore failed delivery. The committed fix changes only that key to `rerun_h`; deleted-owner drop and live context resolution remain tested. This does not redesign the capture framework.

Seven transport-focused fixtures passed after the fix:

- `io_transport/io_job_delivers_and_parks`
- `io_transport/io_job_owned_and_weak`
- `io_transport/io_job_queue_limit`
- `io_transport/two_reads_continue_once`
- `io_transport/read_error_is_transport_failure`
- `io_transport/read_dropped_when_owner_gone`
- `io_transport/dx_exec_delivers_weakly`

The harness restores lane/backend/DX globals and registers the prior `dview_mob` through `set_global()`. A lazily created dview keeper is not qdel'd: it refuses normal deletion and force deletion recreates it. Existing native picker/crayon tests in the same file were not presented as newly migrated I/O coverage.

## Task 3: obsolete declarations

Production `DECLARE_VERB` executable sites and executable `EVENT_HANDLER` declarations were already zero at the base. No production conversion credit is claimed for their absence.

Commit `0bd9f5be52` removes obsolete verb declaration macros, replace the remaining declaration fixtures with real native verb entries and add hard-ban lint spellings. Comment corrections describe current typed actions. `VERB_DECL_*`/legacy verb-store internals remain where still consumed; this is not permission to delete the whole underlying store.

The native declaration fixtures passed with the macros removed; the focused batch also passed the existing condition and turf fixtures.

## Task 4 / C4: initial slice (historical snapshot)

The source inventory distinguishes call sites from distinct handlers:

- Global lexical inventory: **940 masked `after(... with=...)` call sites**.
- Signature resolution: **906 resolved, 34 unresolved** dynamic/type-resolution cases.
- Distinct resolved typed handlers: **502**.
- Ordinary module subset audited here: **239 call sites classified**, zero unclassified rows in its CSV.

Classification is not a blanket runtime-safety claim. Scalar-only rows prove only that they have no independently nullable entity payload. Owner-aligned arguments rely on the actual owner-drop contract. Delegated virtual calls, recursive list-contained entities and internal relation lifetimes have separate limitations.

The consolidated `c4-final-502-coverage.csv` has:

| Evidence category | Handler rows | Meaning |
|---|---:|---|
| `EXPLICIT_BODY_DISPOSITION` | 302 | Explicit actual-body decision, including safe, bug, excluded and held outcomes |
| `PEER_BODY_READ_CONSERVATIVE_HOLD` | 100 | Body read, but conservative unresolved closure/scope hold |
| `PEER_CALLSITE_CLASSIFIED_NOT_FULL_TRANSITIVE_PROOF` | 100 | Call-site classification, not completed transitive behavioral proof |

This table records the initial slice. The durable [per-handler audit](om_retirement_timer_audit.csv) now contains the follow-up dispositions below, retaining original base line anchors and `BaseStatus`. Neither inventory size nor a source disposition proves arbitrary runtime subtype behavior. The 502 total and 239 ordinary-module subset overlap and must not be added together.

The final C4 changes cover **52 handler bodies in 41 production files**. Eight unnecessary projectile guards were restored after independent review, preserving the existing null-safe delegate and its diagnostic. The fancy dispenser greeting guard is included.

Changes preserve owner cleanup before skipping missing participants: AI busy release, LEAPING/pass state restoration, phase movement/body-effect restoration, extraction-holder completion, ammo cleanup and beam disposal. Missing dark-maw victims use the existing dissipate notice and owner disposal. Missing injector targets use the existing failure-pin branch without reagent transfer. Other guards cover deleted scanner targets, preview client loss, telecube targets, reactive stealth/illusions, pulse observers, alerts, independent backup clients, vine targets, door/syringe callbacks and anomaly cough participants. No debug tracing is intentionally removed.

Protected remaining work includes ownership helpers/declarations, task/busy APIs, prompt/flow/ask implementations, machine process/power/pipeline handlers, item/structure periodic work, actual `update_icon`/draw providers and the reserved engine stores/framework files. Sharing a file with one of these areas does not automatically exclude a separately permitted callback, but no broad framework conversion was attempted.

### Wrong-order timer callers requiring owner coordination

The actual current signature is `after(owner, delay, handler, ...)` in `code/datums/capabilities/timed.dm`. These unchanged protected caller sites use the old argument order:

| Source | Current call concern |
|---|---|
| `code/modules/client/client procs.dm:455` | Login timeout supplies delay, global handler, ckey; intended receiver/argument custody must be established |
| `code/modules/client/client procs.dm:733` | Asset preloader supplies delay, typed handler, transport |
| `code/controllers/subsystems/tgui.dm:377` | Prewarm staggering supplies delay, local handler, system receiver |
| `code/modules/asset_cache/transports/asset_transport.dm:148` | Asset JSON update supplies delay, typed client handler, client |
| `code/modules/client/verbs/ooc.dm:281` | Viewport fit supplies delay, verb reference, client |

The first three are the previously recorded audit findings; the last two were additionally confirmed during this handoff review. They were not edited. Safe guards in their eventual handlers do not repair a malformed scheduling call itself.

### Independent review findings before final commit

1. **Eight unnecessary projectile guards were restored.** A missing target reaches the existing `preparePixelProjectile()` stack trace/consume path; generic targeting uses null-safe `get_turf()`/`Get_Angle()`, and the caller cleanup follows or precedes launch. New guards in frog/candy `chargeend`, ddraig `tfbeam_1`, four imperion stages and candy `barrage_shot` suppress that existing diagnostic. Their original behavior was restored before final verification. This is source-level delegation proof, not a newly run deleted-target projectile test. Arc point construction accepts null without atom dereference; wider projectile behavior is not redesigned.
2. **Fancy dispenser greeting now guards its missing setting.** `suit_fancy/dispense_finish()` already clears `GD_BUSY` and resets emagged before its greeting, but the greeting reads `S.name` without checking independent `S`. The guard adds `S` to the existing greeting condition, preserving preceding cleanup. Actual animation providers and vending/stock logic stay unchanged. The live/deleted-setting regression pair uses the real constructor catalog, input click and public dispensing method.
3. **The other current guard diffs were read without finding another concrete introduced error.** No-target cleanup ordering, valid-target branches and existing log text are retained. This is not a claim of exhaustive virtual behavior or connected-client coverage.

### Regression and scope limits

The serial focused batch passed all **24 selected tests**, including nine new timer regressions. A second focused run selects only the two new fancy-dispenser cases. Both passed. The final focused run covers eight further deleted-argument cases for paper, bundles, the dust anomaly, grinder, batterer and autopsy report. The batterer isolation seam reseeds immediately before calling the actual handler, ensuring its old damaging branch is exercised rather than allowing a probabilistic pass. No full-suite/shard/e0 run is requested or claimed.

The scout's injector regression is an uncompiled draft using an actual assembly, crowbar opening, real cell insertion, circuit insertion, default powered activation, target deletion and kernel fault/state assertions. It is not part of verified test results until integrated and run. The plant public-proximity draft is not finished: natural seed/mouse selection is deterministic, but natural spreading/soil cleanup requires a genuine fixture proof. Connected-client disappearance and presentation paths remain untested where no actual client seam exists; no fake clients or fabricated permissions are offered as substitutes.

Recursive list entities, dynamic continuation callbacks, null movement/throw built-ins, underlying ownership helpers and arbitrary subclass delegates remain explicit gaps. A syntactically nullable argument is not by itself evidence that the current delegate crashes.

## Final verification (root updates before integration)

- Committed task-2 transport focused tests: seven passed.
- Task-3/C4 focused batch: **24 passed, 0 failed**, result `data/test-runs/20261006T194219_afcb95b5d3.json`; no boot gate or state leak lines. Includes nine new timer tests.
- Additional fancy-dispenser focused pair: **2 passed, 0 failed**, result `data/test-runs/20261006T195151_a166ea4279.json`.
- Additional eight isolated callback regressions: **8 passed, 0 failed**, result `data/test-runs/20261006T195948_a166ea4279.json`. In total, 34 selected tests passed across serial final focused runs. No full suite, shards or e0 tier was run.
- Final focused compile: **0 errors, 28 pre-existing unused-variable warnings**; DreamChecker: **0 diagnostics**. No new warning site occurred in the added tests or changed handlers. No boot-gate or state-leak lines occurred in the final focused runs.
- Native generation and full `analyze check`: **passed**. Fingerprint set inclusion and decreasing numeric ceilings were verified separately; no new ALLOW annotations were added. The final `check_ratchets.sh` wrapper passed, including generator checks and self-test.
- Final C4 count: **52 handlers, 41 production files**.
- Publication target: only `codex/om-retirement-1006`, never master.

The tracked `doc/om_retirement_timer_audit.csv` records the 502 original handler entries and individual remaining reasons. Additional source inventories and unused drafts under ignored `data/codex-retire/` are supporting evidence only. The lexical inventory is not exhaustive: the separately reviewed fancy override illustrates why virtual overrides need independent review.

At the initial handoff, additional cleanup-sensitive sites remained held: recycling crusher completion must retain its power/working reset; NIF vending must retain ownership and readiness cleanup; firearm reload/burst require inventory/draw closure; artifact revival must preserve revival independently of its holder; resleeving needs an absent-record policy; toy brawls need reciprocal controller cleanup. No head-return conversion was applied to these. The CSV retains the exact source anchors and evidence limitations.

## Baseline update results

The analyzer refreshed stale tolerances inherited from the salvaged integration base. These reductions are not credited as new content conversions by this branch; the documentation legacy-block reduction follows this branch's macro retirement.

| Lint / tolerance | Before | After |
|---|---:|---:|
| API fingerprint rows | 2 | 0 |
| Base-variable fingerprint rows | 989 | 985 |
| Initialize fingerprint rows | 1287 | 1272 |
| Instance-list fingerprint rows | 52 | 48 |
| Documentation baseline rows | 69 | 68 |
| Escape-hatch init-allow ceiling | 347 | 318 |
| Legacy-interaction ceiling | 51 | 16 |

Counts are non-comment baseline rows, including existing duplicates; numeric ceilings are shown separately. Two other baseline files were reordered by the analyzer without changing their fingerprint sets. `decl_baseline` and `op_order` remain untouched.


## Task 4 follow-up: remaining eligible callbacks completed

The follow-up changes **47 callback/completion bodies in 36 production files**, bringing the branch total to **99 bodies** (initial 52 plus 47). These are small handler guards and completion cleanup corrections, not wholesale framework/domain conversions. No timer store, machine process, ownership helper, generated source or drawing implementation was edited.

The **502-entry source inventory now has specific dispositions for every entry**: 230 initial explicit body decisions, 253 subsequent body/delegate decisions and 19 previously landed fixes whose source disposition was completed. The earlier 200 conservative/callsite-only holds are gone. **93 inventory entries are fixed on this branch**; the 99-body count additionally includes override/completion bodies missing from the original lexical inventory. Source dispositions distinguish existing guards, owner-bound arguments, actual delegate behavior and precise exclusions. They do not claim every arbitrary virtual subclass, outside caller or connected-client path was tested.

Additional fixes cover:

- Gun burst and storage loading: a vanished actor cannot consume pending ammunition; real headless users have optional HUD updates.
- Toy battles and transit: missing opponents/pods release surviving combat/movement state, without fabricated wins or losses.
- Book binding, injector completion and hyperpad callbacks: missing payloads do not create empty books or strand synthesis state.
- Artifact revival and backed-up NIF restoration: optional message holders do not block the actual revival call; absent records preserve the current NIF.
- Vacuum, toilet, antagonist spawn and transport completions: missing participants skip target work while existing consumption, flush or unload tails continue.
- Capsule, spell and mecha shots: cancellation preserves common reset/image disposal/projectile disposal behavior.
- Jaunt and tunnel callbacks: missing saved destinations or participants restore surviving movement/busy state and dispose surviving temporary holders/overlays. Missing vents use the surviving origin/current turf rather than dereferencing a deleted vent.
- Cult revival, cliff landings, shuttle crash victim lists, deployment callbacks and recycler shots: absent independent actors/items are guarded before their effects.
- Giga drilling: the genuine regression showed that `ChangeTurf()` can leave a captured mineral reference pointing to a floor. The guard therefore checks the actual mineral type, not merely non-null, and preserves relation/anchor cleanup.

### Focused verification for the follow-up

**35 new regression types** were added, and two existing shuttle tests were selected. All **37 distinct selected tests now have passing focused runs**. The final repair run passed ten tests, with a clean boot and no state/object leak lines. It reran only the affected tests plus the four last additions. The earlier eight-test run passed but exposed fixture global-counter restoration gaps; those fixtures were repaired and subsequently passed. The larger run exposed the replaced-mineral bug and transit/steam fixture problems; the final targeted run verified their corrections.

The fixtures distinguish genuine public entry (toy battle, mineral toggle/Bump) from isolated actual timer/completion boundaries. The transit launch fixture exercises the real launch-close stage, not launch-availability rules. Jaunt fixtures exercise real resurface/reform and temporary-object cleanup without claiming connected-client rendering. The capsule fixture reaches an actor-dependent outcome through actual bounded randomization and asserts that precondition, rather than passing on an unmatched branch. No full suite, shard or E0 run was started.

Final DM compile: **0 errors, 28 pre-existing unused-variable warnings**. Native generation and baseline update were rerun. The baseline updater made no additional tracked baseline changes in this guard-only follow-up; the earlier shrink totals above remain the branch totals. No ALLOW was added. Final DreamChecker: **0 diagnostics**. Full analyze check and ratchets both passed. The final typed-pilot correction was recompiled and verified separately: **1 focused test passed, 0 failed**, with no boot/state/object leak failures (`20261006T205317_c1773d841c.json`). An independent production-diff review found no introduced cleanup or logging regressions.

### Remaining sites intentionally left to their owners

The CSV contains every excluded entry and its reason. Concrete outstanding bugs/policies include:

| Area | Required change | Why not edited here |
|---|---|---|
| In-belly spawn prompts | Guard the missing observer before building request text | Prompt/flow track reserved |
| Recycling crusher/sorter and NIF vending | Guard missing item/record/person while retaining power/readiness/ownership completion | Machine pipeline, power and ownership tracks reserved |
| Empty drink completion | Handle absent feeder while preserving trash placement and consumption | Requires changing shared consumption/ownership policy |
| Spider vent traversal | Abort missing vents with relocation and entry relation cleanup | Requires a new ownership cleanup site |
| Emagged arcade resolution | Make the actual arcade action's missing-user gib nullable | Unsafe read is in a non-timer delegate; handlers-only scope cannot preserve game resolution by returning early |
| Dummy holograms, filter cleanup and transformation callbacks | Guard lost appearance participants | Actual drawing/appearance implementation reserved |
| Admin electricity, scanner lockdown and other power callbacks | Guard lost area/target with appropriate power cleanup | Power track reserved |
| Singularity pull / broken supermatter debris | Skip an obsolete pull or absent-location allocation | Power callbacks reserved; these are builtin/debris policy issues, not demonstrated null-member runtimes |
| Passenger departure when both captured/current occupant are null | Decide intended empty-hatch cancellation behavior | Machine pipeline policy, not a direct null dereference |
| Five old-order timer callers listed above | Correct owner/delay/handler argument order | Assignment permits handler changes, not these scheduling callers |

Existing projectile missing-target diagnostics and their disposal paths remain intact. Dynamic rocket continuation was traced through all seven current producers: only the phase-5 imperion supplies a continuation, whose current projectile path handles missing targets through the existing diagnostics. No universal claim is made for arbitrary external proc values.
