# Throughput: why merges and test cycles were slow, and what changed

Branch `rewrite/throughput`, 2026-10-09. The tooling is described in `doc/rewrite/agent_workflow.md` sections 9-12. This file holds the
measurements and the reasoning. Every number comes from a machine other agents were loading (16 logical cores at 99%, 4-6 cargo and 5
DreamDaemon processes at any time), so read the spread, not the digit; a quiet machine is faster across the board.

## 1. `analyze gen` in the merge worktree: 135-150 s

Gate timings in `E:/projects/dq-wt/merge-base/data/merge-gates/*.timings`, matched to what each merge changed:

| Merge | Analyzer sources changed | Files changed | `gen` |
|---|---|---|---|
| master-fails-3 (e438dbced4) | no | | 44 s |
| draw-structures (0bf69012d3) | 1 file | 79 | 150 s |
| draw-items (70b59063e3) | 3 files | 206 | 135 s |
| draw-reagents (03bd6a84c3) | no | 89 | 47 s |

Four separate causes, each measured:

1. **The analyzer was rebuilt as `release` on every merge that touched `tools/analyze/`** (2 of the 4: 90-100 s of the 135-150 s). The gates and the push
   script forced `DQ_ANALYZE_PROFILE=release`, which no lane builds, so no cached binary exists for a merged source, and release is a thin-LTO,
   non-incremental compile (137 s from scratch here). `dev-fast` is the same source (the findings of the two are identical: `analyze check --no-cache`
   on the whole tree, 428 lines each, no difference), builds incrementally and is what lanes build. Now `dev-fast` everywhere; an incremental rebuild after an
   edit is 30-70 s under load, a binary-cache hit is 0.
