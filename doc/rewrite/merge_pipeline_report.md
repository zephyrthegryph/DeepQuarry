# Merge pipeline: where the time goes, what changed, what is left

Branch `rewrite/merge-speed`, 2026-10-08. The tooling is described in `doc/rewrite/agent_workflow.md` section 9. This
file holds the measurements and the reasoning. "Measured" means read from a log or run JSON; "estimated" means my
arithmetic from those numbers. The machine was loaded by other agents' builds for the whole session, so read the spread
rather than the digit.

## 1. Timing data

Sources: 333 `data/test-runs/*.json` records (main checkout plus 24 worktrees), 179 build logs with Juke
`Finished 'x' in Ns` lines (`E:/projects/dq-wt/*.log`, `focus*.log`, worktree `data/` logs), 73 `data/logs/runN/tests.log`
files for world boot times, `doc/rewrite/build_timings.md`, and this session's own runs. Juke stage timings cover every
`build.sh` target; `check_ratchets.sh` is not a Juke target, so its numbers are this session's.

### Per stage

| Stage | Typical (median) | Worst seen | n | Notes |
|---|---|---|---|---|
| Worktree checkout, fresh worktree of about 24k files | not logged; the merge agents reported up to 30 min | 30 min (reported) | - | Measured here: the persistent worktree's one-time creation, with `gen`, took 3 min 0 s on the loaded machine |
| Persistent worktree update (`dq_merge_worktree.sh`) | 9 s | 9 s | 2 | fetch + clean check + `git switch -C` to a moved origin/master |
| `analyze gen` (`gen`) | 13 s | 106 s | 130 | 126 s was the first, cold run in the new worktree; 3-4 s when warm |
| `analyze-build` (cargo build of the analyzer; cache miss) | 307 s | 558 s | 21 | 21 logs of 179 paid it. A cache hit costs 0 (`analyze cache: hit`) |
| `icon-repack` | 21 s | 202 s | 123 | 1-7 s of work; the rest is contention (dirty-check starved) |
| `validate-dme` | 4 s | 68 s | 119 | |
| `map-bounds` | 45 s | 111 s | 12 | |
| `verdigris-bindings-check` | 0.4 s | 101 s | 94 | 63 s at p90: runs after Rust or DM-list changes |
| `build.sh dm` (production DreamMaker + DreamChecker beside it) | 59 s | 224 s | 19 | |
| DreamChecker alone (`dream-checker`) | 93 s | 233 s | 31 | |
| Test compile + world (`dm-test` total, focused run) | 355 s | 562 s | 27 | includes prerequisites, DreamMaker test compile, boot, tests. Measured here: DreamMaker test compile 5 min 21 s under load |
| `build.sh lint` (tgui lint + DreamChecker + analyze) | 2 min 29 s | - | 1 | measured here; tgui-tsc 45 s, DreamChecker 93 s, analyze 29 s (medians) |
| `check_ratchets.sh` | 1 min 26 s | - | 1 | measured here, loaded machine |
| Test world boot (process start to "Unit-test suite starting") | 28 s | 390 s | 73 | p90 55 s |
| Settle before the first test | 0 s | 23 s | 72 | |
| Whole focused world, suite start to finish | 78 s | 1460 s (24 min) | 56 | p90 315 s |
| Focused run wall time, records with 1-3 tests | 25 s | 2909 s | 152 | p90 392 s (a look pin is in the tail) |
| Focused run wall time, 101-400 tests | 226 s | 645 s | 18 | |
| Focused run wall time, 400+ tests (sharded) | 384 s | 1057 s | 33 | |
| `dq_look_state_pin` alone | 1799 s (30 min) | 3147 s (52 min) | 9 | the user quoted about 22 min on a quiet machine |
| `dq_look_tree_pin` alone | 294 s | 460 s | 6 | 639 s in this session's loaded run |
| `dq_conversion_pin` alone | 230 s | 340 s | 35 | |
| Test-run exit / watchdog | 3 logs show "force-killing daemon (hard timeout)" | | 3 | the 15-minute focused default; a look pin needs `DQ_FOCUS_TIMEOUT_MINUTES` |

