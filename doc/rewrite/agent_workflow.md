# Agent workflow: build, test, merge

What changed in the build/test/merge loop (October 2026, `rewrite/infra-speed`) and what to do on your
next merge. Read this once; the rest of the loop is in `AGENTS.md` section 4 and `doc/testing.md`.

## 1. Generated files are no longer committed

`analyze gen` output is build output now:

| Path | Written by |
|---|---|
| `code/engine/_generated/*.dm` (declare, ids, reads, stats, actions, event_twins, system_accessors) | `analyze gen` |
| `code/_generated/reads.dm` | `analyze gen derived_reads` |
| `tgui/packages/tgui/interfaces/generated/*.d.ts` | `analyze gen ui_types` (and `build.sh ui-types`) |

They are in `.gitignore` and untracked. Every build target that compiles or lints DM runs `GenTarget`
first (`build.sh dm`, `dm-test` and so `tools/dq_focused_test.sh`, `ui-types`, `lint`, `analyze`,
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
