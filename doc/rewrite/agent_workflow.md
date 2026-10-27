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

It fetches, merges `origin/master` (`--no-commit`), resolves the modify/delete conflicts on the generated files as
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
(through `dq_merge_master.sh`), runs `build.sh dm` (DreamChecker must run and report 0 diagnostics, the compiler
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
tests in one world, which also leaves the compiled `.dmb` in the compile-hash cache), the production `build.sh dm` (native compile
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

**Merge-safe tooling.** `deepquarry.dme` and `_unit_tests.dm` merge by union (`.gitattributes`), so a plain `git merge --no-ff <lane>` in the merge worktree succeeds. A lane that still edits a deleted look-pin snapshot file (`look_keys.txt`, `looks/`, `look_states/`, `look_trees/`) conflicts with the deletion; `dq_merge_master.sh` takes the deletion. `dq_merge_gates.sh` records the tip of each `--lanes` branch and origin/master as the gates started (`lane_tips=`, `base_master=` in
`data/merge-gates/<sha>.ok`), refuses a lane that is not in HEAD, and shrinks the ratchet baselines (`analyze baseline --update`, never
adds) into the merge commit instead of a repair commit. `dq_push_master.sh` (`--expect "ref ..."` / `DQ_PUSH_EXPECT` add tips) refuses a
no-op push, refuses on `rewrite/integ-current` when origin/master moved since the gates (re-run them), and after the push fetches and
fails unless origin/master contains HEAD and every expected tip.

**No look pins.** The look pins (`dq_look_state_pin`, `dq_look_tree_pin`, `dq_look_pin`, the human and profile look hashes), `look_keys.txt`, `analyze look-keys` and the
`look_state_pin` machine slot were deleted on 2026-10-17 (they cost too much time per merge; playtesting finds visual issues). Snapshot look pins are never
re-added; behavioural tests stay (`dq_fresh_look_default`, `dq_human_draw_deterministic`, the staleness checker, the boot gate). Other slow tests
(`DQ_SLOW_TESTS`, none by default) go to a second world beside the main one, merged into one `data/test-runs/<id>_focused.json`; `--no-split-slow` /
`DQ_FOCUS_SPLIT=0` restores one world. The slow world's timeout defaults to 45 minutes (`DQ_FOCUS_TIMEOUT_MINUTES` overrides it). Worlds share no mutable
file: each takes its own run slot (`data/runs/runN`), port, log dir, spritesheet dir and results file, exactly as shards do. `--no-pins`, `--full`,
`--look-shards`, `--look-order` and `--look-dump` print a deprecation note and do nothing.

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
| `test_world` | a third of the CPUs, 2 to 6 (5 on 16) | each unit-test world's DreamDaemon launch (`runIsolatedTestWorld()` in `build.ts`: focused, split and sharded worlds) | `DQ_SLOTS_TEST_WORLD` |
| `cargo` | 1 | every cargo invocation of `build.ts` (analyze, verdigris, dmbc) | `DQ_SLOTS_CARGO` |

`DQ_SLOTS=0` turns all of it off and a class at 0 is unlimited (except `merge_base`, the merge worktree lock of section 9: always exactly one slot). A waiter prints the class, its place in the queue and who holds the slots
(`worktree 'label' pid, held Ns`) every 30 seconds. The merge worktree (`E:/projects/dq-wt/merge-base`, `DQ_MERGE_WT`) jumps the queue
(`DQ_SLOT_PRIORITY=0` does the same for another caller); within a priority it is arrival order, and a slot is taken only by the first in the queue.
A holder that crashes does not block anyone: a slot or queue entry whose pid is gone (the Windows pid of a node or bash holder), or whose heartbeat
(its `owner` file's mtime, touched every 15 s) is older than `DQ_SLOTS_STALE_SEC` (600), is removed by the next waiter. `dm_compile` and `cargo` are never held while waiting for another class, so they cannot deadlock.

**Fair order and the suite cap.** Queues are oldest first (priority 0, then arrival); only the head takes a slot. A group of test worlds from a
non-priority caller (full `dm-test`, many-world focused run) takes at most `DQ_SLOTS_SUITE_MAX_WORLDS` worlds: unset = 1 while another run is queued
when it asks (else all it wants), N = always N, 0 = off. The merge worktree and compiler lanes are exempt. It applies to new acquisitions only (nothing
held is preempted, so a suite that started on an empty queue keeps both worlds until a shard exits; the freed slot then goes to the oldest waiter). Shards
past the cap take their own slot in queue order. `dq_machine_slots.sh waiting|holding <worktree>` list a worktree's queue entries / slots; `stats` shows max wait.

A run that launches several worlds (a sharded `dm-test`, the main/slow/sweep worlds of `dq_focused_test.sh`) takes their `test_world` slots **as a
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
bash tools/dq_lane_ready.sh --tests "dq_my_test dq_my_other/*"      # [--covers 'code/game/machinery/**'] [--no-merge]
```

The gates can move `HEAD` while they run (they amend ratchet-baseline shrinks into the unpushed merge commit),
and the proof is named by the `HEAD` they end on. The wrapper follows that move before it looks for `data/merge-gates/<sha12>.ok`; if no proof matches, the error prints
the expected file and the sha it found. `tools/ci/test_lane_ready_evidence.sh` covers it.

It merges current `origin/master` (`dq_merge_master.sh`), runs `dq_merge_gates.sh` on the merge (gen; one test world with the cross-branch
smoke set and your tests; the production compile and DreamChecker; the ratchets), commits any snapshots the gates re-recorded, and writes the stamp: a git note on `HEAD` in `refs/notes/lane-ready` (JSON: the branch, the commit, the master commit it merged
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
  of the two parents has no conflict outside the regenerated files, `snapshots/op_bases/`, which `dq_merge_master.sh`
  regenerates after the merge, and the merge commit's tree is that result, regenerated files aside; `bash tools/ci/test_push_stamp.sh`
  checks this in a scratch repository); (b) what master changed since
  the stamp's master base is disjoint from what the stamp depends on, judged by `tools/dq_lane_check.js --master <master parent>`: the
  lane's files and their directories, the files defining its tests, the snapshot directories those read
  (`code/modules/unit_tests/snapshots/<dir>/`), its `--covers` globs and `tools/ci/lane_ready_global.txt`;
  `snapshots/op_bases/` is regenerated, so an overlap there does not count (a merge-batch stamp needs master's changes disjoint from the
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
- **Stuck and idle leases.** A lease is STUCK when no live process uses its worktree (no command line naming the path, no machine slot held or
  queued for it) and nothing in it changed for `DQ_LANE_POOL_STUCK_MIN` (30) minutes (lease file, HEAD, index, reflog, modified or untracked
  files, `data/logs`, `data/runs`, root `*.log`). `status` tags every lease `active`, `idle Nm` or `STUCK: ... DIRTY|clean, UNPUSHED|nothing unpushed`,
  and `WAITING for machine slot: test_world 12m` when the worktree is queued for a `dm_compile`/`test_world` slot while holding its pool slot.
  `bash tools/dq_lane_pool.sh stuck [--quiet]` lists stuck leases and exits 1 when there are any (poll it); each also gets a notice file
  `E:/dq-cache/lane-pool/notices/pool-N.stuck`. A dirty tree or unpushed commits are only reported, never wiped. A stuck lease that is clean with
  every commit in origin/master or origin/<branch> is reclaimed by the next lease after the reclaim limit. Why the old reclaim missed a dead
  dirty lane (init/sweep-5, 15 h): it skipped every dirty tree and reclaimed only a merged, committed lane.
- **Cancel.** `bash tools/dq_lane_pool.sh cancel <branch>` removes that branch's queue ticket; the waiting `lease --wait` exits 4 ("cancelled"). Nothing is killed.
- `dq_lane_ready.sh` warns outside a pool worktree (`DQ_LANE_POOL_STRICT=1` refuses). Self-test: `bash tools/ci/test_lane_pool.sh`.
- The `reference-transaction` hook (`tools/hooks/reference-transaction`) now allows the update when the checkout's
  `dq_machine_slots.sh` has no `merge_lock_require` (a stale main checkout running `git gc` used to fail every ref update). Reinstall it
  once with `bash tools/hooks/install_pre_push.sh`; the installer now replaces an older copy.

## 20. A lane proves itself once, by tree hash

`dq_merge_gates.sh` stores what a fully passing run proved under the **tree** hash of the commit it ran on (`tools/dq_proof_cache.sh`,
`E:/dq-cache/tree-proofs/<tree>.proof`: the master it ran against, the test selectors, counts, whether the production compile + DreamChecker,
tgui lint and the analyzer's cargo tests ran). `dq_lane_ready.sh` aliases the proof to the tree of its final commit (the snapshot record
it commits), so the lane's tip is covered.

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
`dq_merge_gates.sh` once (one gen, one build, one union of tests, the ratchet-baseline shrink committed into the batch's
last merge commit instead of one per merge), and on failure bisects by lane: the smallest failing prefix names the bad lane, only that lane is
bounced (named with its attempt log under `data/merge-batch/`), and the rest is proved again; every attempt whose tree was proved is answered
from the proof cache. A lane that conflicts is bounced at once. `rewrite/integ-current` moves only to a proved tip (`git switch -C` from a
clean detached tree). Exit 0 all merged, 1 some bounced. Self-test (stub gates): `bash tools/ci/test_merge_batch.sh`.

## 22. Look pins (deleted)

The incremental look pins, their manifest and `tools/dq_look_prove.sh` were deleted on 2026-10-17 (see section 9).

## 23. Shared build outputs

The analyzer binary was already cached by source hash in `E:/dq-cache/analyze-bin` and restored (a 15 MB copy, no cargo) on a miss in the
worktree's target; what had never been done is pruning it (420 entries, 6.3 GB). `bash tools/dq_cache_prune.sh` keeps the newest 12 and every key a live
worktree was built from, plus tree proofs (200). `icons/gen` stays in the pool slots, so a lease repacks nothing.

## 24. Measurements (16 October 2026, `tools/workflow-streamline`)

| What | Before | After |
|---|---|---|
| Disk of a finished lane | 1.5-2.3 GB each, kept until someone removes the worktree (`.dmb`/`.rsc` 300 MB, logs up to 520 MB, `.dmbc` 64 MB, `data/` 300 MB, `icons/gen` 380 MB) | pool slots are permanent; a released slot keeps `icons/gen` + `data/analyze-cache` (about 0.5 GB) and drops the rest; 3 lanes cap the total |
| Fresh worktree | `git worktree add` of 29k files: 6 min 36 s under load (about 30 s on a quiet disk), then cold icons/analyzer/compile caches | first lease of a slot is the same one-time checkout; every later lease is a `git switch -c` |
| `analyze-bin` cache | 6.4 GB, 482 entries | 211 MB, 12 entries (`tools/dq_cache_prune.sh`) |
| Lane done to on master (tools/docs lane, valid stamp, master unmoved) | gates 506 s + push checks 4 min (disk-hygiene merge) | the tree proof answers the gates (section 20); the push skips on the stamp |

**Incremental equals full (sample proof, `tools/dq_look_prove.sh --stride 40`).** A reverse-order run over 526 types (every 40th of the
plan) and a shuffled run over a 263-type subset of them wrote 2257 rows in the subset run; every one is byte-identical to the larger run's
row (`comm -23` empty over 431 files): a type's rows do not depend on which other types a run probes. Both runs also showed 14 and 6
committed snapshot rows that no longer match the render on master (a finding about the tree, not the incremental path): master's look
snapshots need a bless, which today is an unsharded full run (hours) because shards cannot write the same root file.

## 25. Fast, reliable gates (17 October 2026, `tools/gate-speed`)

**Land with `tools/dq_land.sh`: prove outside the lock, lock only to merge and push.**

```sh
export DQ_MERGE_SESSION=<your lane branch>
bash tools/dq_land.sh --tests "dq_my_test dq_my_other/*" [--covers GLOB] [--rounds N] [--dry-run]   # from the lane's worktree
```

A gate run inside the merge lock took 3-10+ minutes and everyone queued behind it. The proof is stored under the tree hash (section 20), so it
can be made before the lock: `dq_land.sh` asks `git merge-tree` what tree merging the lane into `origin/master` would give and whether that
tree already has a covering proof (`proof_covers_merge`). If not, it runs `dq_lane_ready.sh --lite` (no lock held; other lanes land
meanwhile). Only then does it take the merge lock, and only for the fast part: merge, `dq_merge_gates.sh` (answers from the proof: no compile, no
test world), `dq_push_master.sh` (which still verifies master did not move and that the lane landed). If master moved while the lock was queued, the lock is
given back at once (the worktree reset to `origin/master`) and the lane is proved again, up to `--rounds` (default 3); the last round
proves and lands under the lock as before, so a busy master delays a lane but never starves it. `bash tools/ci/test_land.sh` covers the loop.

**Disjoint accept (`tools/dq_land_disjoint.sh`).** A lane that sat in `dq_land.sh` for hours re-proved (15 min of compile and test world) every time master moved.
Now, before proving, `dq_land.sh` asks `dq_land_disjoint.sh`: the lane has a valid stamp (`dq_lane_check.js --lite` VALID), every master commit since the stamp's
base was itself landed through a proved gate (a lane-ready / merge-gates / light-batch note, a merge of such a parent, or docs only), the lane's files and master's
changes are disjoint, neither side touched a path in `tools/ci/land_disjoint_global.txt` (`code/__defines/`, lint config, `tools/analyze`, `tools/build`, `tgui/`, `maps/`,
...), a shared `deepquarry.dme` edit touches no `__defines` include, `git merge-tree` is clean, and master's tree has a proof of the smoke set. Then the lane is merged
with master, `analyze gen` + `check_ratchets.sh --changed-only` run (seconds, no compile, no test world), the merged tree gets a proof inheriting master's and a
lane-ready note, and the push is a fast-forward. Every decision is logged as `== land-disjoint: ACCEPTED ...` or `NOT accepted: <reason>`; a refusal falls back to the
re-proof above (also on the last round). A move while the lock was queued is no longer a reason to re-prove and does not count as a round (at most
`DQ_LAND_FREE_ROUNDS`, default 8, uncounted rounds); `DQ_LAND_DISJOINT=0` turns the shortcut off.

**What runs inside the lock.** The lock should cover merge + gates-from-proof + push (about a minute). It grows to 25 minutes when the merge commit has no stamp and no
`<sha>.dm.ok`: `dq_push_master.sh` then runs `build.sh dm` again on the merge (and `dq_merge_gates.sh` runs the full gates when the merged
tree has no proof). That happens on the last round, and when the lane's tip carries no lane-ready note so the fast-forward path is not taken. The disjoint accept puts the
note on the merged tip so the push fast-forwards with nothing re-run; the DreamMaker cross-check has been dropped from the local gates, so the push no longer runs a second compile.

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

**`current` stays on master.** `dmb-bin/current.commit` names the commit whose compiler `current` is, and it is always a commit in `origin/master`
(`mayAdvanceCurrent`, `publishableCommit` in `tools/build/lib/dmbc_cache.ts`). A publish from a commit that is in master records that commit; a checkout
ahead of master whose compiler sources (`DMBC_CACHE_INPUTS`) equal master's tip builds master's compiler and records master's tip; a commit with compiler
changes master lacks is refused (it logs "will not become the current compiler" and the build uses `current`), and a checkout with dirty compiler sources
builds privately and never publishes. If `current.commit` is not an ancestor of master (a dead commit, or one on an unmerged branch), any checkout at or
ahead of master's compiler sources replaces it; otherwise `current` moves only to a descendant of the recorded commit. `DQ_DMBC_MASTER_REF` names the ref
(default `origin/master`). `bash tools/ci/test_dmbc_current.sh` covers the normal, behind, dead and unmerged-ahead cases.

**Stale test names in stamps.** A stamped test list can name a test master has since deleted. `tools/dq_declared_tests.sh` (`filter_declared_tests`) drops
exact names no `/datum/unit_test/` declares and logs each ("dropped (no longer declared, ...)"). `dq_merge_gates.sh` applies it to every lane stamp and to the
`--reproof` list (the push recheck's replay of a stamped list); `dq_lane_ready.sh` applies it to the lite re-proof list. Globs are kept, and a name typed in
`--tests` or on the `dq_focused_test.sh` command line is not filtered, so a typo still fails. `bash tools/ci/test_declared_tests.sh`.

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

## 28. DreamMaker still has to accept the tree (October 2026, `tools/dmb-behaviour`)

The native compiler is the default, so for a while nothing noticed that master no longer compiled with DreamMaker (105 errors:
`to` used as a named argument and formal, 99 subtype overrides written `/T/proc/name()` where the parent already declares the
proc, and `nameof(call().var)`). Two guards now stop that:

- `dmbc` reports the same errors as DreamMaker for those classes (`fixtures/diagnostics/cases/keyword_*`, `inherited_proc_*`,
  `inherited_verb_*`, `nameof_call_expression`). In DM an override is written without `proc/` or `verb/`; with the keyword it is a
  `duplicate definition` of the nearest ancestor's declaration. `to` and `in` cannot be argument names; `if`, `set`, `while` and the
  like cannot be formal names; a `nameof` operand is a reference path, not a call or index.
- The local gates (`tools/dq_merge_gates.sh`, `tools/dq_push_master.sh`) no longer compile with DreamMaker (the 3 minute cross-check and the second
  one in the push lock are gone, 2026-10-24); the CI `dreammaker_cross_check` job (`tools/ci/dm_equiv.sh`) and CI's production compile are the DreamMaker
  checks. Check a new class locally with
  `python tools/dmb/scripts/diagnostics_corpus.py record --dm <dm.exe> <case>` then `check --dmbc tools/dmb/target/release/dmbc.exe`.

## 27. Lane classes, the light path and what runs when (17 October 2026, `tools/worktree-lifecycle`)

**Pick the class when you lease** (`bash tools/dq_lane_pool.sh lease <branch> [--class general|compiler|light] --wait`):

| Class | Slots | Use it for | Gets |
|---|---|---|---|
| general (default) | `pool-1..3` (`DQ_LANE_POOL_SIZE`) | game work: any `.dm`, maps, icons, tgui | the normal queue; DM compile 2, test worlds 3 |
| compiler (`tools/dmb*` branches are detected; or `--class compiler`) | `pool-c1`, `pool-c2` (reserved, general lanes never take them; a third compiler lane may use a free general slot) | compiler/daemon work and its fixes | served ahead of the general queue; first claim on the machine slots (priority 0 like the merge worktree) and ONE cargo slot beyond the cap |
| light (`--class light`) | `pool-light` (one shared, own queue) | docs, lane/tooling scripts, Rust/compiler-only changes | edit, commit, `bash tools/dq_land.sh --light`, release: minutes. Never runs a DM compile or a test world (`dq_machine_slots.sh` refuses with exit 64) |

**Landing a light lane.** Under section 26 only the batch lander pushes master, so `dq_land_batch.sh run` is the lander's step, not a lane's. `bash tools/dq_land.sh --light` pushes the branch (never forced) and queues it; whoever runs the batch next merges
every queued light branch in one merge (`tools/dq_land_batch.sh run`), runs the cheap checks for what changed (`tools/dq_light_checks.sh`) and
pushes master once with `dq_push_master.sh --light` and a `refs/notes/light-batch` stamp, which `dq_push_stamp.sh` and the pre-push hook accept
only while nothing under `.dm .dme .dmm .dmi maps/ icons/ code/ interface/ sound/ tgui/` changed since origin/master
(`tools/dq_light_paths.sh`). A light branch that touches one is refused and dequeued: lease a general lane. Status: `dq_land_batch.sh status`.

**What runs in each case**

| Case | DM compile + DreamChecker | Test world (smoke, lane tests) | Ratchets + analyze | Cheap checks |
|---|---|---|---|---|
| Doc-only change (light) | no | no | no | doc links |
| Script change (light) | no | no | no | `bash -n` (+ shellcheck if installed), doc links |
| Rust/compiler change (light) | no | no | no | `cargo test` for each touched crate (cargo slot) |
| `.dm`/lints touched in a light batch | refused | refused | n/a | refused (general lane) |
| General lane, first `dq_lane_ready.sh` | yes | yes (smoke + its tests) | yes | n/a |
| Lane already contains current origin/master and is stamped (`dq_land.sh`) | no | no | no | fast-forward push, zero re-runs |
| Master moved, stamped lane re-merges cleanly, master changed no DM code since the lane's base | no | no | no | stamp carries (`dq_push_stamp.sh`) |
| Master moved and changed DM code since the lane's base | yes (merged tree) | only if the stamp does not carry (then the lane's stamped list) | yes | n/a |
| Merge batch of several general lanes (`dq_merge_gates.sh`) | yes | smoke set (the combination), never a lane's own proved tests | yes | n/a |

**One run per worktree.** `dq_land.sh` and `dq_lane_ready.sh` take a lock (`tools/dq_run_lock.sh`, `E:/dq-cache/lanes/<slot>/run.lock`, holder pid
checked) and refuse to start when another live run holds the worktree, naming the holder; `dq_land.sh` running `dq_lane_ready.sh` itself is not
a second run. Overlapping runs used to change the tree under each other ("the tree changed during the gates; not stamping").

Tests: `bash tools/ci/test_lane_pool.sh`, `bash tools/ci/test_light_checks.sh`, `bun test tools/build/lib/machine_slots.test.ts`.

## 29. The batch train (24 October 2026, `tools/batch-train`)

**The default way to land a lane.** Per-lane landing (`dq_land.sh`) proved every lane on its own merge and proved it again whenever master moved:
with 25-40 minute gate rounds and frequent landings a lane needed 2-2.5 hours. Audit of one day's logs: gate rounds median 23 min (production
compile 1184 s, test phase 1055 s), 13 of 14 focused runs at 10 minutes or more, 86 full test-dme compiles = 8146 s. The train gates every waiting lane
**once, together**, and a lane's own wait is the queue plus one cycle.

```sh
# in the lane's worktree, everything committed, focused tests green, `bash tools/ci/check_ratchets.sh --changed-only` clean:
bash tools/dq_train.sh enqueue --tests "dq_foo dq_bar"     # records branch + tip + tests, starts the integrator if none runs, returns at once
bash tools/dq_lane_pool.sh release <branch>                 # the slot is free now; the branch ref stays in the shared repository
bash tools/dq_train.sh status                               # later: integrator, queue, bounced lanes (+ report paths), recent landings
bash tools/dq_train.sh report <branch>                      # why a lane was bounced (also reports/<branch>.md under E:/dq-cache/train)
bash tools/dq_train.sh enqueue --light                      # docs/tooling/Rust-only lanes: no DM compile, no test world (refused when a heavy path changed)
bash tools/dq_train.sh dequeue <branch>                     # withdraw a lane
```

A lane that is neither queued nor bounced has landed (`status` lists the last landings). The train lands **exactly the tip that was enqueued**:
a branch that moved afterwards is bounced ("enqueue the new tip"). A bounced lane gets a report (the reason, the failing tests, the last 70 lines of the
gate output, the next step); fix it in a freshly leased slot, commit, enqueue again. Nothing is ever merged for a bounced lane.

**The integrator** (`dq_train.sh run`) is one detached process: `ensure` (called by `enqueue`) starts it through PowerShell `Start-Process`, outside the
shell's process group, so the 30-minute kill of whatever shell enqueued does not take it along. One at a time: a lock directory under
`E:/dq-cache/train/run.lock` with the pid and a liveness check (a dead holder's lock is replaced). It runs from a snapshot of `dq_train.sh`
(`train/self/`), exits when the queue is empty, and the next `enqueue` starts a fresh one with that lane's copy. It repeats cycles:

1. Fetch; validate every queued lane (branch exists, tip unchanged, not already in master).
2. Choose the batch: queue order, at most `DQ_TRAIN_MAX_LANES` (8) and a union of tests (the lanes' tests plus smoke and gameplay) estimated at no more
   than `DQ_TRAIN_TEST_BUDGET_SEC` (420 s) from the recorded per-test times (`tools/dq_train_estimate.js` over `data/test-runs/`; an unknown test counts 20 s);
   a lane that does not fit waits for the next cycle. A test phase that hits its cap halves the batch limit for the next cycle; it doubles back after clean landings.
3. All lanes light: `tools/dq_land_batch.sh` (cheap checks, no DM build; one lane at a time if the batch cannot attribute a failure). Otherwise one gate on the
   combined tree in the train's own worktree (`E:/projects/dq-wt/train-base`, branch `train/integ`, created by the first heavy cycle; own compile root shared
   with the merge worktree), through `tools/dq_merge_batch.sh`: merge every lane onto current origin/master in order (a conflicting lane is bounced), then
   `dq_merge_gates.sh` once: analyze gen + ratchets, the production compile as a **native** `build.sh dm` plus DreamChecker (`DQ_DREAMMAKER_GATE=0`: CI keeps the
   DreamMaker cross-check), one native test compile, the union of tests and the smoke set. On a failure it bisects by lane (prefix halving; an attempt on a tree
   already proved is answered from the proof cache), bounces the culprit(s) and proves the rest again. A test that fails and then passes alone is a flake: the gate's
   retry ledgers it (`tools/dq_flake_log.sh`) and nobody is bounced.
4. Push with `tools/dq_push_master.sh --expect "<lanes>"` (strict: refused when master moved since the gate started; the merge-gates stamp on the batch's HEAD is
   what `dq_push_stamp.sh` and the pre-push hook check). Master moving under a gate is not the lanes' fault: they stay queued and the next cycle repeats; after
   `DQ_TRAIN_STALL_CYCLES` (3) cycles without a landing or a bounce the integrator stops (`STALLED` in the log) and the next enqueue restarts it.

**Time limits.** Testing never runs over 10 minutes: the gate's test-phase cap is `gate_cap_minutes` (5 min plus 1 min per test, ceiling 10; the train also sets `DQ_FOCUSED_MAX_MIN` to `DQ_TRAIN_TEST_MAX_MIN`, 10), and a run killed at the cap is never retried (another run would only spend the cap again)
and is not blamed on a lane: the batch is reported CAPPED, the lanes not yet judged are deferred, the batch limit halves; a single lane whose tests exceed the
cap alone is bounced. No new gate attempt starts after `DQ_TRAIN_CYCLE_MAX_MIN` (20) minutes into a cycle (`DQ_BATCH_DEADLINE`): lanes not yet judged are
deferred, the proved prefix still lands. That deadline applies only to a batch with unprechecked lanes; a prechecked batch bisects to the end (29a). The shell that starts the integrator returns in about 20 seconds; no Bash command ever has to outlive 30 minutes.
**Nothing heavy runs under the merge lock**: the train works in its own worktree and never takes it (compiles and tests hold machine slots with priority 0, as the
merge worktree does). Compiles per batch: one test compile and one production compile; the test phase and a bisect attempt on an identical tree reuse the tree
proof, and a bisect attempt on a different tree is an incremental compile in the same daemon session, not a cold one.

**The smoke set was trimmed** (`tools/ci/smoke_tests.txt`): measured over 99 recorded runs the smoke set averages 90 s and the gameplay set 27 s; `dx_menu_order`
(33 s mean, 250 s worst) was removed (`dx_menu_order_static`, 11 s, stays; the full golden sweep runs in the full suite). Together they are about 2 minutes of tests,
inside the 3 minute target, so the 10 minute cap leaves room for the lanes' own tests. Add a test to the smoke set only when it is fast.

**State and logs** (disposable, `E:/dq-cache/train`, or `DQ_TRAIN_STATE`): `queue/`, `bounced/`, `landed/`, `reports/`, `log/train.log` (every decision, with times),
`log/cycle-*.log` (a cycle's gate output) and `log/cycle-*.push.log`, `cycle.txt` (the phase now), `batch_limit`. The attempt logs of a batch are in
`train-base/data/merge-batch/` and the gates' job logs in `train-base/data/merge-gates/`.

`DQ_TRAIN_DRY_RUN=1 DQ_TRAIN_ONCE=1 bash tools/dq_train.sh run` runs one cycle through every push check and stops before the push (lanes stay queued).
`bash tools/dq_land.sh` still works and prints a notice; `dq_land.sh --light` is the old light path (the train's `--light` is the same machinery behind the same queue
discipline). Tests (stub gates, stub push, a scratch origin): `bash tools/ci/test_train.sh`; the batch driver's own: `bash tools/ci/test_merge_batch.sh`.

### 29a. Prechecks, affected-only jobs, parallel bisect (26 October 2026, `tools/train-speed`)

Why: on 26 October one gate attempt took about 741 s (analyze_tests 663 s, DreamChecker 410 s, tests 335 s, ratchets 282 s); a batch of 7 with
one bad lane needed a serial bisect, the 20 minute cycle deadline allowed one or two attempts per cycle, so isolating the lane took three cycles
(about 90 minutes) with nothing landing; and lanes reached the train having passed only their focused tests, so DreamChecker, analyzer and
ratchet failures first showed up inside batches. Over 25-26 October (47 h of log): 99 heavy cycles, median 1046 s (p90 1743 s), 75 lanes landed
(about 2.7 per hour of cycling), 56 bounces, enqueue to landing median 102 min (p90 295 min).

**Prechecks** (`dq_train.sh precheck-run`, started detached by `ensure` and by every integrator cycle; lock `E:/dq-cache/train/precheck.lock`). Every
queued heavy lane is gated ALONE on current origin/master before it may join a batch:

1. a conflict probe, seconds: `git merge-tree` of the lane and origin/master (in a throwaway object directory). A real conflict bounces the lane at once
   ("precheck: merge conflict ..."); a conflict in `deepquarry.dme` alone is not one (below).
2. the gate a batch would run, on that one lane: `tools/dq_merge_batch.sh --lanes <lane>` in a worker worktree `E:/projects/dq-wt/train-pre<N>`
   (`DQ_TRAIN_PRECHECK_WORKERS`, 2), each with a compile root of its own (`deepquarry-pre<N>`, `compile_root.ts rootKeyFor`), so a worker's next precheck is an
   incremental compile of master plus the next lane in the shared daemon, not a turn in the lanes' root. Every heavy step holds machine slots below the train
   gate's priority and runs below normal priority; no precheck STARTS while free RAM is under `DQ_TRAIN_PRECHECK_MIN_FREE_GB` (16).

A lane that fails alone is bounced with the usual report and never costs a batch or a bisect. The verdict is kept per (origin/master, lane tip) in
`E:/dq-cache/train/precheck/v/<lane>@<tip>@<master>` (pass, fail, conflict or error, seconds, log); `status` shows it per lane. Batches take only lanes with a
PASS for their tip (light lanes need none). A lane with no verdict after `DQ_TRAIN_PRECHECK_WAIT_MIN` (45, counted from when prechecks started) and no precheck
running rides the old way (a small batch with the cycle deadline), never mixed into a prechecked batch. `DQ_TRAIN_PRECHECK=0` turns prechecks off.

**A batch of prechecked lanes.** Up to `DQ_TRAIN_MAX_LANES_PRECHECKED` (20; `batch_limit_pre` halves after a failed batch and doubles back). Each lane's own
tests passed alone, so they run again only when the lane can interact: it shares an *area* (a code file's first three path components, e.g. `code/modules/mob`;
another file's directory) with another lane of the batch or with what master changed since its precheck, or someone touched a path in
`tools/ci/train_interact_global.txt` (defines, engine, library, controllers, maps, the build and the compiler). Test files, the manifest, baselines, docs and
changelogs are not areas. The test budget (`DQ_TRAIN_TEST_BUDGET_SEC`) counts only those tests plus the smoke and gameplay sets, which always run; the log names
the lanes whose tests were left out. A failure in such a batch is an interaction, so it has **no cycle deadline**: its bisect runs to the end in the same cycle
(the machine is protected by the machine slots and the RAM floor, not by the deadline), and the halves run **at once**: `dq_merge_batch.sh` with
`DQ_BATCH_WT2` (`E:/projects/dq-wt/train-bisect`, own root `deepquarry-bisect`, created in the background by the first prechecked cycle) gates good+L here and
good+R there; L failing narrows to L, L passing grows the proved set by L and narrows to R. One attempt at a time when free RAM is under 16 GB.

**Affected-only gate jobs** (`dq_merge_gates.sh`, for every gate, prechecks included):

- `analyze_tests` (still only when `tools/analyze/` or `tools/ci/lint_scopes.toml` changed): its harness cache (`tools/build/lib/analyze_test_cache.ts`) was
  bypassed on every gate because a vendored path dependency (`vendor/dreammaker`'s `#[doc(hidden)]`, `vendor/interval-tree`'s untagged fences) looked like an
  executable doctest; `cargo test` never runs a dependency's doctests, so only the analyzer's own files are classified now. A hit runs every harness (about a
  minute) instead of recompiling them (9 of the 10-11 minutes).
- `dreamchecker`: SpacemanDMM has no incremental or per-file mode, so its verdict is reused when every file it reads is identical to a tree that passed
  (`tools/dq_gate_verdicts.sh`: key = the DreamChecker binary, the index entries of every tracked file outside `doc/ tools/ tgui/ html/changelogs/ .github/ SQL/
  *.md`, and the content of the untracked and generated files under `code/ maps/ interface/`; passes only, under `E:/dq-cache/train/verdicts`). A lane that changes
  no DM, or a bisect attempt on a tree already checked, skips it; any DM change runs it. A proof reuse also takes the verdict, so the push keeps its stamp.
- `ratchets`: the second `build.sh analyze` after `check_ratchets.sh` (the same `analyze check` over the same tree, about a minute) is gone. `--changed-only`
  is not used in the gates: it still scans the whole tree (no time saved) and only hides sites in unchanged files, which a batch can create.

**`deepquarry.dme` conflicts** (`tools/dq_dme_resolve.sh`, called by every merge in `dq_merge_batch.sh`). A merge that stops on the manifest alone is resolved
by merging the include sets (`dme_merge3`: a side's addition kept, a side's removal kept), verified against the files on disk, and committed; the union merge's
known failure (an include one side deleted, brought back because the other side added a line next to it) is repaired after every merge. `dme_merge3` is the
one function to swap for the generator when `tools/generated-dme` lands (`python3 tools/build/gen_dme.py --merge BASE OURS THEIRS`).

New state: `precheck/` (verdicts, running markers, probe marks; kept 3 days), `precheck.lock`, `batch.lanes` (the lanes of the gate running now; the prechecker
leaves them alone), `batch_limit_pre`, `verdicts/`; logs `log/precheck-<lane>-*.log`; worktrees `train-pre1`, `train-pre2`, `train-bisect` (kept by
`dq_worktree.sh gc`, permanent in `disk_budget.toml`). Tests: `tools/ci/test_train.sh` "prechecks" and "DreamChecker verdicts", `tools/ci/test_merge_batch.sh`
"parallel bisect" and "deepquarry.dme", `bun test tools/ci/analyze_test_cache.test.ts tools/build/lib/compile_root.test.ts`.

### 29b. Batch size, moved tips, gates by what changed (27 October 2026, `tools/train-conflict-limit`)

- **Only a failed test shrinks the batch.** A lane bounced for a merge conflict, a moved tip, or a DreamChecker or ratchet culprit says
  nothing about how many lanes fit (the bisect already isolated it), so the batch limit stays; a cycle in which no lane failed a test
  sets it back to the maximum at once (it used to double step by step: one conflict on 26 October left the train at 1 lane per cycle).
  A capped test phase still halves it.
- **A moved tip is adopted, not bounced.** A lane that committed more after it was enqueued keeps its place: the next cycle takes the
  new tip (log: `adopted the new tip`), and a precheck of the new tip follows. A tip that moves while its lane rides a cycle is carried
  to the next cycle (`mark_landed` keeps the lane queued while its branch holds commits master lacks). A light lane's new tip is pushed
  to origin first (never forced); if that push is refused, it is bounced as before.
- **A lane with no DM rides the light path.** A lane enqueued without `--light` whose change touches no DM path, `tools/dmb/` or
  `tools/build/` is promoted to light (its tip pushed to origin): it never starts a DM world. Light lanes go first and alone
  (`DQ_TRAIN_LIGHT_FIRST`); they no longer ride a DM gate. `DQ_TRAIN_AUTO_LIGHT=0` turns the promotion off.
- **Two test worlds.** The gate's union of tests runs in `DQ_TRAIN_TEST_WORLDS` (2) worlds at once (`DQ_MAIN_WORLDS`, any list over 8
  selectors is split; one compile). The selection budget is `DQ_TRAIN_TEST_BUDGET_SEC` (420) per world, less one 30 s boot per extra world
  (810 s of summed test time), so heavy lanes that one world deferred ride the same cycle.
- **Gate jobs by what changed** (`dq_merge_gates.sh`, since the merge base with origin/master, whose own gate passed every job):
  `analyze_tests` only for `tools/analyze/` or `tools/dmb/` (a `lint_scopes.toml` change runs the lints on the real tree in the ratchet job,
  not the fixture tests); DreamChecker only when DM, maps, interface, `SpacemanDMM.toml` or the generator (`tools/analyze/`) changed
  (SpacemanDMM has no per-file mode: a DM change still checks the whole tree, with the verdict reused per input key, 29a); ratchets only
  when a lint input changed (anything but docs, Markdown and `tools/` outside `tools/ci`, `tools/analyze`, `tools/dx`). The ratchets run
  warm: a change to the analyzer no longer forces a cold run (the caches are keyed by the engine's source hash); a cold audit runs only with
  `DQ_GATE_COLD=1` or `DQ_GATE_COLD_EVERY_MIN=<n>`. `check_ratchets.sh` runs the self-tests of the disk budget, the test-scratch rule and the
  varmap generator only when their own files changed (`DQ_RATCHETS_SELFTESTS=changed`, set by the gates; CI runs all).
- **analyze_tests builds incrementally.** The job uses the `gate-test` profile (`tools/analyze/Cargo.toml`: incremental, 256 codegen units,
  line tables, optimized dependencies) in the worktree's persistent target with 4 jobs (`DQ_ANALYZE_TEST_JOBS`), so the build that the
  job exists for (an analyzer change) rebuilds the touched units instead of the whole crate.
- **`bash tools/dq_train.sh lanes [--since T]`** (`tools/train/lane_times.py`): per lane, the time waiting in the queue, inside cycles and
  fixing after a bounce, and the mean of every gate phase over `train-base/data/merge-gates/*.timings`. On 26 October from 14:00Z: 33 lane
  episodes, mean 2h22m waiting, 36m in cycles, 3m fixing (79% of a lane's life was queue wait); gate means analyze_tests 533 s,
  DreamChecker 361 s, tests 345 s, ratchets 210 s, wall 544 s.
