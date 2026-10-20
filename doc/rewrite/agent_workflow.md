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
`E:/dq-cache/analyze-bin/<source hash>/` (`DQ_ANALYZE_BIN_CACHE`, `off` disables) instead of a 2 minute
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

It fetches, merges `origin/master` (`--no-commit`, so the normalized `look_keys.txt` goes into the merge commit itself instead of a
separate commit after it), resolves the modify/delete conflicts on the generated files as
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

It also refuses a HEAD without a passing test stamp (section 14): run `dq_lane_ready.sh` on a lane, or `dq_merge_gates.sh` on a
merge batch, before `dq_push_master.sh`.

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
2 test blocks instead of 8. The native compiler (the default; `DQ_COMPILER=dreammaker` falls back, doc/testing.md "Native compiler (incremental)") replaces the old
syntax pre-check.


## 9. Merge batches (October 2026, `rewrite/merge-speed`)

Measured data and reasoning: `doc/rewrite/merge_pipeline_report.md`. A single lane lands with one command that proves outside the lock and holds it for about a minute: `bash tools/dq_land.sh` (section 25). The batch recipe, in order:

```sh
export DQ_MERGE_SESSION=<your lane branch>         # 0. names your batch; every merge command needs it
WT="$(bash tools/dq_merge_worktree.sh --lanes "<branch> ...")"  # 1. take the merge lock (waits its turn), then the persistent worktree, moved to origin/master
cd "$WT"
git merge --no-ff <branch> ...                      #    (bash tools/dq_merge_master.sh settles generated files)
bash tools/dq_merge_gates.sh --lanes "<branch> ..." # 2. gen, then the test world (smoke set + the tests of any lane whose stamp is stale),
                                                    #    the production compile + DreamChecker and the ratchets, side by side (section 11)
bash tools/dq_focused_test.sh --detach <more tests> #    only if a failure needs more tests: in the background
bash tools/dq_focused_test.sh --status <runid>      #    poll until it prints state=passed or failed
bash tools/dq_known_failures.sh --check <json>      # 3. NEW vs KNOWN failures (no throwaway worktree)
bash tools/dq_push_master.sh                        # 4. the fail-closed push (skips what the gates passed on this exact HEAD); frees the lock
bash tools/dq_merge_worktree.sh --release           #    only if the batch is abandoned before the push lands
```

**The merge lock (one batch owns the merge worktree).** `dq_merge_worktree.sh` used to check that the worktree was clear and then merge
with no lock, so two agents passing the check together half-applied one `git merge` on top of the other and left a stale index. Now a call
takes the exclusive `merge_base` lock first (one slot, the machine-slot protocol of section 10: queue, atomic take, heartbeat, dead-holder
reclaim), waits for it while printing who holds it and for which lanes, and only then fetches, runs the clear check and moves the worktree.
It is held from that check until the push lands or the batch is abandoned, across `git merge`, `dq_merge_gates.sh` and `dq_push_master.sh`:

- **Holder.** The lock is kept by a small detached process (`dq_machine_slots.sh _hold`) that touches the owner file every 15 s and records the
  batch's lanes (`--lanes`) and the caller's session. It ends when the lock is released, or after `DQ_MERGE_LOCK_MAX_SEC` (6 h), so a forgotten
  batch cannot block the worktree forever. If it dies (killed, reboot) the next waiter reclaims the lock like any dead machine slot
  ("reclaiming a dead slot"). A call that fails the clear check (dirty tree, unpushed commits) frees the lock before it exits.
- **Who is the holder.** `DQ_MERGE_SESSION`, which every merge command must set explicitly (`export DQ_MERGE_SESSION=<your lane branch>`); it is recorded
  in the owner file and a later call is the holder only if its value is equal. It is never inferred (not from `CLAUDE_CODE_SESSION_ID`, which every lane
  of one agent session shares, and not from the process tree): `dq_merge_worktree.sh`, `dq_merge_gates.sh`, `dq_push_master.sh` and `dq_merge_master.sh`
  (in the merge worktree) refuse to run without it. Another lane joins the batch only through the holder: `bash tools/dq_merge_worktree.sh --join "<lane>"`
  (no switch, prints the path); a second plain call from the holder is refused, and anyone else waits.
- **Every mode takes the lock or refuses.** A call without `--lanes` queues as "unnamed batch" like any other; `--warm` and `--discard-previous` take the same
  path; only `--print-path` skips it (it changes nothing). A merge, commit or switch typed straight into merge-base, or run by an older copy of these
  tools, is caught by the `reference-transaction` hook (`tools/hooks/reference-transaction`, installed with `bash tools/hooks/install_pre_push.sh`): an update of
  `rewrite/integ-current` inside the merge worktree is refused unless the caller holds the lock. **Adopting an unpushed batch:** the owner of lanes already
  merged in the worktree runs `bash tools/dq_merge_worktree.sh --adopt --lanes "<branches>"`; it waits for the lock, requires the worktree clean, every lane
  in HEAD and still unpushed, then holds the lock for the current HEAD with no switch, re-merge or discard.
- **A heartbeat is not proof of life.** The holder process checks every 60 s (`DQ_MERGE_LOCK_CHECK_SEC`) whether its batch is over and releases the lock itself
  when the lane worktree that took it (or the merge worktree) no longer exists, or when the merge worktree's HEAD has moved since the batch began
  (`dq_merge_worktree.sh` records `base`) and is now in origin/master with no gate or push running (`dq_merge_gates.sh` and `dq_push_master.sh` mark
  `<slot>/busy` with their pid). The same session and worktree cannot queue twice: the second call is refused and the first keeps its place.
  The push used to release only when it ran inside the merge worktree, so a lane that was refused once, restamped and pushed from its own worktree
  leaked the lock (a detached holder heartbeated for 100 minutes); `release_batch` now releases whenever the caller holds the lock.
