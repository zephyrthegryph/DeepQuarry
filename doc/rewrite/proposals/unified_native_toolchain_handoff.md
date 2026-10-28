# Agent handoff: unify native compilation, Analyze and DreamChecker

## User request and authorization

The user explicitly requested planning and then implementing full convergence of all three tools to reuse memory and CPU. They subsequently requested this handoff to an agent with working Bash. Continue implementation; do not stop at another architecture proposal or ask again whether to start. Follow the repository's current AGENTS.md and integration workflow. No subagents were used or authorized by this handoff.

The desired endpoint is one native frontend, one semantic representation, one incremental query graph and one daemon per worktree. Merely hosting the old parsers in a common process, or adding a sibling Analyze daemon, does not meet the request. Checker-only inference and compiler-specific code generation will still have unique work; eliminate duplicated prerequisites without claiming that all three products cost the same CPU.

## Workspace and changes to preserve

Source checkout: `E:/projects/CHOMPStation2`.
Observed HEAD: `7d987e36d2253ac2d343d8906b1bdb28fd1136d4`, branch `master`.
No branch, lease, commit, merge or push was created in this session.

Our files are untracked:

1. `doc/rewrite/proposals/unified_native_toolchain.md`: full implementation plan and stage-0 checkpoint.
2. `tools/dmb/scripts/unified_frontend_inventory.py`: read-only deterministic source audit.
3. `tools/dmb/scripts/test_unified_frontend_inventory.py`: six unit tests for that audit.
4. This handoff file.

Other pre-existing work is NOT ours; leave it alone:

- Modified `code/game/world.dm`.
- Untracked `bash.exe.stackdump`, `du.exe.stackdump`, `codex_tasks.md`, `doc/rewrite/startup_profile_1013.md`.

Lease a compiler lane using the pool and move/copy only our files into it, preserving the originals until safely recorded. Do not create a worktree manually. Re-read current pool/workflow instructions: they have evolved from the supplied summary.

```sh
bash tools/dq_lane_pool.sh lease compiler/unified-analysis --class compiler
```

The failed lease attempts in this session did not execute Bash and acquired nothing. Recheck actual pool state rather than assuming any slot is free. Earlier observations: pool-c1 held compiler/async-cache-flush, pool-c2 was detached; pool-1 belongs to another Codex compiler task. Do not commandeer them.

## What actually exists

Only the plan and inventory tooling have been implemented. No production compiler/Analyze/checker integration, shared semantic cache, checker port or performance improvement has been implemented. Stage 0 has started and is incomplete.

The audit:

- Scans Analyze Rust source for lexical parser/model/whole-tree dependencies, ignoring Rust comments and strings.
- Records content hashes, source lines, native interface anchors and checker configuration.
- Accepts `--checker-source PATH`; available source is explicitly pin-unverified until independently verified.
- Marks unavailable checker families as unknown, NOT an empty successful coverage list.
- Supports `--require-checker-source` to fail if missing.
- Is a lexical migration aid, not a type-resolved dependency graph or parity certificate.

Validation completed:

```sh
python -m unittest discover -s tools/dmb/scripts -p test_unified_frontend_inventory.py -v
python tools/dmb/scripts/unified_frontend_inventory.py
```

All six tests passed. The full-tree inventory was evaluated twice and matched deterministically. `git diff --check` passed, though these files are untracked and that command does not validate their contents by itself. No Rust/native build, DreamChecker, ratchets, compile-equivalence or runtime tests ran.

Audit results on the observed checkout (files, not rule counts):

| Area | Files | Direct dreammaker references | Semantic-review candidates |
|---|---:|---:|---:|
| codemods | 4 | 0 | 2 |
| frontend | 1 | 1 | 1 |
| gens | 12 | 1 | 11 |
| lints | 98 | 6 | 36 |
| sem | 22 | 13 | 20 |

Seven native interface anchor files exist; their completeness is not proven.

## Why this agent could not proceed through the lane workflow

In this session's restricted launcher, both Bash and MSYS utilities failed initialization with `0xC0000142` (signed exit -1073741502). Native Git and Python worked. Direct Bash shell selection was rejected because this execution environment only supports PowerShell. Native download from raw.githubusercontent.com failed DNS; the web fetch also failed.

The session's default temporary directory allowed creation but not writes inside newly created Python test directories. Setting TEMP/TMP to the writable `E:/workspace` for the test invocation fixed Python tests. That did NOT fix Bash. These are session-specific observations, not evidence that the user's other lanes or Git installation are broken. Do not spend your working Bash lane re-diagnosing them.

## Read these first

- Current `AGENTS.md`, `doc/rewrite/agent_workflow.md`, `doc/testing.md`.
- Our `doc/rewrite/proposals/unified_native_toolchain.md`.
- `git show origin/master:doc/rewrite/proposals/one_frontend.md` if absent locally. It exists on the observed origin/master, but not this checkout. Our new plan replaces its optional-convergence direction.

Native interfaces inspected:

- `tools/dmb/crates/dm-query/src/lib.rs`: dynamic dependencies, reverse edges, early cutoff and eviction. Cross-thread cyclic query fetches can deadlock; solve recursive inference in SCC tasks rather than cyclic blocking queries.
- `tools/dmb/crates/dm-syntax/src/lib.rs`: typed body syntax, scopes, visitors, reference roles. Documentation disclaims complete expression coverage; audit actual gaps.
- `tools/dmb/crates/dm-analysis/src/typed_body.rs`: borrowed visit of already-issued syntax, no parse.
- `typed_body_lexical.rs`: lexical binding analysis with explicit semantic gaps.
- `typed_body_selected_bound.rs`: borrowed compiler-selected reference coordinates/provenance, not an admission certificate.
- `tools/dmb/crates/dmbc/src/runner_analysis.rs`, `query_db.rs`, `analysis_export.rs`, `engine_catalog.rs`.
- `tools/analyze/src/sem/mod.rs`: owns dreammaker ObjectTree and exposes its AST via ProcBody. Existing facade is not representation-independent despite its conceptual small surface.
- `tools/analyze/src/sem/body_facts.rs`, `walk_cache.rs`, `tools/analyze/src/incr.rs`.
- `tools/analyze/src/lints/untyped_refs.rs`: proposed first semantic consumer; relies on stored_refs Walker, type classification and whole-tree value analysis. A toy assignment scan is not parity.

## Next concrete steps

1. Lease and inspect a current compiler lane. Bring only our untracked files across. Coordinate with current compiler changes through existing repository mechanisms; keep tracing intact.
2. Obtain and verify SpacemanDMM source at `0290db5c752fa292f9824521515b603a2afd11dc` (suite-1.11), matching `tools/analyze/vendor/README.md`. Preserve attribution/license. The previous session found only `~/SpacemanDMM/dreamchecker.exe` and suite checksums, not checker source. Do not substitute an unpinned latest checker.
3. Enumerate checker diagnostic families, inference passes, configuration/suppression rules and source-position requirements. Commit an explicit coverage matrix. Audit native syntax/builtin gaps needed by those passes.
4. Build the first vertical slice: shared native body/resolution facts consumed by compilation, Analyze `untyped`, and one real checker diagnostic family. Demonstrate borrowed same-memory ownership and one computation, not serialization/reparse through JSON.
5. Add reference parity fixtures with seeded cross-file errors before switching consumers. Reproduce fixed-commit cold/warm/edit CPU, wall and memory baselines under machine slots.
6. Progress through the plan's remaining stages: native analysis facade; per-proc facts/retractable indexes; SCC inference; checker port; unified host/clients; production cutover and removal of duplicate models.

Important correctness constraints:

- Record negative lookups and actual consulted dependencies, not one whole-tree digest per check.
- Equal storage does not establish equal issuance identity. A recent shared-binding-table bug conflated them; retain its fix.
- Generation moves source R to R+1 transactionally. Do not mutate a snapshot while checking it.
- Retract old facts on edits/deletions; shrinking summaries and recursive graph changes matter.
- One bounded executor and one total memory ledger; no nested worker oversubscription or automatic duplicate standalone analyzer on timeout.
- Compiler acceptance and checker warnings remain separate policies over shared facts.
- Keep standalone pinned tools as independent parity oracles during migration. Zero diagnostics on master is insufficient coverage.

## Historical measurements and traps

These are prior Claude measurements to reproduce, not new benchmarks from our implementation:

- DreamChecker: about 386 s wall / 380 s CPU, largely serial checking; sharing only its parse is insufficient.
- Analyze one-body edit: 18-27 s because semantic passes revisit about 106k bodies. A resident wrapper saved an estimated 1-4 s only.
- Native body edits: approximately 4.5-6 s. Quiet cold game build: 74.5 s, including 23.1 s cache writing after output installation.
- Compiler total memory remains several GB; consolidation alone does not prove a 1 GB target.
- Per-call detail timers once emitted roughly 30k lines and distorted the measured bottleneck. Aggregate instrumentation.
- An apparent second-worktree memory regression was caused by comparing different source commits; use identical trees.
- Reverse-dependent Rust checks had a duplicated Cargo path bug and bounced compiler/detail-summary. Check whether fixed on current master.
- compiler/async-cache-flush was unvalidated at handoff in the logs; do not count background write deferral as eliminating CPU work.

Targets in the plan are unproven engineering objectives: unchanged all-three <=1 s after admission; typical edit <=7 s and <=2 s overhead versus compile-only; cold combined >=2x faster wall and >=40% lower CPU; compile-only median regression <=5%. Report measured limitations honestly.

## Repo safety and validation

Use machine slots, below-normal priority, per-worktree targets and prescribed E: caches. Never delete locks or use git checkout/stash/reset/restore/cherry-pick. No raised baselines or annotations to hide new debt. Run only focused DM tests during development, never dm-test. Follow native/DreamMaker cross-check and equivalence gates. Do not merge/push except through the current authorized repository workflow. Preserve unrelated changes and report exactly what is implemented versus planned.
