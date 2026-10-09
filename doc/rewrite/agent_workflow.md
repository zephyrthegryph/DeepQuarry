# Agent workflow: build, test, merge

What changed in the build/test/merge loop (October 2026, `rewrite/infra-speed`) and what to do on your
next merge. Read this once; the rest of the loop is in `AGENTS.md` section 4 and `doc/testing.md`.

## 1. Generated files are no longer committed

`analyze gen` output is build output now:

| Path | Written by |
|---|---|
| `code/engine/_generated/*.dm` (declare, ids, reads, stats, actions, event_twins, system_accessors) | `analyze gen` |
| `code/_generated/reads.dm` | `analyze gen derived_reads` |
| `tgui/packages/tgui/interfaces/generated/*.d.ts` | `analyze gen ui_types` |

They are in `.gitignore` and untracked. Every build target that compiles or lints DM runs `GenTarget`
first (`build.sh dm`, `dm-test` and so `tools/dq_focused_test.sh`, `lint`, `analyze`,
DreamChecker; the production build and TGS go through `build.sh dm` too). `bash tools/ci/check_ratchets.sh`
writes them as well. Regenerate by hand with `tools/build/build.sh gen` (about 3 s warm, 18 s cold).

`analyze gen` rewrites only files whose text changed, so an unchanged tree keeps its mtimes and the
`.dmb` caches still hit. It iterates to a fixed point (some generators read another's output), so one
run from an empty tree is enough.

**What replaced `analyze gen --check`.** Staleness can no longer reach master: nobody commits the
files, and every compile regenerates them. What still matters fails the generating step itself, in the
build and in `check_ratchets.sh`: a generator diagnostic (a bad declaration), a test-only type
outside the `UNIT_TESTS` guard, a generated file missing from `deepquarry.dme`. `analyze gen --check`
still exists for a quick read-only look.

**Still committed, on purpose:**

- `deepquarry.dme`: hand-written; its `#include` lines name the generated files, which the compiler
  only needs after `gen` ran.
- `code/_generated/om_notices.dm` and `tools/dx/codemods/om_event_map.json`: written by the Python
  `tools/dx/gen_om_notices.py`, which codemods read without a build; they rarely change.
  `check_ratchets.sh` still runs its `--check`.
- The verdigris bindings (`code/__defines/verdigris/_bindings.dm`, `verdigris/ffi/src/abi.rs`): cargo
  compiles `abi.rs` directly, outside `build.ts` (CI, `verdigris/build-*.sh`, rust-analyzer).

**The analyze binary is cached.** A fresh worktree copies the `analyze` binary from
`E:/dq-cache/analyze-bin/<source hash>/` (`DQ_ANALYZE_CACHE`, `off` disables) instead of a 2 minute
cargo build. A miss builds and stores it. `tools/ci/analyze.sh` goes through the same cache.

**The analyzer is built in the worktree's own `tools/analyze/target`, the `dev-fast` profile everywhere** (the gates and the push
script no longer force `release`, a 2-4 minute non-incremental thin-LTO build; the findings are identical, CI builds release).
Do not share a cargo target dir between worktrees (`DQ_ANALYZE_TARGET=<dir>` still exists and is a hazard): cargo names a path
package's artifacts and fingerprints by its path inside the workspace, not by where the checkout is, and judges freshness by file
mtime, so a worktree whose sources are older than the library another worktree just built links that one, either failing to
compile or building a binary from someone else's sources and caching it under its own key. Compiled dependencies are shared
through sccache. An edit to the analyzer rebuilds incrementally (about 1 minute under load); a fresh worktree's first build is
about 3 minutes unless the binary cache has its source.

**`analyze gen` is memoized and parses the model once** (`tools/analyze/README.md`, "How `analyze gen` stays fast"): a run whose
inputs and outputs are unchanged returns in about half a second, and a merge that changes declarations parses the full model one
time instead of once per pass. The outputs of a converged run are also kept in a content-addressed store (`E:/dq-cache/gen-store`,
`DQ_GEN_STORE`), so a fresh worktree of a commit another worktree already generated, or the merge of a lane whose lane-ready run
generated the same tree, copies the files back in about a second instead of regenerating them.

## 2. What to do on your next merge

Run, from your worktree:

```sh
bash tools/dq_merge_master.sh
```

It fetches, merges `origin/master`, resolves the modify/delete conflicts on the generated files as
"untracked" (`git rm --cached`; the files stay on disk), untracks any generated file your branch still
tracks, commits the merge and regenerates. Any other conflict is listed for you to resolve as usual.
It never runs checkout, reset, restore, stash or cherry-pick.