### The 20 slowest tests (median of the runs that recorded a duration, with the worst)

| # | Test | n | Median | Worst |
|---|---|---|---|---|
| 1 | `dq_look_state_pin` | 9 | 1799 s | 3147 s |
| 2 | `dq_look_tree_pin` | 6 | 294 s | 460 s |
| 3 | `dq_conversion_pin` | 35 | 230 s | 340 s |
| 4 | `dq_hit_pin` | 2 | 112 s | 112 s |
| 5 | `dq_constraint_parity/equip` | 20 | 70.5 s | 105 s |
| 6 | `dq_property_type_values_valid` | 28 | 55 s | 92 s |
| 7 | `dq_rule_thresholds` | 24 | 54.5 s | 76 s |
| 8 | `dq_latent_collapse` | 12 | 29 s | 38 s |
| 9 | `dq_state_collapse_blockers` | 28 | 28 s | 63 s |
| 10 | `all_clothing_shall_be_valid` | 32 | 27 s | 58 s |
| 11 | `dq_constraint_parity/storage` | 21 | 24 s | 49 s |
| 12 | `dq_machinery_audit_pin` | 1 | 18 s | 18 s |
| 13 | `dx_menu_order` | 13 | 14 s | 48 s |
| 14 | `dq_lifecycle_sandbox` | 27 | 11 s | 286 s |
| 15 | `dq_timed_pin_w7/h_straight_jacket_resist` | 1 | 11 s | 11 s |
| 16 | `dq_constraint_parity/suit_storage` | 20 | 9.7 s | 29 s |
| 17 | `dq_timed_pin_w7/h_straight_jacket_resist_cancel_on_move` | 1 | 8.6 s | 8.6 s |
| 18 | `dq_shuttle_repeated_moves_preserve_air` | 32 | 8.5 s | 10 s |
| 19 | `dq_station_alarm_component_is_sealed` | 32 | 8 s | 55 s |
| 20 | `dq_machinery_audit_pin/i7` | 1 | 7.7 s | 7.7 s |

One test is more than 60% of every pin batch: `dq_look_state_pin` is about 6 times `dq_look_tree_pin` and about 8 times
`dq_conversion_pin`. The other 19 together are about 15 minutes.

## 2. What changed

| # | Change | Where |
|---|---|---|
| 1 | Persistent merge worktree `E:/projects/dq-wt/merge-base`, branch `rewrite/integ-current`, moved with `git switch -C ... origin/master` (the guard allows `switch`); clean/unpushed/merge-in-progress checks; `--discard-previous` keeps the old tip as a branch | `tools/dq_merge_worktree.sh` |
| 2 | Known master failures list and checker; refresh hooked into the push script, only when a focused run JSON for the pushed head exists | `tools/ci/known_failures.txt`, `tools/dq_known_failures.{sh,js}`, `tools/dq_push_master.sh` |
| 3 | `--split-slow`: the slow pins run in a second world (`run2`) from the same `.dmb`; merged JSON and exit code | `tools/dq_focused_test.sh`, `tools/dq_merge_test_runs.js`, one line in `tools/build/build.ts` (`DQ_KEEP_DERIVED_DME`) |
| 4 | `FOCUSED RESULT:` line; `--detach` and `--status <runid>` | `tools/dq_focused_test.sh` |
| 5 | One pre-test gate script; the push script skips only the ratchets run that the gates already ran on the identical HEAD | `tools/dq_merge_gates.sh`, `tools/dq_push_master.sh` |

