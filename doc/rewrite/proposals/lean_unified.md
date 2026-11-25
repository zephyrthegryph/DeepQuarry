# Lean unified toolchain: analyze, DreamChecker and dmbc

Status: in progress (2026-11-25). S1 and S2 done; S3 under way (see Progress). Replaces the Codex branch `compiler/unified-analysis` (backed up as
`backup/unified-analysis-20261125`), which rewrote dmbc's front end and never ran on the whole project.
Builds on the measurements in `one_frontend.md` §9-§11.

## Decision

Keep the two parsers master already has, each for what it is good at, and remove everything duplicated around them:

- `dreammaker` (vendored suite-1.11 in `tools/analyze/vendor/`) stays the one parse for analysis: analyze's lints, `gen`, and
  DreamChecker all read the same `ObjectTree`. DreamChecker's checks already walk that AST, so they run unchanged.
- dmbc keeps its own front end for the byte-exact compile. It is not rewritten.

`one_frontend.md` §9 measured why: moving analysis onto dmbc's model saves at most about 790 MB and means rewriting every
semantic walk and every checker pass; dmbc cannot use dreammaker's tree because its incrementality needs its receipts.
DreamChecker's 386 s is its serial checking, not its parse. The Codex branch confirmed the cost of the other direction.

## Stages (each one lane, each proven before the next)

| Stage | Deliverable | Proof |
|---|---|---|
| S1 | Vendor `dreamchecker` (same pin) beside `dreammaker`; `analyze dreamchecker` runs it on analyze's parse | Output byte-identical to the standalone binary on master and on seeded trees |
| S2 | Parallel checking: per-proc work split across threads, results merged in the standalone's order | Same output; wall time and peak memory against 386 s / 1.05 GB |
| S3 | Incremental semantic lints and checker results per proc: a body edit re-checks the procs whose inputs changed | `analyze parity --all`, ratchet parity; one-file edit wall against 18-27 s |
| S4 | Resident `analyze serve` per worktree (design in `one_frontend.md` §11), thin client, same CLI and exit codes | Byte-identical answers to standalone for check, gen, baseline, dreamchecker |
| S5 | Shared file and text layer with dmbc; fold the server into the dmbc daemon process | `dmb-equiv`, `shared_store_equiv`, ratchet parity; combined memory |
| Cutover | Gates use the combined request; standalone DreamChecker binary kept as the CI oracle | Sustained parity and measured gains |

DreamChecker stays off as a gate until the user turns it back on; S1-S2 make it cheap enough to run.

## Rules

- No second parser, no rewritten dmbc front end, no new memory-accounting framework.
- The standalone tools stay as independent oracles until each stage's parity holds.
- Measure on fixed commits under machine slots; report wall, CPU and peak working set.

## Progress

Measured on master `6910cfdade` in `pool-c1`, below-normal priority, one run each.

| What | Before | Now |
|---|---|---|
| DreamChecker, whole tree | 366 s, 1.18 GB (standalone binary) | 12 s, 1.0 GB (`analyze dreamchecker`), same diagnostics |
| `analyze check`, nothing changed | about 100 s (the unused-ALLOW recheck misread a real problem as stale caches and wiped them every run) | 0.6-1 s |
| `analyze check`, one-line body edit | 23-27 s | about 10 s |

- S1: `analyze dreamchecker` runs the vendored checker on analyze's own parse; the build's DreamChecker step uses it
  (`DQ_DREAMCHECKER_STANDALONE=1` keeps the binary). `tools/analyze/tests/dreamchecker_parity.rs` compares it with the binary.
- S2: DreamChecker's time was its call-tree pass (243 s), not its body checks (under 1 s): each search queued a proc once per caller.
  Fixed, and the body and call-tree passes run on several threads.
- S3 so far: `value_procs` is a worklist fixpoint (it also kept losing narrowing from definitions that had lost the title, so its
  answer depended on definition order); model call sites and `requirement_bool`'s text rules are cached per file.
  Left on a body edit: `value_procs`' first pass (about 8 s), `sem/handlers` and `gen/deps` (walk-cache decode and context digest).
