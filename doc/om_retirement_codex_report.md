# Codex OM retirement handoff

Date: 2026-10-06. Worktree: `E:/projects/dq-wt/codex-om-retirement-1006`.
Branch: `codex/om-retirement-1006`; starting integration commit: `9a28a84008`.
Four ordered slices were prepared on the integration base; only this private branch is published. Counts below distinguish actual conversions from pre-existing zeroes and partial audit evidence.

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

## Task 4 / C4: delayed argument guards

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

The durable [per-handler audit](om_retirement_timer_audit.csv) retains original base line anchors and `BaseStatus`; final statuses distinguish fixed callbacks from body-reviewed and callsite-only holds. Its `ReviewCoverage` categories explain limited evidence. Neither the 502 total nor the 239 subset should be described as 502/239 fully proven-safe handlers. The two denominators overlap and must not be added together.

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

Additional cleanup-sensitive sites remain held: recycling crusher completion must retain its power/working reset; NIF vending must retain ownership and readiness cleanup; firearm reload/burst require inventory/draw closure; artifact revival must preserve revival independently of its holder; resleeving needs an absent-record policy; toy brawls need reciprocal controller cleanup. No head-return conversion was applied to these. The CSV retains the exact source anchors and evidence limitations.

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