By hand, the same thing is: `git merge origin/master`; for each conflict under
`code/engine/_generated/`, `code/_generated/reads.dm` or `tgui/packages/tgui/interfaces/generated/`,
`git rm --cached <path>`; resolve the rest; commit; `tools/build/build.sh gen`.

After that merge, never `git add` those paths (they are ignored; `git add -f` would bring the
conflicts back). Don't commit regenerated output after a declaration change: commit the declaration.

## 3. Include lists merge by union

`deepquarry.dme` and `code/modules/unit_tests/_unit_tests.dm` have `merge=union` in `.gitattributes`:
two branches that each add an `#include` at the same spot both keep theirs instead of conflicting.
Union cannot tell an edit from an addition, so after a merge that touched either file, build: an
include of a file the other side deleted fails the compile ("cannot find"), and a duplicate `#include`
is harmless. Keep the lists sorted.

## 4. Boot must be clean

Every unit-test run fails when the world logged a runtime or a `WARNING()` (or a refused `move_into()`)
before its first test, and the build prints `BOOT GATE:` with the first lines. It is the boot's fault, so
fix it where it is logged (`doc/rewrite/boot_gate.md`). `bash tools/dq_focused_test.sh --boot` checks boot alone.

## 5. Pushing to master: only through `tools/dq_push_master.sh`

```sh
bash tools/dq_push_master.sh
```

This is the only way to push to master. It fails closed: it refuses a dirty tree, merges `origin/master`
(through `dq_merge_master.sh`), runs `build.sh dm` (DreamChecker must run and report 0 diagnostics, DreamMaker
0 errors), `check_ratchets.sh` and `build.sh analyze` on that exact merged HEAD, checks nothing moved, and only
then pushes (never forced; if master moved it merges and rechecks). Logs go to `data/push-check/`. A hand-made
merge-and-push chain once pushed past DreamChecker errors and broke master; don't write your own.

`tools/hooks/pre-push` refuses any push to master that did not come from the script
(`bash tools/hooks/install_pre_push.sh` installs it for every worktree).

## 6. Interaction snapshots are per-type files

`doc/rewrite/snapshot_pins.md`. The i7 snapshots keep their rows in
`code/modules/unit_tests/snapshots/<name>/<type>.txt`, one file per type, read at run time: parallel
conversions touch different files and a snapshot-only change needs no recompile. Re-record with
`bash tools/dq_focused_test.sh --bless 'dq_interaction_domain_snapshot/*'`. A branch that edited the old inline
`expected = list(...)` in `dq_i7_*_capture.dm` conflicts once: take master's file, then re-bless.
Before converting a type, `bash tools/dq_pin.sh /type/path` records a generated pin of its menu, refusals,
clicks and wires; after, `bash tools/dq_focused_test.sh dq_conversion_pin` shows what changed.

## 7. Order-dependent failures

A test that fails in a long focused run but passes alone leaks or inherits shared state. Every run now logs
`STATE LEAK` lines in `tests.log` (and prints them when the run fails) for each global flag a test left changed;
the culprit is the leak before the failing test. Fix it with `set_global()`/`set_var()` in the leaking test.

## 8. Faster loop

`doc/rewrite/build_timings.md` has the numbers. What you notice: `build.sh dm` runs DreamChecker beside
DreamMaker, the verdigris bindings check is skipped when its inputs did not change, a focused run starts with
2 test blocks instead of 8, and `tools/build/build.sh dmb-check` (or `DQ_DMB_PRECHECK=1`) is an optional 14 s
syntax pre-check from the Codex compiler.


## 9. Merge batches (October 2026, `rewrite/merge-speed`)

Measured data and reasoning: `doc/rewrite/merge_pipeline_report.md`. The batch recipe, in order:

```sh
WT="$(bash tools/dq_merge_worktree.sh)"            # 1. the persistent worktree, moved to origin/master
cd "$WT"
git merge --no-ff <branch> ...                      #    (bash tools/dq_merge_master.sh settles generated files)
bash tools/dq_merge_gates.sh --lanes "<branch> ..." # 2. gen, then the test world (smoke set + the tests of any lane whose stamp is stale),
                                                    #    the production compile + DreamChecker and the ratchets, side by side (section 11)
bash tools/dq_focused_test.sh --detach <more tests> #    only if a failure needs more tests: in the background
bash tools/dq_focused_test.sh --status <runid>      #    poll until it prints state=passed or failed
bash tools/dq_known_failures.sh --check <json>      # 3. NEW vs KNOWN failures (no throwaway worktree)
bash tools/dq_push_master.sh                        # 4. the fail-closed push (skips what the gates passed on this exact HEAD)
```

