# One frontend: analyze, DreamChecker and dmbc on one parse

Status: DRAFT plan. Baselines in section 7 were measured 2026-10-28 on master 10372a2c52.

Finding that changes phase 1: DreamChecker costs 386 s wall at 380 s CPU on one thread and 1.05 GB, while analyze parses and runs every ratchet in 41-53 s. DreamChecker's time is its serial checking passes, not its parse (analyze's whole parse is on the order of 8 s per its README). Sharing the parse removes at most that parse from DreamChecker's 386 s; it does not cut the gate cost by itself. Every number marked MEASURE is filled in by the lane that produces it; nothing
below the "Known today" table is a measurement yet.

## 1. Problem

Three tools parse the same ~5,800 `.dm` files separately, and a gate runs all three:

| Tool | Parser | Resident cost | Where it runs |
|---|---|---|---|
| `tools/analyze` | vendored SpacemanDMM `dreammaker` suite-1.11 (`tools/analyze/vendor/`) | about 3.3 GB | `check_ratchets.sh`, `build.sh gen`/`lint`, gates |
| DreamChecker | SpacemanDMM `dreamchecker` 1.11 binary (`~/SpacemanDMM/dreamchecker.exe`), no incremental mode | whole-tree parse per run; OOM-crashes near 4 GB free | `tools/build/build.ts` (`runDreamChecker`, `-e deepquarry.dme`), `tools/dq_merge_gates.sh` (`DQ_DREAMCHECKER=1 DQ_DREAMCHECKER_AFTER=1 build.sh dm`) |
| dmbc | its own frontend (`tools/dmb`, Salsa-style query store, `QUERY.md`) | about 4.5 GB per session daemon, capped at `DQ_DMBC_MAX_DAEMONS` | compile, `dmbc query` |

DreamChecker is the largest gate cost (626-1397 s per landing cycle). Memory is the binding
constraint on this machine, so the goal is one parse and one resident process, not just fewer minutes.

## 2. End state

One dmbc-hosted daemon per worktree serves compile, `analyze check` lints, `gen`, and DreamChecker
diagnostics from one parsed and lowered model. The `analyze` binary becomes a thin client of that
daemon (same CLI, same output and exit codes). CI keeps DreamMaker and its own DreamChecker job until
equivalence is proven.

## 3. Direction: decide by measurement

Two candidates:

A. analyze's lints move onto dmbc's query model (dmbc's frontend is the single parser).
B. dmbc consumes the dreammaker parse (dreammaker is the single parser).

Facts that bear on it, from the code:

- analyze's semantic layer (`src/sem/`) and DreamChecker both consume dreammaker's `ObjectTree` and
  AST types. The vendored dreammaker already carries a model store (`sem/model_store.rs`), per-file
  patching (`file_patch`/`splice_file`), and lazily decoded proc bodies. DreamChecker's checks walk
  the same AST, so A forces rewriting DreamChecker's ~all analysis passes (type inference,
  unreachable code, proc signature checks) against dmbc's IR; B keeps them as they are.
- dmbc has what analyze lacks: complete-key incremental lowering, a daemon with admission/eviction,
  session identity (`revision`, `source_revision`), and a shared store across worktrees.
- dmbc is not byte-for-byte dreammaker. Its frontend is validated against DreamMaker output
  (`dmb-equiv`, `shared_store_equiv`), not against dreammaker's AST. Any lint that depends on
  dreammaker AST quirks (macro history, `__FILE__` handling, comment positions) can differ.

Decision rule (numbers go in section 7 when measured):

1. Peak RSS of the combined process for each direction on the master tree.
2. Cold wall time and CPU for parse + lints + DreamChecker + compile.
3. Edit-one-file wall time (incremental) for each direction.
4. Parity risk: count of lint/diagnostic differences on master and on the seeded trees.

Provisional lean (to be confirmed or overturned by the numbers): B for the DreamChecker and lint
half, because it reuses two existing consumers of one AST unchanged; then converge the frontends in
the other direction only if dmbc can emit dreammaker-equivalent `ObjectTree` data. State this as a
hypothesis, not a result.

## 4. Phases (each is its own lane and proves itself)

Phase 1: DreamChecker inside analyze (this lane).
- Vendor the `dreamchecker` crate at suite-1.11 commit 0290db5c (same pin as `vendor/README.md`)
  next to `dreammaker`; list changes in `vendor/README.md`.