Interfaces kept: every existing `dq_focused_test.sh` flag and its exit status are unchanged for a selection with no slow
pin (a single world, the same `build.sh dm-test --focus=...`); the split is on by default only when a slow pin and another
test are selected together, and `--no-split-slow` / `DQ_FOCUS_SPLIT=0` restores the old single-world run. The output now
also carries the final `FOCUSED RESULT` line, and `tee`s dm-test's output into a log. `dq_push_master.sh` runs everything it
ran before unless a stamp for the exact HEAD says ratchets passed.

No correctness check is lost: the gates run gen, the test compile and boot gate, and ratchets before the tests; the push
script still runs production `dm` (DreamMaker 0 errors), DreamChecker, `analyze` and (unless stamped for this exact HEAD with
the release analyzer) ratchets on the merged HEAD, and a stamp is invalidated by any commit or tracked change. Dropping
`build.sh lint` from the pre-test list loses nothing, because `lint` is DreamChecker + analyze + tgui lint, all repeated in
the push script (tgui lint remains in the gates when the batch touches `tgui/`).

### What was verified in this session

- Persistent worktree: created in 3 min (including a cold `gen`), updated in 9 s when master moved, aborts on an untracked
  file, aborts on an unpushed commit, and `--discard-previous` kept the tip as a branch (removed afterwards).
- `dq_known_failures.sh --check` against a real integration run (`rewrite/integ-14`, 7 failures): 2 KNOWN, 5 NEW; `--refresh`
  bumped the sha of the two known entries (reverted); `--refresh-for-head` reports "no focused run JSON for head" and leaves the
  file alone.
- `--split-slow dq_look_tree_pin dq_boot_gate`: both worlds ran concurrently as `run1` and `run2` (two `data/runs` slots, two
  ports, two log dirs); world 2 printed `compileDerived: reusing deepquarry.test.dmb`, so there was one compile; the two records
  merged into one `data/test-runs/20261008T204715_04faf2744a_focused.json` (2 passed, 0 failed, `split_worlds` 2, worlds 131 s
  and 639 s); the script printed `FOCUSED RESULT: 2 passed, 0 failed (json: ...)` and exited 0. Wall time was dominated by the
  loaded machine (the DreamMaker compile alone took 5 min 21 s), so it is not a speedup measurement.
- `--detach` / `--status`: `--detach dq_boot_gate` returned at once with a run id; `--status` printed state, elapsed time and
  the log tail and exited 3 while running.
- `bash tools/ci/check_ratchets.sh`: All ratchet lints passed. `tools/build/build.sh lint`: 0 DreamChecker diagnostics, passed.
- Not run: shellcheck (not installed; I reviewed the scripts by hand and `bash -n` them), the full suite, a real
  `dq_push_master.sh` push (the stamp and known-failure refresh paths were read, not exercised), and a `--status` on a
  failed run.

## 3. Projection

A merge batch, using medians and the batch the user described. Loaded-machine numbers; the user's checkout figure is the
only one I could not measure.

| Phase | Before | After |
|---|---|---|
| Worktree | 10-30 min (checkout of about 24k files, cold caches) | 0.2 min (update), warm analyzer, icons, verdigris, dmb cache |
| gen + test build + boot | gen 0.2 + test build 6-9 min | same compile (6-9 min), once; `.dmb` reused by every later run |
| Production `dm` + `lint` before tests | 1-4 min + 2.5 min | 0 before tests (they run once, in the push script) |
| check_ratchets before tests | 1.5 min | 1.5 min (the push skips its repeat) |
| Focused batch | one world: look_state_pin 22-30 min + the rest 8-15 min in series if run in one world | max(look_state_pin 22-30, rest 8-15) = 22-30 min |
| Failure triage (per failing test: new origin/master worktree) | 10-30 min checkout + 6-9 min compile + run, per failure, 2-3 failures | 0 for KNOWN failures (a file lookup); a NEW one is one focused run in `merge-base` |
| Rerun after bless | 22-30 min if the look pins are in the rerun | same 22-30 min (see bottleneck) but in parallel with the rest, and the compile is cached |
| Push script | dm 1-4 + ratchets 1.5 + analyze 0.5 | dm 1-4 + analyze 0.5 (ratchets skipped when stamped) |
| Waiting on monitors / hand-backs | an extra poll-and-resume round trip per wait | poll `--status` |

