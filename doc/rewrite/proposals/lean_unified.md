# Lean unified toolchain: analyze, DreamChecker and dmbc

Status: in progress (2026-11-25). S1-S4 done; S5 dropped; "One program" step 1 done, steps 2-3 next. Replaces the Codex branch `compiler/unified-analysis` (backed up as
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
| S5 | Dropped: sharing the text layer saves at most 64 MB (the DM source); "one program" below replaces it | `dmb-equiv`, `shared_store_equiv`, ratchet parity; combined memory |
| Cutover | Gates use the combined request; standalone DreamChecker binary kept as the CI oracle | Sustained parity and measured gains |

DreamChecker stays off as a gate until the user turns it back on; S1-S2 make it cheap enough to run.

## Rules

- No second parser, no rewritten dmbc front end, no new memory-accounting framework.
- The standalone tools stay as independent oracles until each stage's parity holds.
- Measure on fixed commits under machine slots; report wall, CPU and peak working set.

## Progress

Measured on master in `pool-c1`, below-normal priority, a shared machine (other work ran beside it); single runs.

| What | Before (2026-11-25 start) | Now |
|---|---|---|
| DreamChecker, whole tree | 366 s, 355 CPU s, 1.18 GB (standalone binary) | 6.7 s, 12 CPU s, 1.0 GB (`analyze dreamchecker`), same diagnostics |
| `analyze check`, nothing changed | about 100 s (the unused-ALLOW recheck misread a real problem as stale caches and wiped them every run) | 0.6 s, 1.2 CPU s, 0.3 GB |
| `analyze check`, one-line body edit | 23-27 s, about 35 CPU s | about 5 s, 28 CPU s, 3.3 GB peak |

- S1: `analyze dreamchecker` runs the vendored checker on analyze's own parse; the build's DreamChecker step uses it
  (`DQ_DREAMCHECKER_STANDALONE=1` keeps the binary). `tools/analyze/tests/dreamchecker_parity.rs` compares it with the binary.
- S2: DreamChecker's time was its call-tree pass (243 s), not its body checks (under 1 s). Each search now queues a proc once, keeps parent
  links instead of copied stacks, and a should_not_sleep proc whose same-context calls cannot reach a reportable sleep is not searched;
  the searches and the body pass run on several threads. The call-tree diagnostics come in source order (upstream's order is seeded per process).
- S3: `value_procs` is a worklist fixpoint kept between runs (only the definitions an edit affects are evaluated again; it also no longer
  loses narrowing from definitions that lost the title, which made its answer depend on order); the semantic record re-collects only edited
  files; model call sites, `requirement_bool`, `read_back` and `lifeforms`' text rules are cached per file.
  Left on a body edit: the reads walks behind `sem/handlers`, `gen/deps` and `gen/auto-tracked` (shared by `untracked_inputs`,
  `setter_publishes`, `sem/handlers`), the model load, and walk-cache decoding: about 28 CPU s spread over the cores.
- S4: first a one-shot warm worker per worktree; replaced by the daemon below (one resident program, not two).

## One program (2026-11-25, after S4)

The user's direction: analyze, DreamChecker and dmbc are one program on one parse. The "keep two parsers" decision above is
superseded. Three steps:

1. One program (done): the analysis engine is a library of the compiler. `dmbc analyze` runs it; the old `analyze` path is the
   compiler under that name; the compiler's daemon serves analysis requests beside compiles, with the read-ahead model shed on idle
   or low memory. analyze's process globals became per request: output and environment through `tools/analyze/hostio`, run
   statics through `RunCell` and `host::reset_run_state`. Measured on one-line body edits: hosted 4.5-6.0 s, in the client
   4.6-6.1 s (the read-ahead saves the 0.8 s model read; the lint work itself is the rest), output byte-identical every time.
   A lint edit now rebuilds the compiler (minutes, not 10 s): `DQ_ANALYZE_STANDALONE=1` keeps the separate binary for that loop.
2. One parse: the analysis passes and DreamChecker read a tree built from dmbc's front end (its typed bodies gain typed literals,
   string parts and the special call forms), then dreammaker's parser is deleted. Proof: every lint, `gen` and DreamChecker output
   identical on master and seeded trees.
3. One incremental engine: per-proc analysis results in dmbc's query store; analyze's own caches go.

### The converted tree and its intended differences (2026-11-26)

`dmbc analysis-parity --tree` compares the object tree built from dmbc's front end (`dmbc::analysis_tree`) with dreammaker's under one
preprocessor environment; `DQ_ANALYZE_PARSE=dmbc` makes `dmbc analyze` (check, gen, dreamchecker) take its model from it
(`dq_analyze::sem::register_parse_provider`, its own `data/analyze-cache-dmbc` and gen stamp). For analysis the front end is built with
`SPACEMAN_DMM` defined, as SpacemanDMM tools read the tree. Differences kept on purpose, because dmbc follows BYOND:

- Empty call arguments (`list(, a = b)`, `f(a, , b)`): the analysis conversion drops them, as dreammaker does (dmbc's own typed body keeps a
  `null` there, as BYOND does; the model is dreammaker's shape, so no lint sees a difference).
- An absolute path in a parameter list (`proc/f(mob/M, /datum/x/A)`) declares the type `/datum/x/A` and is no parameter (BYOND 516
  compile oracle); dreammaker reads it as a parameter. The one site in the tree (`/datum/viral_trait/heal/proc/Heal`) was a typo and is fixed.
- BYOND constants (`WAVE_SIDEWAYS`, `NORTH`) are dmbc predefines, so they arrive as integers where dreammaker sees builtin names
  (DreamChecker's filter checks then see `Int(1)`).
- Preprocessor warnings (macro redefined / undefined) are dmbc's own diagnostics, not forwarded into DreamChecker's stream.
- File paths are canonical (`code/tests/benchmarks/x.dm`), not as an include spelled them (`code/tests/unit_tests\..\benchmarks`).
- Docs and proc body ranges are not built: dq-analyze and DreamChecker read neither (dq-analyze drops body ranges, nothing reads
  `docs`), so `analysis_docs.rs` is gone and the parity compares neither.
- Hint-level diagnostics (the 11 `///` after `#define` hints) are not emitted; hints are never printed or counted among the diagnostics.

### Step 2 result (2026-11-26): parity proved, the switch not made

`dmbc analysis-parity --tree` on master: TREE PARITY 1168032 of 1168032 (100.00%); CONVERTER PARITY (bodies, spelling normalized) 105882 of 105882 (100.00%),
0 classified differences. Four source sites were behind the last gaps and are fixed: the absolute
parameter path above, a `\` line continuation after an `if` (the statement's line), and nested macro expansions (a function-like macro
using other macros) whose invocation spans were read as source positions, which put the first arguments of an `animate()` call on the
wrong line and made `tracked/outside_setter` report a named argument (`dm-tree` `debug_site_column` now keeps only the invocations whose
name is in the statement's source).

Outputs on master and on two seeded trees (a body edit, a new var), `DQ_ANALYZE_PARSE=dmbc` against the default:
`analyze check --raw` byte-identical (0 differing lines), `gen` identical (warm tree, 409 files), `dreamchecker --json`: the printed
diagnostics identical, only the unprinted hint count differs (401 vs 390, the `#define` doc hints).

Measured and the reason the toggle is still there: the converted model is 5-10x slower than dreammaker's parse. Cold, in one process:
dreammaker parse 7.6 s; dmbc front end 8-11 s plus the object tree 40-45 s (6.6 M location lookups 18-21 s, the rest body and
initializer conversion, single-threaded) = 49-64 s. A one-line body edit through the daemon: 67-72 s `check` against about 5 s, because the
daemon remembers a conversion only for unchanged inputs and an edit converts the whole tree again. Making it the only path therefore needs
per-file (per-proc) conversion results kept between requests and a parallel conversion: step 3's engine. Until then `DQ_ANALYZE_PARSE=dmbc`
stays opt-in and dreammaker's parser stays; deleting it also needs dq-analyze's own tests (`tools/analyze/tests`, the lints' fixtures), which
build their models through it, moved onto the compiler's front end.
A cold `analyze gen` under dmbc also needs the front end to accept a tree whose generated files are not there yet (dreammaker only reports
a bad parent type): `gen` now creates empty stubs for the generated includes it finds missing, but `/datum/act/admission_query: invalid parent
type` (its parent comes from a generated file) still refuses the first model.