- `analyze check --dreamchecker`: run its checks on analyze's already-loaded `ObjectTree`, same
  `SpacemanDMM.toml`, same output text and exit codes `build.ts`/`dq_merge_gates.sh` read.
- Proof: diagnostics identical to the standalone binary on master and on 3 seeded-error trees (type
  error; unreachable code or proc-signature warning; pragma-controlled lint), as a test under
  `tools/analyze/tests`.
- Switch `dq_merge_gates.sh`, the prechecker and `build.ts` to the combined run; standalone path
  kept behind an env var (`DQ_DREAMCHECKER_STANDALONE=1`) for comparison. CI untouched.
- Exit measure: wall, peak RSS, CPU, free RAM, combined vs separate.

Phase 2: share the parse across processes. Put the analyze model behind a resident process (the
existing incremental record in `sem/incremental.rs` is the seed) so gates stop re-loading it.
Proof: ratchet parity (`analyze parity --all`), DreamChecker parity from phase 1.

Phase 3: dmbc and the model share inputs. dmbc's preprocessor/region store and analyze's tree read
one file/hash layer (`tools/analyze/src/tree.rs` and dmbc's source projection), so a file is read and
hashed once. Proof: `dmb-equiv`, `shared_store_equiv`.

Phase 4: one parse. Per section 3's decision, either dmbc emits (or lazily builds) the `ObjectTree`
analyze and DreamChecker consume, or analyze lints are rewritten as queries over dmbc's store.
Proof: dmb-equiv, shared_store_equiv, ratchet parity, DreamChecker parity, all on master and seeded
trees. Gate: diagnostics identical, RSS lower than the sum of today's separate processes.

Phase 5: thin client. dmbc daemon serves `analyze check`/`gen`/DreamChecker requests; the analyze
binary forwards over the existing daemon transport. Daemon count stays under
`DQ_DMBC_MAX_DAEMONS`; nothing is killed by hand; CI unchanged.

Phases touching `tools/dmb` wait for `compiler/variant-switch` (answer tables, `query_db.rs`) and
`compiler/macro-repack` (`region_memo`, `MacroExpansion`) to land; coordinate through the
coordinator.

## 5. Costs (estimates to be replaced by MEASURE)

- Phase 1: vendoring one crate, one adapter, one parity test; small. Risk: dreamchecker's entry
  point owns its own `Context`/parse; it must be driven from analyze's tree, possibly requiring
  analyze to keep full proc bodies decoded (analyze stores them as `LazyCode`; DreamChecker will
  decode all of them, so peak RSS during the combined run is above analyze alone). MEASURE.
- Phase 4: the large one. Weeks of work if dmbc must reproduce dreammaker's tree; likely larger if
  lints move to queries.

## 6. Memory it saves (upper bounds from known figures)

Today a gate holds analyze (about 3.3 GB) and DreamChecker (a second whole-tree parse, not
sampled yet) in turn, plus the dmbc daemon (about 4.5 GB). Phase 1 removes DreamChecker's separate
parse; the end state removes the analyze process and one of two parses. Exact savings: MEASURE.

## 7. Measurements

| Run | Wall s | Peak RSS | CPU s | Free RAM before |
|---|---|---|---|---|
| ratchets via analyze (cold cache, `analyze check`, dev-fast binary) | 40.8-53.2 | 3.5-3.7 GB | 359 (parallel) | 19-25 GB |
| DreamChecker alone (`-e deepquarry.dme`, 0 diagnostics) | 385.6 | 1.05 GB | 380 (one thread) | 21.8 GB |
| combined (phase 1) | MEASURE | MEASURE | MEASURE | MEASURE |

## 8. Risks

- Diagnostic drift: DreamChecker run on a patched/lazily decoded tree may order or de-duplicate
  differently. Mitigation: byte comparison of sorted output, plus exit code, in the parity test.
- Memory spike: a single process holding model plus all decoded bodies. Mitigation: measure first;
  fall back to the standalone path via the env var.
- dmbc/dreammaker semantic differences (section 3). Mitigation: equivalence suites per phase.
- Coupling to two active compiler lanes in `tools/dmb`. Mitigation: do not edit their files until they land.
- Single resident process is a single point of failure for gates. Mitigation: standalone fallbacks
  stay available behind env vars until each phase has a clean landing record.
