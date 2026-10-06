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