Estimated batch wall time: before, about 100-150 minutes (10-30 checkout, 9-12 gates, 30-45 focused batch, 20-60 for triage
worktrees, 22-30 rerun, 5-7 push). After, about 60-80 minutes (0.2, 8-11 gates, 22-30 focused batch, about 0 triage, 22-30
rerun when the look pins must rerun, 3-6 push). If no look pin needs a rerun after bless the batch is about 40-50 minutes.
These are estimates, not a measured batch.

**What remains the bottleneck: `dq_look_state_pin`, run once or twice per batch.** It is one test in one world, 22-52
minutes on its own, and nothing the scripts do shortens it; they only stop it from queueing behind other work. Options, in
order of payoff:

1. Shard `dq_look_state_pin` itself across worlds. A test can already know its shard (`sweep_owns(index)` in `doc/testing.md`
   "Sharded runs"); the pin walks types one by one, so four slices should take it from 22 to about 6-8 minutes. This is a
   test change, not a tooling one, and was out of scope here. `--split-slow` then grows to one world per slice.
2. Incremental look pin: re-probe only the types whose files, declarations or tracked variables changed since the last
   recorded run (`--incremental` machinery for sweeps exists, `SWEEP_INCREMENTAL_SCOPE`).
3. The second compile and boot per run (about 25-60 s) and the 5-9 minute DreamMaker compile are fixed costs per batch. The
   persistent worktree keeps them cached, but a changed `.dm` file means a recompile.

## 4. Common issues found in the run logs, with counts and a tooling fix for each

Counts come from the run records and logs listed at the top (326 test-run records readable, 582 log files, 5064 commits
since 2026-09-25 of which 798 are merges). A count of 0 means I found no trace in those sources, not that it never
happened.

