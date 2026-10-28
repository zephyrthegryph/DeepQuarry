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

## 9. Measured: what the merge would share (2026-10-28, master 3db4c46d2f)

Same tree, cold caches. The analyze numbers are a sampling heap profile (every allocation of 1 MiB or more, 1 in 64 of 4 KiB to
1 MiB, 1 in 65,536 of smaller ones, attributed to the first dreammaker or dq_analyze frames) taken at the peak; dhat was too slow
(two runs hit the 30 minute cap). The dmbc numbers are the allocation-sites probe after one game compile. Sampled figures are
estimates, not exact bytes.

| Run | Wall | Peak | Notes |
|---|---|---|---|
| `analyze check --no-cache` (cold) | 47.7 s | 3,675 MB working set | sampled heap at peak 2,126 MB; the rest is allocator overhead and untracked small objects |
| text-only lint (tree loaded, no model) | 12 s | 1,348 MB | |
| `analyze sem reads` | 10 s | 1,410 MB | |
| `analyze frontend-diff` | 9.4 s | 552 MB | |
| dmbc game compile (one session) | n/a | 4,108 MB private, 2,377 MB requested-live | 2,087 MB sampled |

analyze resident model by owner (MB, sampled at peak):

| Owner | MB |
|---|---|
| dreammaker proc-body AST (expression, group, statement, prefab) | about 490 |
| dreammaker object tree (vars, procs, docs) | about 236 |
| dreammaker lexer and constants | about 62 |
| analyze text layer: compiled regex patterns | about 340 |
| analyze text layer: comment-stripped text | about 180 |
| analyze text layer: tree load | about 83 |
| analyze lint indexes (stored_refs 98, value_procs 91, dx 54, schema 34, ownership 31, other) | about 330 |
| sem walks and Sem::build | about 230 |

dmbc frontend owners on the same tree (MB):

| Owner | MB |
|---|---|
| dm_tree (declarations, normalization, metadata, adapter, shapes, indexes) | 811 |
| dm_preprocess (expansion 109, prepared source 76, joined text 62, region memo 56, environment 50, trace arena 45, source text 35, directives 28) | 479 |
| source bytes held by the input layer | 80 |
| dm_ir symbols | 40 |
| frontend total | about 1,410 |
| session memo machinery (dm_session: receipt pool 234, artifact stores 177) | 419 |
| lowering, ABI and policy (dmbc) | 264 |
| codegen | 22 |