- **Release.** `dq_push_master.sh` releases it after a successful push, and also when HEAD is already in origin/master (the worktree is level with it).
  `bash tools/dq_merge_worktree.sh --release` ends an abandoned batch; only the holder may, `--release --force` overrides for a batch you know is
  dead. Never delete lock files by hand.
- **Refusals.** `dq_merge_gates.sh` and `dq_push_master.sh` exit 1 at the top when run in the merge worktree (`DQ_MERGE_WT`) by a caller that
  does not hold the lock. Other worktrees are unaffected.
- **Status.** `bash tools/dq_machine_slots.sh status` lists `merge_base` with its holder, lanes, pid and heartbeat; `bash tools/dq_machine_slots.sh
  merge-lock status` prints just that line.
- **No automatic stashing, no merge on a dirty tree.** The merge tools source `tools/dq_git_safe.sh`, which turns `merge.autoStash`, `rebase.autoStash` and
  `pull.autoStash` off for every git command they run, whatever any config says (none is set in the repo, the merge worktree or the global config; the
  first sighting came from a merge started while another batch had staged files), and `dq_merge_master.sh` passes `--no-autostash`, refuses to start in the
  merge worktree without the lock, and refuses when the tree has staged or modified tracked files.
- **Test.** `bash tools/ci/test_merge_lock.sh` runs two contenders against a scratch repo and worktree under `data/` (never merge-base) with its
  own slot directory: the second waits and names the holder, unlocked gates/push are refused, join/release are holder-only, a failed clear check
  frees the lock, a killed holder is reclaimed.

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
the sha of those still failing; `--adopt --reason` adds a run's NEW failures (a decision, never automatic). Nothing commits the list
automatically: `dq_push_master.sh` no longer refreshes it after a push. `dq_merge_gates.sh` does not fail on a known failure but prints
"KNOWN FAILURE STILL PRESENT - fix required"; a lane that fixes the test removes the entry in its own commit. A new failure still fails the gate.

**Merge-safe tooling.** `code/modules/unit_tests/snapshots/look_keys.txt` stays committed (it is the record of look keys a pin run
actually probed and matched, so it cannot be build output or regenerated from the tree) but never conflicts: `.gitattributes` gives it
`merge=union` and every merge script (`dq_merge_master.sh`, `dq_merge_gates.sh`, `dq_push_master.sh`) runs
`check_look_keys_format.sh --normalize` after the merge, which only drops rows (dead types, or a type the union left with two different keys)
and never writes a key. A plain `git merge --no-ff <lane>` in the merge worktree therefore succeeds. A type whose look changed in a lane or in
the merge matches no row (its key in `data/look-plan.tsv` differs), is *unverified*, and `dq_merge_gates.sh` runs the look pins over exactly that
set before stamping and records their keys into the merge commit (a lane-ready run does the same for its own lane). Do not hand-merge or regenerate it.
`dq_merge_gates.sh` records the tip of each `--lanes` branch and origin/master as the gates started (`lane_tips=`, `base_master=` in
`data/merge-gates/<sha>.ok`), refuses a lane that is not in HEAD, and shrinks the ratchet baselines (`analyze baseline --update`, never
adds) into the merge commit instead of a repair commit. `dq_push_master.sh` (`--expect "ref ..."` / `DQ_PUSH_EXPECT` add tips) refuses a
no-op push, refuses on `rewrite/integ-current` when origin/master moved since the gates (re-run them), and after the push fetches and
fails unless origin/master contains HEAD and every expected tip.

**Look pins (`dq_look_state_pin`, `dq_look_tree_pin`).** One sweep (`code/modules/unit_tests/dq_look_sweep.dm`) makes each creatable type once and
writes both snapshot sets: the made look is the tree row and the state pin's base, and every probe writes a var on that same instance, redraws,
captures, writes the original back and checks the look returned (a type whose look does not return is listed as `look sweep IMPURE` in tests.log and
probes on fresh instances). The vars probed are narrowed to those a draw can read by `analyze look-keys` (`data/look-plan.tsv`: per type a key and a
probe list, `*` meaning unknown, scan everything). `dq_focused_test.sh` runs the pins as `DQ_LOOK_SHARDS` (default 4, `--look-shards=N`) worlds from the
one compiled `.dmb`, each probing every Nth type (`sweep_owns`), beside one world for any other selected tests; the summaries merge into one
`data/test-runs/<id>_focused.json`. Without `--full` only the unverified types (current key matches no row of `code/modules/unit_tests/snapshots/look_keys.txt`) are probed (no
unverified type: no world is booted); a passing run that covered both pins records the keys of the types it probed (and no others) in that file, so commit it with the snapshots. `--full` probes everything
(merge worktree, nightly); `--repeat` runs the pins unsharded and full; `--bless` shards like a full run (`--look-shards=N`, one world per test-world slot by default): each world writes its own partial rows under `data/look-bless/<pid>/shard<i>/` (`look-bless-dir` world param) and `tools/dq_look_bless_merge.py` joins them, in typesof order, into the snapshot files after the worlds end, so the files are byte-identical to an unsharded bless (`--look-shards=1` still blesses in one world). A state pin only probes the types under a root it has a file for, and a probe whose own setter refuses the value (`set_x() given 1, not a ...`) writes no row; `tools/dq_pin.sh --look-state/--look-tree` records new pins with
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
| `cargo` | 1 | every cargo invocation of `build.ts` (analyze, verdigris, dmbc) | `DQ_SLOTS_CARGO` |
| `look_state_pin` | 2 | a `dq_focused_test.sh` run holding a look pin, for the whole run | `DQ_SLOTS_LOOK_STATE_PIN` (old name `DQ_LOOK_PIN_SLOTS`) |