2. **A cargo target shared by every worktree corrupted builds.** `build.ts` built the analyzer into `E:/dq-cache/analyze-target`. Cargo identifies a path
   package by its path inside the workspace, not by where the checkout is, and judges freshness by mtime. Observed during this work: my `cargo build` waited on the
   lock while another worktree built the library from different sources, found the library "fresh" (my files were older), and either failed ("cannot find
   `look_keys` in `dq_analyze`") or finished in 0.35 s and **stored a binary built from other sources under my source key** in the content-addressed cache.
   (verdigris's build already carries a workaround for the same cargo behaviour.) Now each worktree builds in its own `tools/analyze/target`, dependencies
   come from sccache, and the cargo slot serialises builds on the machine. If a binary in the cache was built before this change and misbehaves, delete its
   directory under `E:/dq-cache/analyze-bin/<key>`.
3. **A merge discarded the analysis caches, and `gen` then parsed the full model twice.** The cache stamp is the analyzer build plus `lint_scopes.toml`, and a merge
   changes one or the other most times. Pass 1 wrote the generated files (full model, 15-18 s); pass 2 re-checked the fixed point on the changed files, where the semantic
   record misses because the files pass 1 wrote are in its footprint (the model again, 15-18 s); each pass also spent 4-5 s in the generators. Now generators have a
   stage: stage 0 (declarations and text) runs to a fixed point, stage 1 (`reads`, `derived_reads`) runs once on the settled files, and stage 0 is proved fresh against
   what stage 1 wrote. The model is parsed once.
4. **A run with nothing to do still took 6-7 s of CPU** (the docs said 0.2 s). Warm, per generator: the defined-types scan of every file 1.5 s, the notice-listener scan 1.4 s
   (a substring search of the whole tree per notice type), stats 1.0 s, derived reads 0.6-0.9 s, system accessors 0.4 s, declare 0.3 s, all reading 6,900 `.dm` files on one
   thread. Now the tree is read on all cores first, the first two scans are per-file facts cached by content, a converged run records a digest of its inputs and outputs
   (`gen-state.bin`), and the outputs also go into a content-addressed store shared by worktrees (`E:/dq-cache/gen-store`).

Before and after, same inputs (draw-reagents + machinery-timed + machinery-prompts-reqs merged on top of the tree; the generated files are byte-identical):

| Run | Before | After |
|---|---|---|
| `gen` right after the merge (caches from before it, scopes file changed) | 44.5-52.6 s | 30.4 s: one model parse (16 s) + stage 0 twice |
| `gen` again, nothing changed | 5.7-12.8 s | 0.35-0.5 s |
| first `gen` in a new worktree (cold caches) | 80 s | 1.05 s when the store holds the inputs; 28 s when not |
| a source edit to the analyzer, in the merge worktree | release rebuild 90-100 s | dev-fast incremental 30-70 s, or a binary-cache hit |

So "seconds" holds when nothing the generators read changed since a run in any worktree (0.4-1 s) and when a single lane's merge matches its lane-ready tree. When the merged
branches change declarations it is one full model parse, 8 s on a quiet machine and 16 s on this one, plus an analyzer rebuild when they also changed the analyzer: 30-100 s
worst case instead of 135-150 s, not a handful of seconds. The model parse is the floor until the incremental compiler provides the model.

### `analyze look-keys`: 96-111 s cold, rerun on any `.dm` change

Profile of a cold run: semantic model 15 s, tables 0.4 s, own vars 0.5 s, probes 6.2 s, **closures 75.8 s** (6,217 distinct closures, 47.6 million edge expansions, each cloning
strings and hashing with SipHash). Now edges are interned, visited sets are bitsets, the integer tables use a multiplicative hasher and a name's fan-out is computed once:
rows byte-identical (compared on the real tree), cold run 33-37 s with the closures at 14 s.

It is also incremental now (`tools/analyze/README.md`, "`analyze look-keys`"). Measured on the real tree, each result compared with a full computation:

| Edit | Time | Rows recomputed |
|---|---|---|
| nothing | 0.5-0.8 s | none (cached) |
| a string in a proc of `code/controllers/kernel/boot.dm`, in no closure | 2.3 s | none, no full parse |
| a comment in `code/game/machinery/Beacon.dm` | 2.9 s | none |
| the body of `bluespace_beacon/draw` (a closure proc) | 15.6 s | 1 of 21,008 (one full model parse) |
| a string in a proc of `lightswitch.dm` | 14.3 s | 3 (a macro defined outside `code/__defines/` makes the partial parse disagree on that file's var values: conservative, correct) |

## 2. `test-build-boot`: 285-355 s

Where it goes (`dq_focused_test.sh --boot`, the first run in a cold worktree and a second one):

| Stage | First run | Second run | Avoidable? |
|---|---|---|---|
| prerequisites: icon repack, map bounds, DME check, verdigris bindings check, gen | 58 s wall (map bounds 45 s and the bindings check 45 s are cold-only; icon repack does 1.5 s of work and waits for the CPU; gen 6 s) | 45 s (the bindings check 37 s: the merge changed its inputs) | persistent worktree: 12-20 s |
| DreamMaker compile of the test `.dmb` | 189 s | 177 s | not here (the incremental compiler); the `dm_compile` slot limits contention |
| copy of the 223 MB `.rsc` and 65 MB `.dmb` into the run slot, trusted-DLL approval, port, DreamDaemon launch | 24 s | | no: a hard link would let a recompile corrupt a running world |
| world boot to "Unit-test suite starting" | 46 s | | |
| the test, shutdown | 4 s | | |
| **total** | **327 s** (`dm-test` 268 s) | **298 s** (`dm-test` 254 s) | |

The compile is 55-60% of it and the world (copy, launch, boot) 25-30%. What the gates did that was avoidable:

- **A world booted only to check the boot, then a second world for the batch** (the copy, the launch and a 46 s boot twice, 70-100 s). Every test world already fails the run when its boot is
  unclean, so the gates now run the smoke set (it starts with `dq_boot_gate`) and the tests that need running in the one world they compile for.
- **The ratchets (30-37 s) and the push script's production `build.sh dm` (140-224 s, DreamMaker plus DreamChecker) and `build.sh analyze`** ran one after the other, after the test world, and the push
  script ran them again. They now run beside the test world, and the push script reuses their stamp.
- The prerequisite targets ran inside every job concurrently, racing on `icons/gen` and the bounds file. The gates run them once, first.
- A watchdog that killed a world 30 s after its results file appeared. On a loaded machine that is shorter than the world needs to write `clean_run.lk`: a lane-ready attempt here passed 27 tests and
  reported `exit 1, not clean`, losing 15 minutes. Now the world writes `finished_run.lk` for failed runs too and the watchdog waits for it (up to 180 s), then kills a lingering daemon 5 s later.

## 3. Measured: a lane-ready run, the gates with a valid stamp, the push

`dq_lane_ready.sh --no-pins` on this branch (master had moved; 25 smoke tests, production compile, ratchets, analyzer; machine loaded):

| Step | Seconds |
|---|---|
| merge of origin/master, gen | ~110 |
| gates wall | 361: gen 2, prepare 25, then in parallel tests 328 (compile + 25 tests in one world), dm 154, ratchets 34 |
| total | 475 |

The same checks the old way, serially on this machine: gen + prepare (27) + `--boot` run (298-327) + ratchets (34) now, and the push script's production compile (154) and analyzer later, before a single
lane test ran: about 520 s, and the lane's tests as a further batch. Then, for the merge agent:

- `dq_merge_gates.sh --lanes "rewrite/throughput"` with the stamp valid: tests 2 s (the lane's list was skipped; the smoke list found the rerun guard's record), dm 140, ratchets 12, 160 s in all.
- `dq_push_master.sh` (dry run) on that HEAD: 1 s instead of the 190-260 s of its dm + ratchets + analyze steps.
- The stamp check against a master that moved: unrelated files VALID, a file the branch changed or a global path INVALID with the file named, no note UNSTAMPED.

A lane whose tests include the look pins pays for stale keys: the first attempt ran five worlds for 13 minutes because master's recorded keys were behind other lanes' merges.

## 4. What is left, in order of payoff

1. **The DM compile (3 minutes loaded, 80-110 quiet) is the floor of every test cycle and gate.** Nothing here reduces it; the incremental compiler is the lever.
2. **The look pins after master moved.** Whoever runs first pays and commits `look_keys.txt`; two lanes doing it in parallel conflict on that file. Re-recording the keys and snapshots on master
   in the merge worktree after each batch would take that cost off the lanes.
3. **The full model parse (8-16 s)** when declarations change: `gen` and `look-keys` each build it in their own process. Sharing one parsed model between them, or the incremental compiler's
   analysis API, removes it.
4. **`look-keys` false positives**: a file using a macro defined outside `code/__defines/` has its var digests recomputed on every edit. Including the directive files in the partial model would
   remove it. Its cache (38 MB) is per worktree; the gen store pattern would share it.
5. Two unit tests of the analyzer were already failing on master: `lints::check_grep::tests::rule_names_follow_the_part_titles` (a rule name and its title disagree) and the two
   `generated_reads.golden` files (the chunked output was never re-blessed; re-blessed here).
