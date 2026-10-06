# Where the build/test loop's time goes (October 2026)

Measured on the dev machine (Windows 11, other agents' builds running, so read the spread rather than the
digit) in one worktree, `rewrite/infra-speed`. "Before" is master as of 2026-10-05 afternoon; "after" is with
the changes listed at the end.

## The loop, step by step

| Step | Before | After | Notes |
|---|---|---|---|
| analyze binary in a fresh worktree | 2 min 12 s cargo build | 0 s (copied from `E:/dq-cache/analyze-bin`) | content-addressed cache, `DQ_ANALYZE_CACHE` |
| `analyze gen` (now runs on every build) | n/a (`--check` in ratchets, 3.5 s) | 2.3-3 s warm, 18-36 s cold | cold after many DM edits: the semantic re-parse |
| `verdigris-bindings-check` | 16-49 s every build | 0.13 s when unchanged | it read every DM file; now keyed on the Rust sources and the DM file list |
| `icon-repack` | 1.5 s alone, 42-74 s inside a build | 6-7 s inside a build | it was starved by the bindings check running beside it |
| `validate-dme` | 2.5-3.5 s | same | |
| DreamChecker (`build.sh dm` only) | 42-51 s, before DreamMaker | runs beside DreamMaker | a DreamChecker failure still fails `dm` and deletes the `.dmb` |
| DreamMaker, production `.dme` | 107-125 s | 69 s measured (less contention) | unchanged work |
| DreamMaker, test `.dme` | 110-150 s | same; skipped when the content hash is unchanged | `data/dmb-cache` (already present) |
| DreamDaemon boot to "Initializations complete" | 16-24 s (Atoms 17 s) | same | the minitest map's atom init; not reduced |
| Test block pool before the first test | 8 z-levels, 5.2 s | 2 z-levels, 0.8 s; grows on demand | focused runs only (`UNIT_TEST_BLOCK_POOL_FOCUSED`) |
| Round-start settle (focused) | 2 s | same | |

## End to end

| Command | Before | After |
|---|---|---|
| `tools/build/build.sh dm` (DM changed) | 3 min 53 s | 1 min 20 s |
| `tools/build/build.sh dm` (nothing changed) | about 1 min (bindings, repack, DreamChecker) | 11 s |
| Focused rerun, `.dmb` cached (`dq_conversion_pin`) | 1 min 46 s (49 s in the world) | 55 s (38 s in the world) |
| Focused run with a compile (`--boot`) | about 3 min 30 s | 3 min 9 s (compile dominates) |
| A snapshot-only change (i7 rows, pins) | full recompile | no recompile (rows are read at run time) |
| First build in a fresh worktree | + 2 min 12 s analyze build | + 0 (cache hit) |
| Merge of two branches touching declarations | conflict on `declare.dm` (464 commits in 30 days) | clean (generated files untracked) |

## Codex `tools/dmb` as a pre-check

`dm-compile check deepquarry.dme` (preprocess and parse only, no type or proc resolution) takes 13-14 s against
DreamMaker's 70-150 s. It is wired as an optional pre-check: `tools/build/build.sh dmb-check`, or
`DQ_DMB_PRECHECK=1` before a `dm-test` compile. Findings:

- One false positive on master (`metrics_api.dm:69`, a macro call whose arguments span lines), listed in
  `tools/dmb/precheck_known.txt`.
- It does not catch everything DreamMaker does: an unterminated proc header at the end of a file passed it.
  `analyze gen`, which every build now runs first, caught that one in 2 s.
- So it is advisory: it never replaces DreamMaker, and is not on by default. The native compiler's full
  `build-project` path was not evaluated as a replacement here.

## What did not move

- The DreamMaker compile itself (about 2 minutes for the test `.dme`). The test `.dmb` cache already skips it
  for an unchanged tree; snapshot-only changes no longer touch DM.
- World boot (the minitest map's atom initialization, about 17 s). Skipping the map load would need a
  map-free test world; not attempted.