`DQ_SLOTS=0` turns all of it off and a class at 0 is unlimited (except `merge_base`, the merge worktree lock of section 9: always exactly one slot). A waiter prints the class, its place in the queue and who holds the slots
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

**Split worlds record their own exit status.** `dq_focused_test.sh` once counted a fully green world as exit 127 (`wait` found no such child). Each world's subshell now writes its exit status to `data/focused-runs/split.<pid>.N.log.rc`; that record is the verdict, `wait` only reaps, a disagreement is printed, and a world with no record and no child counts as failed (125). An unclean run keeps its `split.<pid>.N.log` files and records (pruned after two days). The root cause of the lost child was not reproduced in isolation. `bash tools/ci/test_focused_world_status.sh` covers the new logic. `bash tools/ci/test_lane_check_docs.sh` builds a scratch repo and shows a stamp kept on a changelog/doc-only master move and invalidated on a code move or a read doc.

**Stamps and docs.** `tools/dq_lane_check.sh` ignores master changes under `html/changelogs/`, `doc/`, `data/bench/` (the only committed `data/` files, bench output nothing reads) and root `*.md` unless the file is listed in `tools/ci/lane_ready_doc_reads.txt` (docs a tool reads); the verdict names the files that decided it.

**Run copies of the world are per process.** `runIsolatedTestWorld()` copies the compiled `.dmb`/`.rsc` to `<base>.runN.p<pid>.*`. The slot-only name (`...test.run2.dmb`) was reused, and the cleanup gives up after 5 s and leaves a file behind when something still holds it (the previous world's DreamDaemon closing its handles, or a scanner); the next occupant's `copyFileSync` onto that file then failed with `EBUSY` (the lost look-pin shard). A name no earlier process used cannot be held, leftovers of dead processes are pruned at the next run, and one that stays locked is logged with its error code. The exact holder was not captured (the failing run's files were gone), so this fixes the collision, not a proven holder; no retry was added. `bun test tools/build/lib/run_copies.test.ts` covers the naming and the pruning.

**Re-proof (a stale stamp is proved again on the merged tree).** A lane or batch gated for 25-40 minutes can have master change a global path (`tools/analyze/`, the build) or one of its files meanwhile; the push then found the stamp stale and refused, and the retry raced the same way. Now `dq_push_master.sh` checks the stamp right after its merge and, when it is missing but `tools/dq_reproof_source.sh` says the merge joins master with one unpushed parent whose passing stamp sits on exactly that tip (a lane-ready note with `branch_commit` == the tip, or a merge-gates note with `commit` == the tip; so the lane's own commits are unchanged), it runs `dq_merge_gates.sh --reproof`: the parent's full stamped test list on the merged tree, plus the usual compile, DreamChecker and ratchets. That run stamps the merged HEAD with a merge-gates note carrying `tests`, `reproof_of` (the stamped parent) and `reproof_reason` (the lane check's verdict), the gate log prints `== re-proof: ...` with the reason, and `data/merge-gates/<sha>.ok` has `reproof_of=`/`reproof_reason=`. The push then accepts the HEAD. A lane with commits after its stamp has no note on its tip and is still refused (it needs `dq_lane_ready.sh`); `DQ_PUSH_NO_REPROOF=1` turns the automatic re-proof off. `bash tools/ci/test_reproof.sh` covers the eligibility rule; the gates run themselves need a test world and are not in that test.

**Test names are checked first.** `dq_lane_ready.sh --tests` and `dq_focused_test.sh` check every name and glob against the `/datum/unit_test` types the build compiles before anything is merged, generated or compiled, report all the misses at once, and print close matches (a missing `dq_eg2/` prefix, a one-letter typo, a glob that matches nothing). `bash tools/dq_focused_test.sh --list '*word*'` searches the declared types without compiling.

```sh
bash tools/dq_lane_ready.sh --tests "dq_my_test dq_my_other/*"      # [--covers 'code/game/machinery/**'] [--no-pins] [--no-merge]
```

The gates can move `HEAD` while they run (they normalize `look_keys.txt`, amend ratchet-baseline shrinks into the unpushed merge commit and record probed look keys),
and the proof is named by the `HEAD` they end on. The wrapper follows that move before it looks for `data/merge-gates/<sha12>.ok`; if no proof matches, the error prints
the expected file and the sha it found. `tools/ci/test_lane_ready_evidence.sh` covers it.

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

## 13. Op pins are factored (October 2026, `tooling-fix`)

The op snapshot pins (`code/modules/unit_tests/snapshots/{pins,i7_*,*_1008}/`) no longer repeat inherited rows: a type file
names a block in `snapshots/op_bases/<base type>.txt` per `actor|held item` group and writes only its delta (`@obj.item human|none`,
`-menu: X`, `+2 menu: Y`). Comparison is the same (the file expands to exactly the old rows); a mismatch prints each differing row
once with the types it differs for. Details: `doc/rewrite/snapshot_pins.md` "Factored op pins".

**Re-blessing in the new format.** Nothing changes in the command: `bash tools/dq_focused_test.sh --bless <test>` writes plain rows and
then runs `python3 tools/dq_pin_factor.py`, which factors them; commit the pin files and `op_bases/` together. A branch that blessed pins in
the old format still passes (plain rows are read as before); run `python3 tools/dq_pin_factor.py` once to factor them before the lane-ready
run. On a merge conflict in a pin file, take master's file (`git show origin/master:<path> > <path>`, never checkout) and re-bless the type; never hand-merge the `@`/`-`/`+` lines.

## 14. The push gate needs a test stamp (October 2026, `tooling-fix`)

`tools/dq_push_master.sh` and `tools/hooks/pre-push` refuse a push unless the pushed commit carries a passing test stamp, checked by
`bash tools/dq_push_stamp.sh <commit>` (prints `STAMPED: ...` or `UNSTAMPED: ...`). A commit passes when:

- it carries a lane-ready note (`refs/notes/lane-ready`, written by `dq_lane_ready.sh`) or a merge-gates note (`refs/notes/merge-gates`,
  written by `dq_merge_gates.sh` when its test world ran) on exactly that commit, with `"ok":true`;
- it is already in `origin/master`;
- it is a merge of master into one stamped parent and **the stamp carries across the re-merge**: (a) the merge is clean (`git merge-tree`
  of the two parents has no conflict outside the regenerated files, `look_keys.txt` and `snapshots/op_bases/`, which `dq_merge_master.sh`
  regenerates after the merge, and the merge commit's tree is that result, regenerated files aside; `bash tools/ci/test_push_stamp.sh`
  checks this in a scratch repository); (b) what master changed since
  the stamp's master base is disjoint from what the stamp depends on, judged by `tools/dq_lane_check.js --master <master parent>`: the
  lane's files and their directories, the files defining its tests, the snapshot directories those read
  (`code/modules/unit_tests/snapshots/<dir>/`), its `--covers` globs and `tools/ci/lane_ready_global.txt`; `look_keys.txt` and
  `snapshots/op_bases/` are regenerated, so an overlap there does not count (a merge-batch stamp needs master's changes disjoint from the
  batch's files, directories and the global paths); (c) the compile, DreamChecker and the ratchets pass on the merged tree, which
  `dq_push_master.sh` runs on exactly that commit before pushing. A lane whose push races other pushes no longer re-gates: it re-merges
  and pushes on its old stamp while master's changes stay out of its way. Otherwise the message says what overlapped; run
  `dq_lane_ready.sh` again;
- it has one parent that passes and changes only docs, changelogs, `*.md`, `tools/ci/known_failures.txt` or the look keys (what
  `dq_lane_ready.sh` allows after a stamp, and the data-only commits the push script adds).

A stamp is ok when nothing failed that `tools/ci/known_failures.txt` does not list: the gates now record `new_failed=` beside `failed=`, the
lane-ready note carries both, and `dq_lane_check.sh` judges `new_failed`. `dq_merge_gates.sh --no-tests` writes no stamp. The hook runs the
checker from the pushing worktree, so a worktree that predates it pushes as before; reinstall the hook after merging
(`cp tools/hooks/pre-push "$(git rev-parse --git-common-dir)/hooks/pre-push"`).

## 15. Ratchet lints on the typed tree (October 2026, `tooling-fix`)

`silicon_entry`, `init`, `decl`, `base_vars` and `requirement_bool` now find their sites on the analyzer's semantic model
(`tools/analyze/src/sem/actor_tests.rs`, `sem/procs.rs`) instead of by header text. What changes for you:

- **Actor tests reachable from an op handler.** `handler_actor_check` (an op handler spelling `isAI`/`issilicon`/`isrobot`/`ispAI`) is
  still banned; `handler_actor_istype` (a literal `istype(A.actor, /mob/living/silicon...)`, or on a local holding the actor) and
  `helper_actor_check` (the same test in any proc the handler hands the actor or the act to, up to 8 calls deep) are ratchets from the
  15 and 89 sites that existed. A helper that branches on the caller's kind is the site: pass what the op knows (`A.authority`, the
  provider) or split the op with `when(req(T, of = ON_ACTOR))`.
- **Better matching, same baselines.** A definition written in a nested block or by a macro, a macro-declared var on a base type
  (`EXPIRY_DECLARE`, `VAR_PRIVATE`), a body line after a column-0 comment and a `req_bool()` inside a macro all count now. The
  pre-existing ones were added once (base_vars +33, decl +1; init dropped a commented-out header). Baselines stay shrink-only.
- Line numbers are the engine's (universal newlines): `sem::procs::engine_line()` maps the parser's numbering, which differs after a
  lone carriage return.
- When the model cannot be built the lints fall back to the old text rules, so a parse failure never passes a site silently.

## 16. Constructor arguments are checked (October 2026, `tooling-fix`)

The `lifeforms` lint now judges positional constructors on the typed tree (`tools/analyze/src/sem/ctor_args.rs`; final_api section 6,
"param() and make()"):

- `ctor_dead_arg`: `new /T(loc, x, ...)` (or `var/T/v = new(loc, x, ...)`) where no `param(..., pos = N)` of `/T` takes position N and no
  `New()`/`Initialize()` of `/T` or an ancestor reads it. Drop the argument, or declare the param it was meant for. A literal `null` is no
  argument.
- `ctor_forward_only`: an override whose trailing extra parameters only reach `..()`; drop them (`..()` passes the caller's arguments).
- `param_pos_override`: a subtype's `param(..., pos = N)` that takes over a position an ancestor maps needs `overrides = TRUE`
  (`param_overrides_nothing` rejects one that overrides nothing).

All four are hard errors. `python3 tools/dx/codemods/ctor_args.py --apply` rewrites the sites the lint reports (dead trailing arguments
removed, a dead one before a live one written `null`, forward-only parameters dropped with an exact `..(params)` becoming `..()`, and
`overrides = TRUE` added); anything it cannot do exactly it prints as residue. The first run removed 22 dead arguments, 37 forward-only
parameter lists and marked 33 position takeovers.

## 17. Tests write tracked state through setters too (October 2026, `tooling-fix`)

A test that writes a tracked var raw (`A.equipment = POWERCHAN_ON_AUTO` on the map's APC) changes shared state with no
`state_changed()` mark, and a later test's refresh sweep reports `REFRESH DRIFT` on it, far from the cause (it took the grid tests
followed by the lights tests to show). The `tracked` lint exempts the test trees, so a second lint, `tracked_tests`, reads
`code/modules/unit_tests/`, `code/modules/benchmarks/` and `code/tests/` for the same writes: `TRACKED`/`SETTER` vars, `derive()`
values and, here only, the vars a non-virtual `STAT()` composes. It is shrink-only over `tools/ci/tracked_tests_baseline.txt`
(225 sites when it landed; the 43 cheap ones, APC channels/charging/status and cell charge, now use `set_x()`). In a test write
`A.set_x(v)`, or `set_var()` when the test must put the value back. A drift report now also prints where the drawn look key and the
current one part, which names the part that moved.

## 18. Interrupted lane-ready runs never stamp

Lane-ready requires the gate result for its exact tested commit, the production compile/DreamChecker, analyzer and ratchet markers, and a test-result JSON whose counts match the gate. An interrupted run or missing evidence is refused. The controlled wrapper regression is `bash tools/ci/test_lane_ready_evidence.sh`; it runs no compiler or DM world. DM selectors passed to the note writer retain their literal paths on Windows.

After diagnosing a wrapper-only failure following successful gates, `dq_lane_ready.sh --reuse-gates --tests-file <list>` may finish stamping the unchanged clean commit. It validates the real `sha=` gate format, compile/analyzer/ratchet markers, matching runtime JSON commit and counts, and that every requested selector was already tested. It performs no merge, compile or test run; changed source needs fresh gates. The controlled evidence regression checks missing, incomplete, inconsistent and wrong-commit evidence, and refuses untested selectors during reuse.

Serialized focused runs keep the incremental look plan: DQ_FOCUS_SPLIT=0 launches one combined world with the main selectors and both look pins. It forwards the prepared look parameters and records keys only after success. This avoids an accidental full appearance sweep when parallel worlds are disabled. The pure-shell regression is tools/ci/test_focused_look_single.sh.

## 19. Lanes lease worktrees from a pool (October 2026, `tools/workflow-streamline`)

A lane no longer creates and deletes a worktree. `tools/dq_lane_pool.sh` (also `tools/dq_worktree.sh lease|release|pool`) manages
`DQ_LANE_POOL_SIZE` (default 3) permanent worktrees, `E:/projects/dq-wt/pool-N`:

```sh
WT="$(bash tools/dq_worktree.sh lease rewrite/my-lane)"   # prints the path; the lane runs there
cd "$WT"  ...  bash tools/dq_lane_ready.sh --tests "..."
bash tools/dq_worktree.sh release rewrite/my-lane           # after the lane is merged (or to park it; the branch is kept)
bash tools/dq_worktree.sh pool                               # who holds what
```

- **Cap.** At most 3 lanes at once. A 4th `lease` exits 3 with `POOL FULL`, naming the holders. A lease whose lane is finished
  (its commits are all in origin/master, the tree is clean) is reclaimed by the next `lease`, so a forgotten `release` never blocks it.
- **Start.** The slot's first lease checks it out once (about 3 minutes, on `git worktree add --detach`); every later lease is a
  `git switch -c <branch> origin/master` of a few seconds. A dirty slot is skipped and named, never cleaned. A branch that already holds
  commits is resumed (`git switch`), a merged one restarted (`git switch -C`, which loses nothing). No checkout, reset, restore, stash or
  cherry-pick, and no discard flag.
- **Release.** Refuses a dirty tree. Retires the slot's dmbc daemon (about 8 GB of RAM), deletes its build outputs
  (`deepquarry.*` .dmb/.rsc/logs, `.dmbc`, `tools/dmb/target`, `verdigris/target`, everything under `data/` except `data/analyze-cache`),
  moves the slot to a detached `origin/master` and deletes the lane branch if it is fully merged. **Kept warm:** `icons/gen` (the seed),
  `node_modules` links, `tools/analyze/target` (the analyzer binary), `data/analyze-cache`. `--keep-outputs` skips the deletion.
- **`dq_worktree.sh gc`** never removes a pool slot, `play`, `merge-base`, a detached-HEAD worktree, a name in `DQ_WT_KEEP` or in
  `E:/dq-cache/worktree-keep.txt`, or a worktree a process names on its command line or wrote to in the last 20 minutes.
- **Waiting for a slot.** `bash tools/dq_lane_pool.sh lease <branch> --wait [--timeout MIN]` (default 240) queues instead of failing
  when the pool is full: first come first served, one waiting process per lane, a dead waiter drops out on its own, `status` lists
  the queue. Run it once in the background and act when it exits. Never write your own retry or `until` loop around `lease`.
- **Reclaim.** A lease whose branch is fully in `origin/master` is reclaimed only after `DQ_LANE_POOL_RECLAIM_IDLE_MIN` (180) minutes
  with no change to the lease, the worktree's HEAD or its index, so a lane that lands several merges keeps its slot between them.
- `dq_lane_ready.sh` warns outside a pool worktree (`DQ_LANE_POOL_STRICT=1` refuses). Self-test: `bash tools/ci/test_lane_pool.sh`.
- The `reference-transaction` hook (`tools/hooks/reference-transaction`) now allows the update when the checkout's
  `dq_machine_slots.sh` has no `merge_lock_require` (a stale main checkout running `git gc` used to fail every ref update). Reinstall it
  once with `bash tools/hooks/install_pre_push.sh`; the installer now replaces an older copy.

## 20. A lane proves itself once, by tree hash

`dq_merge_gates.sh` stores what a fully passing run proved under the **tree** hash of the commit it ran on (`tools/dq_proof_cache.sh`,
`E:/dq-cache/tree-proofs/<tree>.proof`: the master it ran against, the test selectors, counts, whether the production compile + DreamChecker,
tgui lint and the analyzer's cargo tests ran). `dq_lane_ready.sh` aliases the proof to the tree of its final commit (the look-key record
it commits after the pins), so the lane's tip is covered.

When the merge agent merges the lane and master has **not moved** since, `git merge --no-ff` produces exactly the lane's tree. The gates find
the proof, print `proof reused`, skip gen/compile/test world/ratchets and write the `<sha>.{ok,dm.ok,ratchets.ok,analyze.ok}` stamps and
the merge-gates note for the merge commit; `dq_push_master.sh` then skips its checks on that stamp as before. When master **moved**, the merged tree
is new, no proof matches and the gates prove the combination: smoke set + the tests of any lane whose stamp is invalid, the compile and
the ratchets. A proof only covers a test list it contains (a subset is fine, a missing selector is not). `DQ_PROOF_REUSE=0` forces a full run.

## 21. Batched merges

```sh
export DQ_MERGE_SESSION=<your lane>
WT="$(bash tools/dq_merge_worktree.sh --lanes "a b c")"; cd "$WT"
bash tools/dq_merge_gates.sh --lanes a,b,c          # merges all three, one combined gate run; same as tools/dq_merge_batch.sh
bash tools/dq_push_master.sh --expect "a b c"
```

`--lanes` naming lanes that are not in HEAD hands over to `tools/dq_merge_batch.sh`: it merges them in order on a detached HEAD, runs
`dq_merge_gates.sh` once (one gen, one build, one union of tests, **one** look-key normalization and record, committed into the batch's
last merge commit instead of one per merge), and on failure bisects by lane: the smallest failing prefix names the bad lane, only that lane is
bounced (named with its attempt log under `data/merge-batch/`), and the rest is proved again; every attempt whose tree was proved is answered
from the proof cache. A lane that conflicts is bounced at once. `rewrite/integ-current` moves only to a proved tip (`git switch -C` from a
clean detached tree). Exit 0 all merged, 1 some bounced. Self-test (stub gates): `bash tools/ci/test_merge_batch.sh`.

## 22. Look pins: incremental by key and by manifest

Incremental look pins were already keyed by `analyze look-keys` against the committed `look_keys.txt`. What is added:

- A machine-wide **manifest** (`E:/dq-cache/look-manifest/<digest>.tsv`, `tools/ci/check_look_keys_format.sh`): every (type, key) a passing
  run verified, named by the content hash of the look snapshots (`look_states`, `look_trees`, `looks`) and the two sweep files. A lane does not
  re-probe a pair another worktree already proved; any change to a snapshot or the sweep starts an empty manifest (that is what keeps it
  sound). `DQ_LOOK_MANIFEST=off` disables it.
- `--full` shards over the `test_world` slot count instead of 4 (`--look-shards=N` / `DQ_LOOK_SHARDS` still win).
- `tools/dq_look_prove.sh`: the equivalence proof on a sample (see section 24 for what it showed and what a full sweep costs).

## 23. Shared build outputs

The analyzer binary was already cached by source hash in `E:/dq-cache/analyze-bin` and restored (a 15 MB copy, no cargo) on a miss in the
worktree's target; what had never been done is pruning it (420 entries, 6.3 GB). `bash tools/dq_cache_prune.sh` keeps the newest 12 and every key a live
worktree was built from, plus tree proofs (200) and look manifests (6). `icons/gen` stays in the pool slots, so a lease repacks nothing.

## 24. Measurements (16 October 2026, `tools/workflow-streamline`)

| What | Before | After |
|---|---|---|
| Disk of a finished lane | 1.5-2.3 GB each, kept until someone removes the worktree (`.dmb`/`.rsc` 300 MB, logs up to 520 MB, `.dmbc` 64 MB, `data/` 300 MB, `icons/gen` 380 MB) | pool slots are permanent; a released slot keeps `icons/gen` + `data/analyze-cache` (about 0.5 GB) and drops the rest; 3 lanes cap the total |
| Fresh worktree | `git worktree add` of 29k files: 6 min 36 s under load (about 30 s on a quiet disk), then cold icons/analyzer/compile caches | first lease of a slot is the same one-time checkout; every later lease is a `git switch -c` |
| `analyze-bin` cache | 6.4 GB, 482 entries | 211 MB, 12 entries (`tools/dq_cache_prune.sh`) |
| Lane done to on master (tools/docs lane, valid stamp, master unmoved) | gates 506 s + push checks 4 min (disk-hygiene merge) | the tree proof answers the gates (section 20); the push skips on the stamp |
| Look pins | 4359 of 21045 types unverified on master; the 4-world full run was watchdog-killed at 46 min with about 100 of 2108 types per world done | a tools/docs-only diff skips them (`dq_diff_touches_dm`); the manifest spares re-probing pairs another worktree proved |

**What a full look sweep costs.** The sweep covers 8429 creatable types; worlds spend 2-4 s per type on average and 17-100 s on each
`/mob/living` type (`dq_look_settle()` drives the kernel's D phase several times per type, and simple mobs and robots run their AI there).
At 5 worlds that is about 1.4 hours at best, so a full run cannot be brought under 10 minutes by sharding alone; the per-type settle cost
for mobs is the lever. `--full` is still sharded over every `test_world` slot, and an incremental run only pays for what moved.

**Incremental equals full (sample proof, `tools/dq_look_prove.sh --stride 40`).** A reverse-order run over 526 types (every 40th of the
plan) and a shuffled run over a 263-type subset of them wrote 2257 rows in the subset run; every one is byte-identical to the larger run's
row (`comm -23` empty over 431 files): a type's rows do not depend on which other types a run probes. Both runs also showed 14 and 6
committed snapshot rows that no longer match the render on master (a finding about the tree, not the incremental path): master's look
snapshots need a bless, which today is an unsharded full run (hours) because shards cannot write the same root file.

## 25. Fast, reliable gates (17 October 2026, `tools/gate-speed`)

**Land with `tools/dq_land.sh`: prove outside the lock, lock only to merge and push.**

```sh
export DQ_MERGE_SESSION=<your lane branch>
bash tools/dq_land.sh --tests "dq_my_test dq_my_other/*" [--covers GLOB] [--no-pins] [--rounds N] [--dry-run]   # from the lane's worktree
```

A gate run inside the merge lock took 3-10+ minutes and everyone queued behind it. The proof is stored under the tree hash (section 20), so it
can be made before the lock: `dq_land.sh` asks `git merge-tree` what tree merging the lane into `origin/master` would give and whether that
tree already has a covering proof (`proof_covers_merge`). If not, it runs `dq_lane_ready.sh --lite` (no lock held; other lanes land
meanwhile). Only then does it take the merge lock, and only for the fast part: merge, `dq_merge_gates.sh` (answers from the proof: no compile, no
test world), `dq_push_master.sh` (which still verifies master did not move and that the lane landed). If master moved while the lock was queued, the lock is
given back at once (the worktree reset to `origin/master`) and the lane is proved again, up to `--rounds` (default 3); the last round
proves and lands under the lock as before, so a busy master delays a lane but never starves it. `bash tools/ci/test_land.sh` covers the loop.

**Lite re-proof (`dq_lane_ready.sh --lite`, `dq_lane_check.js --lite`).** When master moved under a stamped lane but changed none of what the stamp depends
on (the lane check says VALID), and `origin/master`'s own tree carries a passing proof of the smoke set, the gates run the boot gate, the lane's
stamped tests, the gameplay scenarios and the tests of the lanes that landed on master since (their stamps), not the rest of the smoke set. The
compile, DreamChecker and ratchets still run on the merged tree. The proof records `inherits=<master's tree>`; `proof_find` counts that proof's
selectors as covered while it is itself clean (`dm=1`, `new_failed=0`). `bash tools/ci/test_lane_lite.sh`.

**A gate flake costs one isolated rerun, not a batch.** `dq_merge_gates.sh` runs its test job through `tools/dq_gate_retry.sh`: when tests failed, only
those run again once in a fresh world (`--force`); if they pass the job passes and each test is recorded in the machine flake ledger
(`E:/dq-cache/flakes.tsv`; `bash tools/dq_flake_log.sh [N|--count]`; the `.ok` record has `flakes=`; the log has `GATE FLAKE:` lines). Every test in the
`--count` list needs a fix lane. A test that fails twice is a failure. A world that produced no result ("Native executable changed during compilation", "daemon
startup deadline", watchdog) reruns the whole list once and is ledgered as `infra`. `DQ_GATE_RETRY=0` turns it off. `bash tools/ci/test_gate_retry.sh`.

**The shared compiler binary is immutable per version.** `E:/dq-cache/dmb-bin/v/<id>/{dmbc,dmbd}.exe` (`<id>` the content hash of the pair), `dmb-bin/current` names the
version a new compile uses, a process resolves it once and keeps it (`tools/build/lib/dmbc_cache.ts`). Publishing writes a new version directory and swaps the
pointer atomically; it never touches a version a running compile or daemon holds, so a republish mid-gate cannot produce "Native executable changed during
compilation". Old versions are pruned (the current and the 3 newest others stay). A bin dir with no `current` is the old layout, still honoured.

**`no method named evict_to_budget` (dmbc build).** The method exists in `tools/dmb/crates/dm-cache/src/store_budget.rs` and the call in `dmbc/src/daemon/cache_gc.rs`; the
error came from the one shared cargo target (`E:/dq-cache/dmb-build`) holding stale artifacts of another revision of the path crates (each worktree is a different
path, but pool slots reuse a path across revisions and the target is incremental). It was not reproducible from source. `DmbcTarget` now treats a build that fails with
that signature (E0599/E0432/E0433/E0425, an ICE, an incremental-cache error) as stale state: it removes `release/incremental`, runs `cargo clean --release` for the
workspace crates and builds once more with `CARGO_INCREMENTAL=0`. A real compile error fails twice and is reported.

**A test-world slot is kept free for the merge worktree.** With 3 or more `test_world` slots, other worktrees may hold only all but one
(`DQ_SLOTS_MERGE_RESERVE`, `DQ_SLOTS_MERGE_RESERVE_<CLASS>`; the merge worktree already went first in the queue but could still wait for a long run to finish).

**Measurements (17 October 2026, real landings of this lane on a machine with 5 lanes active).**

| What | Before | After |
|---|---|---|
| Merge lock held per lane | the whole gate run: 260-1109 s on 12 recent gate runs (`data/merge-gates/*.timings`), plus queue waits up to 4.5 h behind it | landing 1: 113 s, landing 2: 120 s, of which merge 3 s, gates 36-39 s, push 65 s (about 30 s of that was the disk cleanup, now after the release); with the early-proof path, the no-fork test-list read and the skipped second merge: see the landing-3 line below |
| Gate steps before the proof lookup | `proof_covers`-style test list: 10.8 s of forks (an `xargs` per smoke line) | 0.9 s (`proof_smoke_tests`, the gates' list read) |
| Gate run proving a lane (outside the lock) | 6-10+ min, redone in the lock when master moved | landing 1: proof 557 s (47 tests), master moved, re-proof (lite: 15 tests) 516 s; the wall time is dominated by queues for the test compile root (171 s) and test-world slots on a loaded machine, not by the tests |
| Master moves while the lock is queued | the lane waits, then gates for 3-10 min under the lock | the lock is given back at once (observed, landing 2: 43 s queued), the lane is re-proved outside the lock |
| A flaky test in the gate | the whole batch fails; rerun costs a full gate | one isolated rerun (seconds); ledgered |

What is still slow and is not fixed here: the test compile of a cold tree takes the one machine-wide `dmb_root_deepquarry.test` compile-root slot (waits of 171 s
seen) and the test worlds queue for `test_world` slots; those are the load of five lanes sharing one machine, and a lane proof (outside the lock) absorbs them
instead of the merge. The production compile (`dm` job, 200-330 s) and the test job overlap, so a proof's wall time is the longer of the two.

## 26. Batch landing by one lander (17 October 2026)

Lanes no longer push. A finished lane commits everything on its branch, runs its own focused tests (and `dq_lane_ready.sh` if it
wants a stamp; it no longer has to), and sends the main session `READY <branch> <worktree> [<sha>] — <summary>; tests: <names>`. The
main session forwards it to the batch lander, the only agent that runs `dq_push_master.sh`.

The lander, per batch:

1. `export DQ_MERGE_SESSION=batch-lander`; `WT="$(bash tools/dq_merge_worktree.sh --lanes "<branches>")"` (the lock and
   `E:/projects/dq-wt/merge-base` moved to origin/master). If the worktree holds an unpushed batch from an interrupted push, adopt it
   (`--adopt --lanes <branch>`, every named lane must be in HEAD; name a commit with `git branch batch/<name> <sha>` when the lane's
   tip moved on past what was merged), then `--join` the new lanes.
2. In `$WT`: `git merge --no-ff --no-edit <branch or sha>` for each READY lane, the sha the lane reported (a lane that committed
   more since is not taken past what it said is ready). Resolve conflicts as usual; two lanes carrying the same fix keep one.
3. One gate for the whole batch: `bash tools/dq_merge_gates.sh --lanes "<the merged shas>" --tests "<every lane's focused tests>"`.
   Name the exact commits you merged, not branch names: a lane named by branch whose tip moved past what you merged is not "in HEAD",
   so the gates hand the batch to `dq_merge_batch.sh`, which starts again from origin/master with every branch tip and bounces any
   lane that conflicts, discarding the conflicts you resolved by hand (seen 2026-10-18).
   Look pins run only when the batch touches DM, map, icon, sound, skin or analyzer files.
4. Green: `bash tools/dq_push_master.sh`. With one pusher master does not move under the gate, so the push honors the gate's stamp
   on the exact HEAD and repeats nothing.
5. Red: bisect the batch. Re-take the worktree with the lanes minus half, gate, and repeat until the breaking lane is found
   (`dq_known_failures.sh --check` first separates known and flaky failures). Land the rest, and report the breaking lane to the
   main session with the failing test and its log path.

**The session across shell calls.** Each agent shell call starts a fresh environment, so an `export DQ_MERGE_SESSION=...` from the
call that took the lock is gone in the next one. When the batch starts, `dq_merge_worktree.sh` writes the holder's session and holder pid to
`dq-merge-session` in the merge worktree's git dir. The reference-transaction hook accepts a plain `git merge` / `git commit` there with no
`DQ_MERGE_SESSION` when that record names the live holder (`merge_lock_require_ref`). A record left by a released or dead lock is void, and
an explicit `DQ_MERGE_SESSION` of another lane is still refused. The merge scripts (`dq_merge_gates.sh`, `dq_push_master.sh`) still need
the explicit session, so set it in every call that runs them (the simplest way is one shell call per step: commit, gates, push).
`bash tools/ci/test_merge_lock.sh` section 15 covers this. Before this fix, a merge whose commit the hook refused was left half-done
(MERGE_HEAD set; seen on three lanes, 2026-10-19).

Polling: wait on a result line with an `until` loop whose timeout is at most 120 s, or run the step with `run_in_background` and
wait for the notification; never block 10 minutes at a time.

The merge worktree compiles in its own compile root (`E:/dq-cache/dmb-roots/deepquarry-merge`, `compile_root.ts rootKeyFor`): every
gate there is master plus a batch, so its daemon session patches from the previous gate's tree instead of waiting behind lanes in the
shared root and recompiling their trees (measured: a gate's test compile waited 315 s for the shared root, then ran a full compile).

## 19. DreamMaker still has to accept the tree (October 2026, `tools/dmb-behaviour`)

The native compiler is the default, so for a while nothing noticed that master no longer compiled with DreamMaker (105 errors:
`to` used as a named argument and formal, 99 subtype overrides written `/T/proc/name()` where the parent already declares the
proc, and `nameof(call().var)`). Two guards now stop that:

- `dmbc` reports the same errors as DreamMaker for those classes (`fixtures/diagnostics/cases/keyword_*`, `inherited_proc_*`,
  `inherited_verb_*`, `nameof_call_expression`). In DM an override is written without `proc/` or `verb/`; with the keyword it is a
  `duplicate definition` of the nearest ancestor's declaration. `to` and `in` cannot be argument names; `if`, `set`, `while` and the
  like cannot be formal names; a `nameof` operand is a reference path, not a call or index.
- `tools/dq_merge_gates.sh` and `tools/dq_push_master.sh` compile the production dme with `DQ_COMPILER=dreammaker` after the native
  compile (about 3 minutes, overlapped with the test world). `DQ_DREAMMAKER_GATE=0` skips it for a local experiment; the push
  refuses a tree DreamMaker rejects. Check a new class locally with
  `python tools/dmb/scripts/diagnostics_corpus.py record --dm <dm.exe> <case>` then `check --dmbc tools/dmb/target/release/dmbc.exe`.