Pairs (could one serve the other's consumers):

| Pair | analyze / dreammaker | dmbc | Verdict |
|---|---|---|---|
| source text | text layer about 263 MB (stripped text and tree load) | prepared comment-aware source about 220 MB | shareable: 100-260 MB estimated (an inference, not measured); the regex patterns (340 MB) stay |
| preprocessor | streams tokens, no resident region store | 479 MB incremental region and expansion state | not shareable: dmbc's is incremental state analyze does not use |
| parse and AST | full proc-body AST about 490 MB, needed by the sem walks and DreamChecker | no persistent AST; typed statements parsed on demand into dm_syntax types | dmbc cannot serve dreammaker consumers without rewriting every sem walk and DreamChecker check |
| object tree and model | about 236 MB | 811 MB (adds per-owner receipts, contributions and dependency tracking for incrementality) | the small Sem surface (ty, var_decl, proc_ref, proc_body, owner_candidates, def_at) could be implemented on dmbc's model; proc_body brings the AST problem back |
| symbols | string interning inside the maps | 40 MB | not worth sharing |

Parser comparison: dreammaker holds about 790 MB (AST, tree, lexer); it patches one file in about 70 ms but a define or macro
change is a full parse; it serves analyze (about 60 lints, only the sem family needs the parse) and DreamChecker. dmbc's frontend
holds about 1,410 MB including its preprocessor and incremental state; a body edit costs about 0.5 s of frontend; it serves the
byte-exact compile. Neither can replace the other's consumers cheaply.

Recommendation: keep both parsers for now; share what is shareable (the daemon, the file and text layer) and move consumers onto
dmbc's model only where the surface is small. DreamChecker's 386 s is its serial checks, not its parse, so a parser choice does
not remove it. Replacing analyze's dreammaker AST and tree with dmbc's would save at most about 790 MB at the price of the
rewrite above; replacing dmbc's tree with dreammaker's would drop 811 MB toward 236 MB but is not feasible (dmbc's
incrementality needs the receipts).

## 10. Revised phase plan

Supersedes section 4 where they differ; each phase is its own lane and proves itself.

- P1: parallel DreamChecker checks on the shared dreammaker model (the analyze process runs DreamChecker over its own loaded tree,
  with the checks split across threads). Blocked on the user's download OK for the dreamchecker crate. Exit measure: wall, peak RSS
  against the 386 s / 1.05 GB standalone, diagnostics byte-identical on master and three seeded trees.
- P2: the dmbc daemon hosts analyze and the dreammaker model as one resident process; `analyze` becomes a thin client. Saves the
  per-gate model load (7-8 s parse, 3.7 GB transient) and the second resident process. Proof: ratchet parity, DreamChecker parity.
- P3: a shared file and text layer (estimated 100-260 MB): one read and one comment-stripped view of each file for dmbc's prepared
  source and analyze's text lints. Proof: `dmb-equiv`, `shared_store_equiv`, ratchet parity.
- P4 (optional, long term): move the sem walks and checks onto dmbc's model by implementing analyze's Sem surface there, and give
  proc bodies a dmbc-side AST the walks can read. Only after P1-P3 land and only if the memory or maintenance case holds.

## 11. P2 design: a resident analyze per worktree

Goal: `analyze check`, `gen`, `baseline` and `parity` stop paying process start, tree load and the 7-8 s model parse on every
call (cold 17-53 s, 3.5-3.7 GB transient), by keeping the loaded `Tree`, the `Sem` model and the incremental stores
(`incr.rs`, `sem/incremental.rs`) in one resident process. Outputs, exit codes and files written stay byte-identical to the
standalone run; the standalone run stays the fallback.

**Where it lives (decision wanted).** Two ways to read "the dmbc daemon hosts analyze":

- A, link analyze into dmbc's daemon process. One process, one memory budget, and P3 can later share the file layer in memory.
  Cost: the daemon's identity is its executable hash, and a dmbc daemon is replaced when its image changes. Every lint edit would
  then rebuild dmbc and evict a 4-5 GB compile session; dmbc also gains the vendored dreammaker and analyze build time.
- B (recommended for P2), a sibling `analyze serve` process that reuses the dmbc daemon's conventions, not its address space:
  endpoint descriptor and namespace (`an-<hash of worktree root>`), the `live/<pid>.json` registry with heartbeat, retire
  files, idle exit, the machine-wide admission rules, and the same lifecycle log plus the per-namespace `stderr.log` that
  `crash_trace.rs` writes. A lint change replaces only this daemon. The "one process" end state is a P3/P4 question
  (shared file layer, one parser) and can fold B into A later without changing the client protocol.

**Protocol.** The `analyze` binary keeps its CLI. For `check`, `baseline`, `parity`, `gen` and `timing` it connects to
`an-<root hash>`, sends `Request { argv, cwd, root, engine_hash, env subset }` and streams back stdout, stderr and the exit
code verbatim. The daemon refuses a request whose `root` is not its own worktree, so a daemon never touches another tree.
Writes (`gen`, `baseline --update`, codemods) are done by the daemon inside its root with the same code path; the client prints
what the standalone run would print. An `engine_hash` that differs from the daemon's (the analyze binary was rebuilt) makes the
daemon drain and exit and the client run standalone for that call; the next call starts a fresh daemon.

**Cache and invalidation on edit.** Correctness never depends on a file watcher. Each request re-validates exactly like
today's cold path: walk the tracked directories, compare `(size, mtime)` and fall back to the content hash (`tree.rs`), keep the
`Tree` entries whose hash is unchanged, reload the rest, then let the existing per-file result cache, whole-tree memo (keyed by
the combined hash) and the semantic record's footprint rules decide what to recompute. The resident process holds those caches in
memory and still persists them to `data/analyze-cache/`, which remains the source of truth, so a restart or the standalone
fallback sees the same state. A changed `deepquarry.dme`, `#define` file or `lint_scopes.toml` takes the same full-model path as
today. Any doubt is a miss. Expected steady state: the tree walk (tens of ms for ~5,800 files) plus the lints whose inputs
changed, and the model parse only when the footprint rule demands it (about 8 s, kept resident afterwards).

**Memory cap.** The daemon counts in the machine's daemon table and obeys the dmbc rules: it does not start with less than 12 GB
of free RAM, and it is the first to shed. Tiers: (1) idle 2 minutes: drop the regex caches and decoded text views, keep the
tree hashes and the semantic record (about 0.4 GB resident); (2) idle 10 minutes or memory pressure: drop the full `Sem` model
(about 2.1 GB sampled, the largest piece); (3) idle 60 minutes: exit. The hard cap is 4.5 GB resident; a request that would
exceed it runs standalone. A shed model is rebuilt on demand exactly as the cold path builds it.

**When the daemon is busy or absent.** One request runs at a time per worktree. A second request waits up to 10 s, then runs
standalone in its own process (current behaviour, current memory), so a gate is never blocked by another agent's long run.
Connection refused, a handshake mismatch, a protocol error or a daemon that dies mid-request (the client sees the closed pipe)
all end in a standalone rerun of the whole command, never a partial result; the dead daemon's namespace log says why.
`DQ_ANALYZE_DAEMON=0` forces standalone; the default is on only after the parity gate below has a clean landing record.
Nothing is killed by hand: retirement is the registry's retire file.

**Proof, per sub-lane.** P2a: server, client, `check` only: for the whole ratchet set and for three one-file edits (body edit,
declaration edit, `#define` edit) the daemon answer is byte-identical to the standalone run (stdout, stderr, exit code, files
written), with `analyze parity --all` clean. P2b: `gen`/`baseline`/codemods through the daemon, same proof. P2c: tiered shed and
the 4.5 GB cap, tested by forcing each tier and requiring the next request to match standalone. Exit measure (all sub-lanes):
cold-start wall, warm no-change wall, warm one-file-edit wall, resident RSS per tier, and free RAM, against today's 17-53 s and
3.5 GB per call.

**Not in P2.** DreamChecker (P1), moving lints onto dmbc's model, any change to `tools/dmb`.