**Persistent worktree (`tools/dq_merge_worktree.sh`).** One worktree, `E:/projects/dq-wt/merge-base`, branch
`rewrite/integ-current`, is never removed. Each call fetches, checks it is clean, in no merge or rebase, and holds no
commit that origin/master lacks, then runs `git switch -C rewrite/integ-current origin/master` in it (`switch` is not
one of the forbidden commands and no discard flag is passed, so git refuses rather than lose work). Creation is a one-time
checkout (about 3 minutes measured); an update is about 10 seconds. `icons/gen`, the verdigris DLL (also cached in
`E:/dq-cache`), the analyze binary, `data/dmb-cache` and `node_modules` stay warm. If the last batch never reached
master it aborts and says so; `--discard-previous` keeps that tip as `rewrite/integ-prev-<stamp>` and moves on. Only one
batch uses the worktree at a time; the unpushed-commits check is the guard. Do not make a fresh worktree per batch.

**Gates once (`tools/dq_merge_gates.sh`).** `build.sh gen` and the prerequisites every build target shares (icon repack, map
bounds, DME check, verdigris: done once, so the jobs below never write the same file), then four jobs side by side, each with its
log in `data/merge-gates/<sha>.<job>.log`: the test world (`dq_focused_test.sh <the list>`: the test compile, the boot gate and the
tests in one world, which also leaves the compiled `.dmb` in the compile-hash cache), the production `build.sh dm` (DreamMaker
without UNIT_TESTS and DreamChecker beside it), `check_ratchets.sh` followed by `build.sh analyze`, and `tgui-lint` when the batch
touches `tgui/`. Do not also run `build.sh dm`, `build.sh lint` or `build.sh analyze` by hand before the push. On success the gates
stamp the exact HEAD (`data/merge-gates/<sha>.{ok,ratchets.ok,dm.ok,analyze.ok}`); `dq_push_master.sh` skips each check the
stamp says passed on that exact HEAD with a clean tree (`DQ_PUSH_FULL=1` forces them). A new merge commit (master moved) has no
stamp, so everything runs. `--serial` runs the jobs one after another to read one job's output.

**Known failures (`tools/ci/known_failures.txt`, `tools/dq_known_failures.sh`).** Tests that fail on master itself: spec, reason,
master sha last seen. `--check <run.json>` prints NEW and KNOWN failures (a focused run that has failures calls it for you),
so no throwaway origin/master worktree is needed to prove a failure old. `--refresh` drops entries that pass in a run and bumps
the sha of those still failing; `--adopt --reason` adds a run's NEW failures (a decision, never automatic). After a push,
`dq_push_master.sh` refreshes the list from the focused run JSONs for the pushed head if any exist (no tests run there);
a changed list goes in as its own data-only commit on top (`DQ_KNOWN_FAILURES_REFRESH=0` turns that off).

**Look pins (`dq_look_state_pin`, `dq_look_tree_pin`).** One sweep (`code/modules/unit_tests/dq_look_sweep.dm`) makes each creatable type once and
writes both snapshot sets: the made look is the tree row and the state pin's base, and every probe writes a var on that same instance, redraws,
captures, writes the original back and checks the look returned (a type whose look does not return is listed as `look sweep IMPURE` in tests.log and
probes on fresh instances). The vars probed are narrowed to those a draw can read by `analyze look-keys` (`data/look-plan.tsv`: per type a key and a
probe list, `*` meaning unknown, scan everything). `dq_focused_test.sh` runs the pins as `DQ_LOOK_SHARDS` (default 4, `--look-shards=N`) worlds from the
one compiled `.dmb`, each probing every Nth type (`sweep_owns`), beside one world for any other selected tests; the summaries merge into one
`data/test-runs/<id>_focused.json`. Without `--full` only types whose key differs from `code/modules/unit_tests/snapshots/look_keys.txt` are probed (no
changed type: no world is booted); a passing run that covered both pins rewrites that file, so commit it with the snapshots. `--full` probes everything
(merge worktree, nightly); `--bless` and `--repeat` run the pins unsharded and full; `tools/dq_pin.sh --look-state/--look-tree` records new pins with
`--look-shards=1 --full`. `--look-order=reverse|shuffle:N` reorders the types and `--look-dump=DIR` writes the rows each world produced, merged and
sorted under `DIR/merged` (two runs compare with `diff -r`): the determinism proof. `--no-split-slow` / `DQ_FOCUS_SPLIT=0` restores one world. Other
slow tests (`DQ_SLOW_TESTS`) still go to a second world. The slow world's timeout defaults to 45 minutes (`DQ_FOCUS_TIMEOUT_MINUTES` overrides it).
Worlds share no mutable file: each takes its own run slot (`data/runs/runN`), port, log dir, spritesheet dir and results file, exactly as shards do.

