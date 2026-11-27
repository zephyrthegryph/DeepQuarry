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

### Step 3, first part (2026-11-26): parallel and remembered conversion

The object tree conversion (`analysis_tree::build_tree_in`) now runs on every core and remembers its work between requests:

- Bodies, declarations (initializers, parameters, locations) and types convert in parallel (rayon, one location mapper per worker, the files
  registered up front in include order so a worker maps a path to its id with a read). Output is byte-identical to the serial build
  (`dreamchecker` and `check --raw` compared with dreammaker's model).
- Each converted body and each converted declaration is an `incr::keyed_by` entry (`tree-bodies`, `tree-declarations`), so inside the daemon it
  lives in the analysis store (and on disk standalone). The key is what decides the result: the expanded text, the item's place in its file, the
  file's path and bytes, and a digest of the file-id table. An edit converts the items of the edited file again; the rest are read back.
- The daemon remembers the whole encoded tree (`analysis_model`) only for a checker request (encoding it costs about a second and 234 MB).

Measured (single runs, shared machine, one daemon, `check --raw`; dreammaker's own model beside it):

| What | Before | Now | dreammaker |
|---|---|---|---|
| model, cold, standalone (`analyze dreamchecker`) | 54.4 s (tree 45.3 s) | 18-19 s (front end 6.9 s, tree 9.5 s) | 7.6 s |
| model, cold, in the daemon | 49-64 s | 22 s (front end 11 s, tree 10 s) | |
| one-line body edit, whole `check --raw` through the daemon | 67-72 s | 10.8-11.6 s (model 4.5-5.0 s: front end 2.5-2.9 s, tree 1.5 s) | 5.3-9.7 s |
| nothing changed | 2.3 s | 1.9 s | 2.3 s |

`check --raw` output after the edit and after reverting it is byte-identical to dreammaker's. Left for the cutover: the cold model is about 2.5-3x
dreammaker's (the front end is 7-11 s of it and is the compiler's own cost); an edit still pays the compiler front end (about 2.5 s) plus the
tree-wide steps (spelling, matching, builder, finish: about 1 s), where dreammaker's model store splices one file's patch in well under a second.
Cold `gen` under dmbc (first model before the generated files exist) is not done. Two differences the test lane reported: columns (dmbc places an
`if(1)` one column right of dreammaker; the real tree has no DreamChecker diagnostic, so no printed output changes today) and a missing included
file (dreammaker reports an error and continues, dmbc refuses the whole model, as the compile does; no tree on master has one).

## Workstream 2a LINTS: dq-analyze on dmbc's own tree (2026-11-27)

Branch `compiler/lints-native-tree`. Goal: the semantic model (`sem/`), the `dm/` helpers and every lint and generator read dmbc's front end
(`dm_tree::frontend::ColdFrontend`: the semantic tree, the declaration occurrences, the typed bodies, the site map) through borrowed views,
with no dreammaker-shaped intermediate. Then `analysis_tree.rs`, `analysis_bridge.rs`, the parity converter, `DQ_ANALYZE_PARSE` and analyze's
dependency on dreammaker's parser go. `dreamchecker.rs` keeps the converter until workstream 2b ports the checker.

### Inventory (what reads dreammaker shapes, and what for)

31 files name `dreammaker::` (15.9 k lines). About 60 more reach the shapes through `sem`: `Sem::objtree`, `ty()`, `proc_ref()`,
`proc_body()` and the `sem::ast` walkers. Grouped by what they need:

| Group | Files | Needs from the tree | Port |
|---|---|---|---|
| Model hub | `sem/mod.rs` (`Sem`, `VarSig`, `ProcBody`, `rel`/`file_of`/`location_key`/`def_at`) | types and parents; own vars (declared type, static/const/tmp, initializer, line); procs (definition chain, verb or proc, parameters, body, line); the file of a location | rewrite on the view; the dreammaker parse pipeline is deleted |
| Persistence of dreammaker's tree | `sem/model_store.rs`, `sem/incremental.rs` (shape digest), `sem/body_facts.rs` (keyed by `location_key`), `host.rs` reset, `cli.rs` decode probes, `frontend/mod.rs` `DreamMakerFrontend` | nothing: they exist because dreammaker's parse is slow and unretained | deleted; per-file and per-member keys come from the front end (`SourceFile` text, `MemberNode::content`) |
| Shared walkers | `sem/ast.rs` (`walk_expr`, `walk_block`, `stmt_exprs`, `stmt_blocks`, `as_call`, `as_ident`, `strip_parens`, `calls_in`) | pre-order expression and statement walks, each expression with its statement's line | rewritten first, over `dm_syntax` |
| Body interpreters and write scanners | `sem/reads.rs` (3.2 k), `dm/value_procs.rs` (1.5 k), `gens/auto_tracked.rs`, `sem/globals.rs`, `sem/checks.rs`, `lints/stored_refs.rs` | receiver chains (`term` plus `follow[..n]`); call forms (bare, method, `..()`, `global.f()`, `call()()`); `new`, `list()`; locals from `var`/`for`; literals (Int vs Float, decoded strings); statement lines. `checks.rs` also reads columns | large; the chain view below replaces every `follow` slice |
| Pattern lints | `lints/{base_vars,untyped_refs,untyped_member,image_dir_after_build,rel_write_undeclared,weak_raw_read,setter_publishes,player_link}.rs`, `base_vars_dead.rs`, `sem/{layering,ctor_args,actor_tests,oracle,procs,ui_windows}.rs` | one shape each: an empty `list()` initializer, `nameof(x)`, `key = x` at statement level, `set SpacemanDMM_return_type`, a string constant up the type chain | small each |
| Codemod | `codemod/mod.rs` | the start (line, column) of a bare call in the source file; the text itself is rescanned | small, needs columns |
| DreamChecker | `dreamchecker.rs` | a real dreammaker `ObjectTree` and `Context` | workstream 2b |

Precision: every lint reads lines only, except `sem/checks.rs` (two position rules) and the codemod (the call's start column). `FileId` is used
only to map a location to its repo-relative path. No lint reads docs or body ranges. `weak_raw_read` keys nodes by address, so the view must
hand out the same node every time (it borrows; it never rebuilds).

### The view (`dq_analyze::model`)

dq-analyze depends on `dm-tree`, `dm-syntax` and `dm-ir`, for their types only. dmbc still builds the front end, so there is no cycle. The
registered provider returns the front end itself (`FrontendRevision`), from the daemon's retained session or built cold; nothing is converted.

- `Model { rev: FrontendRevision, bodies, types, files }`.
  - `bodies[member]` is the compiler's own typed body (`Arc<StatementBody>` from `BodyArena`), parsed once per revision.
  - `types` maps a path to its `TypeId` and holds the children.
  - `files` maps a `dm_tree::FileId` to the repo-relative path and a content key.
  - Nothing in it copies a body, an initializer or a declaration: the handles borrow from the revision.
- Handles, all `Copy` and borrowed:
  - `Ty<'m>`: path, parent, own vars, own procs, `var(name)` and `proc(name)` up the chain.
  - `Proc<'m>`: owner, name, verb or proc, definition ordinal and `parent_proc()`, parameters (`dm_ir::Parameter`, the default as a parsed
    `dm_syntax::Expr`), `body() -> Option<&[dm_syntax::Statement]>`, `site()`.
  - `Var<'m>`: declared type text, flags from `DeclarationMeaning::flags`, the initializer as a parsed `Expr`, the resolved constant from
    `resolved_constant`, `site()`.
- `Site(u32)` is an expanded-text offset. Lines and columns are computed when asked (`Model::line(site)`, one `SiteMapper` per worker), not for
  every node. The converter's 6.6 M location lookups were most of its cost; lints ask for a line only for what they report or key.
- Where the tree lacks something a lint reads, dm-tree gains it rather than analyze re-deriving it:
  - each member's declaration site (the occurrence the converter recovers today by matching spellings);
  - the initializer and parameter defaults as parsed expressions (the semantic tree keeps them lowered to `SymbolicExpression`);
  - the SpacemanDMM flags (`SpacemanDMM_private`, `_protected`, `_final`) as declaration flags.
- Expressions: `model::expr` gives a borrowed chain view, `Chain { root: &Expr, hops: [Hop] }` with `Hop::Field`, `Hop::Call`, `Hop::Index` and
  `Hop::Static`, peeled once from the outermost `Member`/`Call`/`Index` node.
  - Code written as "term, then follows" ports as "root, then hops", with `hops[..n]` slices and no rebuilt prefix.
  - The call forms dmbc spells as calls (`new`, `list`, `locate`, `input`, `pick`, `..()`, `global.f()`, `call()()`, `.proc/x`) are classified
    once there, by the rules `analysis_bridge.rs` encodes today.
  - Literals decode through `dm_syntax::decode_literal`, which keeps Int vs Float.
  - The walkers visit a chain as one unit, as dreammaker visits a `Base`, so nested `Member`/`Call` nodes are not counted twice.
- Identities the ENGINE workstream keys queries on:
  - a proc is `(owner path, name, definition ordinal)`, a file is its repo-relative path;
  - a body's content key is the hash of its expanded text, its file key and its place in the file (the key the converter's `tree-bodies`
    entries use today);
  - a declaration's key is `MemberNode::content` plus its site.

### Plan and landing

1. Build the view beside the converted tree under `DQ_ANALYZE_PARSE=dmbc`, with a parity check against the converted `ObjectTree`: types,
   parents, own vars and procs in the same order, declared types, flags, every declaration's file and line, and parameters. The converted tree
   is the oracle for what each lint will read. The dm-tree additions land with dmbc unit tests.
2. Port in groups: `sem::ast` first, then the hub, the interpreters, the pattern lints and the codemod. Each group is proven byte-identical
   against master under `DQ_ANALYZE_PARSE=dmbc` (`check --raw --no-cache` and `gen`, on master and on the seeded trees).
3. Cutover: the view becomes the only model. The converter, `DQ_ANALYZE_PARSE`, `model_store`, the dreammaker parse pipeline and the tests'
   `set_var` go.

A ported group cannot run on dreammaker's default parse. Building the front end beside it on the default path would make master slower: the
front end alone is 7-11 s cold. So the groups are proven and pushed on the branch, with master merged into it often, and they land with the
cutover, measured against master's cold, one-line-edit and no-op times. What lands before the cutover is what is useful on its own: the dm-tree
additions, the view and its parity check, and the cold `gen` fix.

Oracle on the branch base (820811dfc9, `DQ_ANALYZE_DAEMON=0`, shared machine, single runs): `gen` cold 4 min 40 s (model 22 s), 416 generated
files; `check --raw --no-cache` 1606 lines, model 6.7-9.5 s per build.
