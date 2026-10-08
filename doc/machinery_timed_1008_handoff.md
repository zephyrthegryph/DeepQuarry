# Machinery timed-action handoff — 2026-10-08

Branch: `codex/machinery-timed-1008`. Assigned base: `origin/rewrite/timed-tasks` at `059aac8767`; master did not yet contain the required timed forms. Only this branch is pushed.

## Conversion counts

| Explicit form in machinery/power | Before | After |
| --- | ---: | ---: |
| `task_timed` | 22 | 2 |
| `task_busy` | 5 | 0 |
| `task_start` | 1 | 1 |
| `task_hold_busy` | 0 | 0 |
| `om_task_periodic` | 0 | 0 |
| Total | 28 | 3 |

Twenty-five explicit calls are retired across sixteen completed files plus partial cryopod self-entry. Camera and camera assembly also retire two indirect `use_tool` paths. `timed_forms_converted` gains sixteen file entries banning the requested explicit forms. The AI-core file still has the separate helper paths listed below; this is not a claim that its construction ladder is fully migrated.

Native waits cover IV/feeder/doorbell dismantling, food scanning, beacon deployment, painting, printer/cloner loading, AI-core cable/glass installation, breaker switching, camera welding, washing-machine escape/loading, oxygen placement, VR entry, cryopod self-entry and suit-storage entry/loading. Start effects, delays, costs, custody and interruption are tested using real objects and inputs. Camera wire requirements subscribe to the existing published wire key; suit-storage door/power/broken fields publish tracked writes.

## Remaining explicit calls and why

* `code/game/machinery/medical_kiosk.dm:110`: `task_start` reserves the active user and power state before a question. Native `starts()` runs at the first positive wait, after questions, and cannot express reversible pre-question session effects. No fabricated zero/tiny wait or custom request handler was introduced.
* `code/game/machinery/cryopod.dm:713`: loading obtains consent from the passenger while the loader is the actor. `asks()` currently addresses the actor; a separate answerer is required. Self-entry is converted.
* `code/game/machinery/suit_storage/suit_cycler.dm:212`: an electrified cycler immediately shocks the loader and may abort before its delay. Native start effects cannot abort, while takeover runs after waits. A side-effecting requirement or delayed shock would change behaviour.

Additional indirect timed helpers remain in AI-core construction: wrench at states 0/1 (lines 109/111), welder at line 125, and wrench/unbolt paths at lines 275/278. These were not in the requested explicit-call census and did not receive old-code pins for conversion. Other request flows are unchanged, including replicator printing and VR avatar requests.

## Pins and verification

Eighteen old-code conversion snapshots were recorded and committed in `c90121166c` before native snapshots are accepted. Forty-three real-input behaviour checks were written first: thirty-nine initially passed; four grab-loading fixtures were corrected to select the actual menu operation instead of the generic UI click, then all four passed against unchanged legacy loading code. That preparatory run compiled with zero errors and 46 existing warnings; boot was clean. Additional native regressions cover unsupported cryopod actors, fast welders, live wire repair and electric charge/cancellation.

Per-class snapshot causes are documented in `doc/rewrite/intended_changes.md`. Existing breaker tests now observe native pending work/claims and typed contention, preserving the lock refusal. No debt annotations, ceilings or baseline additions were introduced. No full suite, shard run or Rust workspace suite was run.

Final verification results will be appended after the combined batch and lint pass.

## Ratchet changes

Official `analyze baseline --update` removed only debt:

| Baseline | Before | After | Cause |
| --- | ---: | ---: | --- |
| `sys/usr_use` | 132 | 131 | Oxygen placement carries its actor through a native drag op. |
| `sys/dx_review` | 199 | 198 | Cutout painting uses chained `asks()` instead of an effect opening a request. |
| `escape_hatches` / `usr_content` | 137 | 136 | The same oxygen `usr` read is removed. |

No baseline identities were added or renamed. All other baseline files are unchanged.

The first post-edit batch found two failures: the AI-core requirement lacked a typed refusal reason, and the electric charge assertion omitted physical cell delivery loss. Both were repaired together; the runtime-produced AI-core snapshot was discarded before the repair batch. The electric assertion remains exact, using the real cell efficiency API rather than a tolerance. The final repair result is recorded below.

## Final verification

* Focused repair batch: **55 passed, 0 failed, 0 skipped** (57 selected types include two abstract bases). This includes all 49 new real-input checks, five existing machinery/storage checks and the scoped conversion-pin capture. Result: `data/test-runs/20261008T063859_c90121166c.json`.
* DreamMaker for that batch: **0 errors, 46 pre-existing warnings**, with a clean boot and no state leaks.
* Native snapshot review: **10 files changed, 51 rows added and 22 removed**; eight old snapshots remain byte-identical. Each changed class is explained in `intended_changes.md`. No runtime/error snapshots were accepted.
* Final `build.sh lint`: passed, **0 DreamChecker diagnostics**, TypeScript and Biome clean, all analyze ratchets passed.
* The final lint pass required three small follow-ups after the focused batch: an explicit human cast before the oxygen anatomy helper; routing suit-storage stumble closure through its tracked setter; removing the now-unused read annotation on the suit-storage UI gate. These final edits are statically verified by DreamChecker and analyze, but were not recompiled or rerun under the build limit. A narrow extra verification batch was offered for explicit approval.

Focused selections: `dq_machinery_timed_conversion_pin`, `dq_timed_pin/machinery_*`, `dq_machinery_timed_material_pin/*`, `dq_hc_struct/breaker_locked_click_refuses`, `dq_hc_struct/breaker_busy_click_refuses`, `dq_c8a_suit_storage_occupant_slot`, `dq_hc_struct/camera_bug_click_round_trip`, `dq_hc_struct/suit_storage_door_and_lock_work_until_it_is_broken`.
* Final `bash tools/ci/check_ratchets.sh`: passed, including generator consistency checks. Generated files remain uncommitted.