**At most two look-pin runs at once on the machine.** A run holding a look pin takes a `look_state_pin` slot (section 10; `tools/dq_look_lock.sh`
is the thin wrapper `dq_focused_test.sh` calls; `DQ_SLOTS_LOOK_STATE_PIN`, or the old `DQ_LOOK_PIN_SLOTS`, sets the count, 0 turns it off) before it
starts and gives it back when it ends. A third run prints `machine slots: look_state_pin: waiting` with its place in the queue and who holds the slots.

**Do not hand back mid-run.** `dq_focused_test.sh` ends every run with one line,
`FOCUSED RESULT: N passed, M failed (json: path)`, and its exit status. A long batch is started with `--detach`, which prints
`FOCUSED RUN STARTED: <runid>` and returns at once; poll `--status <runid>` (exit 0 passed, 1 failed, 3 still running, 2
unknown; it prints the state, elapsed time and the last log lines). A merge agent keeps polling, with short calls, until the state is
`passed` or `failed`; it does not hand its report back while a run it started is going, and it does not leave a background
monitor as the only thing watching one. Status files live in `data/focused-runs/<runid>.{status,log}`.

## 10. Machine-wide build slots (`tools/dq_machine_slots.sh`, `tools/build/lib/machine_slots.ts`)

A dozen worktrees compiling at once turn a 90 second DM compile into five minutes. The heavy steps now take a slot from a counting
semaphore shared by every worktree on the machine (state under `E:/dq-cache/slots`, `DQ_SLOTS_DIR`):

| Class | Default | Taken by | Count variable |
|---|---|---|---|
| `dm_compile` | 2 | every `DreamMaker()` compile (`lib/byond.ts`) | `DQ_SLOTS_DM_COMPILE` |
| `test_world` | a third of the CPUs, 2 to 6 (5 on 16) | each unit-test world's DreamDaemon launch (`runIsolatedTestWorld()` in `build.ts`: focused, split, look and sharded worlds) | `DQ_SLOTS_TEST_WORLD` |
| `cargo` | 1 | every cargo invocation of `build.ts` (analyze, verdigris, dmb-check) | `DQ_SLOTS_CARGO` |
| `look_state_pin` | 2 | a `dq_focused_test.sh` run holding a look pin, for the whole run | `DQ_SLOTS_LOOK_STATE_PIN` (old name `DQ_LOOK_PIN_SLOTS`) |

