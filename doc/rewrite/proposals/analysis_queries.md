# Analysis results in dmbc's query store (lean_unified "One program", step 3)

Status: design, 2026-11-26. Not started. Estimates are agent-days, not measurements.

## Lint inputs

- A, per file text (about 45 lint and gen files, `tools/analyze/src/incr.rs:1-28`): facts(file), index, judge(file). Keyed by file
  content, so `source(path)` in `tools/dmb/crates/dmbc/src/query_db.rs:14,18` already feeds them.
- B, per file or type: `sem/decls.rs:258` (CAPABILITIES/STAT scan), `sem/gen.rs:87,196`, gens/*.
- C, per proc: the reads walks (`sem/reads.rs:765-818`) behind about 17 lints. A walk depends on the bodies it entered and the
  var declarations it looked up (`sem/walk_cache.rs:35-40`); everything else is one global `context()` digest (`reads.rs:783-803`).
- D, whole tree: GlobalIndex, WriteIndex (`sem/body_facts.rs`), the value_procs fixpoint (`dm/value_procs.rs`), dx_reactive caps,
  ownership_index.

Today a declaration edit invalidates every walk (the context digest changes). The body-edit cost left is C, D and the model load.

## Keys

New kinds in the session `QueryDb`, versioned by the engine hash, the scopes hash and the engine flavor:

- A/B: `lint_facts(lint, file)` -> `lint_index(lint)` -> `lint_judge(lint, file)`; `lint_tree` for whole-tree lints;
  `sem_decls(file)`, `decl_row(type)`, `annotations(type)`.
- Per proc: `body(owner, name, occurrence)` (position-independent hash), `proc_facts`, `write_index_name(var)`,
  `global_index_entry(g)`.
- Walks: `walk`, `walk_node` (the memo nodes, `reads.rs:626`), `walk_handler`, `proc_result(lint, type, name)`.
- Per type: `type_node`, `var_decl`, `proc_sig`.
- D: `value_proc` per strongly connected component, `reactive_caps(type)`, `ownership(type)`, `gen_reads(type)`.

## Invalidation

- Body edit: `source` changes, then `lint_facts` and `body`. An equal hash stops there (dm-query `lib.rs:9-12`). On a real change,
  `proc_facts` reruns, then only the walks that read the changed body or index entries (`Db::dependants`, `lib.rs:504`).
  Results store lines relative to the proc header and the reporter rebases them, so inserting lines no longer invalidates walks.
- Declaration edit: the front end's splice, bounded by `affected_types()` (`tools/dmb/doc/retained_frontend.md:92`), re-derives
  only the changed `type_node`. Only walks that looked up the changed name or crossed the changed type rerun.
- Directive edit: the front end's own rules (`retained_frontend.md:72-90`).

## Sharing

- An `analysis_results` core in `SharedStore` (`shared_store.rs:46-50`), built like `ObservedArtifactStore`: key bytes, a receipt of
  (dependency, content hash) pairs, an `Arc` value.
- A session adopts a shared value only after replaying its receipt against its own `Db`, so sharing changes memory, never output.
- Persistence goes through the dm-cache records, with a `[cache.analysis]` table in `tools/ci/disk_budget.toml` added first.
- This replaces `tools/analyze/src/shared.rs` and `E:/dq-cache/analyze-cache`.

## Memory (estimates)

- About 1M nodes at 150-250 B each. Clean group A files are bitmap bits, not nodes.
- Walk results are lazy bytes in the shared core, with about 400 MB resident per session (`Db::evict_values` keeps hashes and deps).
- Target: at most 0.6 GB per session on top of the compile session, and 0.3 GB for a second worktree. Today analyze runs 1.0 GB
  steady and 3.3 GB at peak.

## Deletion order

1. `lint-*.bin` and `cache.rs`, once A/B come from the Db.
2. `incr.rs` and `incr-*.bin`.
3. `sem/body_facts.rs`, `body-*.bin`.
4. `sem/walk_cache.rs`, `walks*.bin`.
5. `value-procs.bin`.
6. `sem/model_store.rs`, `sem/incremental.rs` and the model files, after step 2 (one parse) is proven.
7. `shared.rs`, `linetext.bin`, `gen-state.bin`.

A cold standalone path stays for CI and `DQ_ANALYZE_DAEMON=0`, and is the proof baseline.

## Proof

- A cold run and a warm daemon session give byte-identical `check`, `gen` and `dreamchecker` output.
- `DMB_ANALYSIS_VERIFY=1` (through `Db::set_verify`) replaces `DQ_WALK_VERIFY`, `DQ_MODEL_VERIFY` and `DQ_BODY_FACTS`.
- An edit-sequence test asserts both output equality and the recompute counters. Each step also runs after `evict_values`.
  - S0: no edit (nothing recomputed).
  - S1: a comment edit.
  - S2: a body edit that adds a call.
  - S3: 10 lines inserted above many procs (zero walk reruns).
  - S4: a var added to a base type, then removed (output back to S0).
  - S5: a CAPABILITIES edit.
  - S6: a type added, then deleted.
  - S7: a `#define` edit.
  - S8: a file rename.
  - S9: a lint hit added, then fixed (with ALLOW and the baseline).
  - S10: a `lint_scopes.toml` edit.
  - S11: a worktree switch and back.
  - S12: two sessions edited in alternation.
- A seeded random-edit harness, plus a nightly verify run.

## Risks

- An unrecorded read serves a stale result. Keep the coarse `context()` digest as a fallback dependency until each read class is
  proven, and audit `var_decl_unrecorded` (`sem/mod.rs:424`).
- Lines relative to the proc header change what each lint reports: audit every lint.
- Cycles in value_procs and in recursive walks: key by strongly connected component, or keep one query at first.
- One engine-hash version invalidates every store on any analyzer rebuild. Use per-lint versions.

## Order of work (estimated agent-days, about 34 in all)

| # | Step | Days |
|---|---|---|
| 1 | Analysis kinds, scopes input and non-`.dm` sources in `QueryDb` | 1.5 |
| 2 | `incr::facts/keyed/two_phase` backed by the Db when hosted | 3 |
| 3 | Clean bitmap, folded nodes, memory marks | 1 |
| 4 | Shared `analysis_results` core, receipts, leases, disk budget | 3 |
| 5 | Delete `lint-*.bin`, `cache.rs`, `shared.rs` on the hosted path | 1.5 |
| 6 | `body`, `proc_facts`, `write_index_name`, `global_index_entry` | 4 |
| 7 | Walks with recorded reads and relative lines | 5 |
| 8 | Per-type `type_node`, `var_decl`, `proc_sig`, `annotations`; drop the coarse digest | 5 |
| 9 | `lint_index_entry`, `value_proc`, per-type gens | 5 |
| 10 | Delete the model stores (after step 2) | 2 |
| 11 | Random-edit harness and nightly verify | 3 |

Steps 1-5 (about 10 days) bring groups A and B into the Db, with sharing, and delete the old disk caches.