| Issue | Count found | Evidence | Proposed tooling fix |
|---|---|---|---|
| Stale or missing analyzer binary, cold cargo rebuild | 21 cargo builds in 179 stage logs, median 307 s, worst 558 s; 5 logs show `analyze cache: hit` | `analyze-build` stage times; `AGENTS.md` section 4 | Kept warm by the persistent worktree. Add a hash check to `dq_merge_gates.sh` that prints "analyzer rebuilt" when the stage was not a cache hit. Done for the cache itself earlier (`E:/dq-cache/analyze-bin`) |
| CRLF churn from `--bless` | 2 mentions in docs (baton file line endings, `intended_changes.md` Batch 8 pins) | `doc/rewrite/intended_changes.md` | Make the snapshot writer emit the line ending the committed file already has (or LF only, with `.gitattributes` `eol=lf` for `snapshots/`); `git diff --ignore-cr-at-eol --stat` as a post-bless check in `dq_focused_test.sh --bless` that warns when a file changed only in line endings |
| Order-dependent pin rows | 7 batch notes in `intended_changes.md` (batches 7b-12, e.g. `blob/core` colours, `electronic_assembly`, `baton` rows) plus 670 test messages carrying the "rng seed ... reruns this test alone" hint | run records; `intended_changes.md` | After a bless, rerun the blessed pins once in a second world with a different seed and fail if the rows differ (add `--bless-verify`); list seeded/random types in the pin so they are skipped by construction |
| Leaks on the pin tile / between tests | 314 `UNIT TEST LEAK` messages in 23 runs; 384 `STATE LEAK` lines in 52 logs; the top STATE LEAK is `dq_look_tree_pin` changing the six `GLOB.chamelion_*_choices` lists (15 logs each) | run records, logs | Reset those globals at the end of the pin (`set_global()`), and make the leak a failure of the leaking test rather than a warning, so the culprit is named in the result line. A `dq_known_failures.sh --check` run already separates these from real regressions |
| Watchdog kills | 3 logs (`force-killing daemon (hard timeout)`), all focused runs of the look pins past the 15 min default | logs | The split run now defaults the slow world to 45 minutes; the real fix is sharding the look pin (section 3). Print the elapsed/limit in the `--status` output so a coming kill is visible |
| Globs matching abstract parents | 1 fix commit (`0be96781c3`, an abstract parent run as a test); `023e71cf8b` already restricted globs to compiled types | `git log` | `dq_focused_test.sh --list` should drop types that have no `Run()` of their own and are only parents; add a `--list-abstract` report so a glob that expands to a parent is visible |
| Tests that never ran because the type was not compiled or not declared | 4 commits (`21bafdfd3e`, `023e71cf8b`, ...); the script now refuses an uncompiled name | `git log`, script comments | Already refused by name. Add a post-run check that every focused name appears in the result JSON and fail the run with "N focused tests never ran: ..." (the world can skip a test silently on a boot failure) |
| Generated-file test guards (test-only types in generated code) | 8 commits (`1f3d51a97b`, `783de9acca`, `9ebc513b49` ...) | `git log` | Already a hard failure in `analyze gen`. `dq_merge_gates.sh` runs it first so it fails before the 6-9 minute compile |
| Duplicate `TRACKED` / duplicate definitions after a merge | 2 commits (`e5edaa186f`, `276e3d1c53`); 35 "duplicate definition/var" lines in 7 logs | `git log`, logs | `gen` or ratchets should list a variable declared twice in one type with both sites (the merge result of two branches adding the same line); run it in `dq_merge_gates.sh` before the compile, where it is cheap |
| Duplicate CAPABILITIES blocks after a merge | 3 distinct messages in logs (`two_blocks` / `gen/declare`) | logs | Same gate position: the semantic lints already catch it; the gates run them before the compile |
| Merge conflicts to settle by hand | 15 `CONFLICT (` lines in 3 logs; 798 merge commits since 09-25 | logs, `git log` | Keep `dq_merge_master.sh`. Not done: `merge=union` for `known_failures.txt` (union would resurrect a line a refresh removed), so it is left to ordinary merges |
| Pre-existing failures re-proved with a throwaway worktree | every merge batch: 2 pins failing on master at the moment | coordinator report | `known_failures.txt` plus `--check`. Needs one owner to keep it honest: `dq_push_master.sh` refreshes it when a run exists for the pushed head |
| Whole-pin failures from a changed menu (`dq_conversion_pin` 32 failed runs, `dq_interaction_domain_snapshot/i7_bulk` 9) | 32 / 9 | run records | These are the intended-change class; the existing diff report per snapshot file is right. A `--bless` summary line ("N rows in M files changed") printed by the script would help the reviewer decide in one look |
| Agents handing back while a monitor ran | reported, not in the logs | coordinator report | `--detach` + `--status` (section 9), with the rule written down |

## 5. Risks of this change

- `--split-slow` runs two `dm-test` invocations against one worktree. They share `data/`, the `.dmb` cache record and the
  derived `.dme`; the second waits until the first has launched its world (so the compile is done) and
  `DQ_KEEP_DERIVED_DME=1` stops the first from deleting the `.dme` the second reads. If world 1 dies before launching, world
  2 is not started. A test that depends on running in the same world as another test (state leaked forward) would behave
  differently split; use `--no-split-slow` to reproduce the old order.
- `dq_push_master.sh` now makes a second, data-only commit on master (`tools/ci/known_failures.txt`) after a successful push
  when a run for that head exists. It uses the same `DQ_PUSH_VERIFIED` mechanism; set `DQ_KNOWN_FAILURES_REFRESH=0` to turn it
  off. It is best effort and never fails a push.
- The persistent worktree is a single shared resource: two coordinators using it at once would trip the "commits origin/master
  lacks" check, which is the only guard; there is no lock.