`DQ_SLOTS=0` turns all of it off and a class at 0 is unlimited. A waiter prints the class, its place in the queue and who holds the slots
(`worktree 'label' pid, held Ns`) every 30 seconds. The merge worktree (`E:/projects/dq-wt/merge-base`, `DQ_MERGE_WT`) jumps the queue
(`DQ_SLOT_PRIORITY=0` does the same for another caller); within a priority it is arrival order, and a slot is taken only by the first in the queue.
A holder that crashes does not block anyone: a slot or queue entry whose pid is gone (the Windows pid of a node or bash holder), or whose heartbeat
(its `owner` file's mtime, touched every 15 s) is older than `DQ_SLOTS_STALE_SEC` (600), is removed by the next waiter. Lock order when a run needs
several: `look_state_pin`, then `test_world`; `dm_compile` and `cargo` are never held while waiting for another class, so they cannot deadlock.

A run that launches several worlds (a sharded `dm-test`, the look/main/slow worlds of `dq_focused_test.sh`) takes their `test_world` slots **as a
group**: one queue entry, and the head of the queue takes slots as they free up and starts nothing until it has all it asked for, clamped to the
class capacity (a group larger than the budget could never be satisfied; `dm-test` clamps `--shards`, and `dq_focused_test.sh` starts the extra
worlds as earlier ones end). Only the head ever holds part of a group, so two sharded runs cannot each hold part of the budget and wait on each
other, and a sibling world never waits for a slot while another of the run's worlds holds one. The worlds the run launches carry
`DQ_SLOTS_PREHELD=test_world` and do not queue again; the run hands a slot back the moment its world exits. Shell: `slots_group_size`,
`slots_group_acquire`, `slots_group_release_one`; TypeScript: `acquireSlotGroup()`.

```sh
bash tools/dq_machine_slots.sh status              # who holds what, who waits
bash tools/dq_machine_slots.sh stats 40            # the last 40 releases (waited, held) and the mean per class
bash tools/dq_machine_slots.sh run cargo -- cargo test --manifest-path tools/analyze/Cargo.toml   # any command under a slot
bash tools/dq_machine_slots.sh selftest            # capacity, priority order, crash recovery, in a scratch directory
bun test tools/build/lib/machine_slots.test.ts     # the same protocol from the build tool, and the two implementations against each other
```

## 11. Lane-ready stamps: a lane proves itself once, a merge tests the combination

When a lane finishes, from its worktree:

```sh
bash tools/dq_lane_ready.sh --tests "dq_my_test dq_my_other/*"      # [--covers 'code/game/machinery/**'] [--no-pins] [--no-merge]
```

It merges current `origin/master` (`dq_merge_master.sh`), runs `dq_merge_gates.sh` on the merge (gen; one test world with the cross-branch
smoke set, your tests and the incremental look pins; the production compile and DreamChecker; the ratchets), commits the look keys and snapshots
the pins re-recorded, and writes the stamp: a git note on `HEAD` in `refs/notes/lane-ready` (JSON: the branch, the commit, the master commit it merged
and tested against, the tests, `--covers`, the results), a copy in `data/lane-ready/`, and pushes the notes ref (`DQ_LANE_NOTES_PUSH=0` keeps it local,
which all worktrees of this clone see anyway). A failing gate stamps nothing. Commit nothing but changelogs and docs after it: a later code commit
makes the stamp stale.

The merge agent asks `bash tools/dq_lane_check.sh <branch>...` (or lets `dq_merge_gates.sh --lanes "<branch> ..."` ask) whether each stamp still
covers the master it is about to merge into:

- `VALID, base is current`: the stamp's master commit is `origin/master`. The lane's tests ran on exactly this base.
- `VALID, master moved N file(s) ...`: the stamp's master is in `origin/master`'s history and what master changed since touches none of the files the
  branch changed, the directories those sit in, the stamp's `--covers` globs, the files that define its tests, or the global paths in
  `tools/ci/lane_ready_global.txt` (the test harness, the kernel, the analyzer, the build). Keep that list short: every entry stales more stamps.
- `INVALID`: master changed something the stamp depends on (the overlap is printed), the lane was rebased, code was committed after the stamp, or the
  stamp records a failure. The gates add that lane's tests to the combined world.
- `UNSTAMPED`: no stamp. Name the lane's tests with `--tests "a b"`, or have the lane run `dq_lane_ready.sh`.

A merge of stamped lanes is then: `git merge` them, `dq_merge_gates.sh --lanes "a b c"`, `dq_push_master.sh`. The gates run one test world holding
the smoke set (`tools/ci/smoke_tests.txt`: the boot gate and about 25 cheap tests across the engine, state, look/draw, construction, bodies, atmos, power,
ownership and timed ops; add a test that caught a bad combination) plus the tests of any lane whose stamp is not valid, next to the production build and
the ratchets. What the stamps do not prove is the combination of lanes, which is what the smoke world, the compile and the ratchets on the merged HEAD
are for. A failure there is diagnosed like any other (section 12), not answered by rerunning every lane's tests.

## 12. Diagnose before re-running (the rerun guard)

`dq_focused_test.sh` does not run the same argument list twice on the same tree within two hours (`DQ_FOCUS_RERUN_WINDOW_MIN`). The tree is HEAD plus the
tracked changes plus the untracked sources, so any edit lets the next run through; `data/focused-runs/ledger.tsv` is the record. Same list, same tree:

- the earlier run passed: the script prints `FOCUSED RESULT: (not rerun) ... already passed ...` and exits 0 (with `--detach` it still hands back a run id whose
  status is `passed`);
- the earlier run failed: exit 4 with `REFUSED` and a pointer to the failures in the result JSON, the world log and `data/focused-runs/`. **Read the log and the
  code first**: the same tests on the same code fail the same way unless the failure is order- or seed-dependent, and the log says when it is (`rng seed ...
  reruns this test alone`, `STATE LEAK`).

`--rerun-failed` (optionally `=data/test-runs/X.json`) runs only the tests that failed in the last recorded run, the way to check a flake; `--force <tests>` runs
the list anyway. `--bless`, `--repeat=N` and `--list` are never guarded.

A detached run that exits before it reaches a result (a bad test name, a signal) now marks its status file `failed` with the exit code and the log's last line,
instead of leaving `state=running`.
