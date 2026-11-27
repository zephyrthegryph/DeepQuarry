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

### 2a progress (2026-11-27)

Landed on the branch, not on master:

- dm-tree keeps each declaration occurrence's expanded item span (`ColdFrontend::declaration_spans`, indexed by `OccurrenceId`). The spans
  were computed for body indexing and then dropped; analysis reads a declaration's header and site from them, with no spelling matching.
- The dmbc provider hands the front end itself to dq-analyze (`Parsed::native`). `Sem::model()` builds `crate::model::Model` over it on
  first use: types, each type's own members in emission order, member sites. It takes 2.2-5.2 s on the whole tree (53255 types, 321247
  members, 120473 bodies).
- `analyze sem model-parity` (needs `DQ_ANALYZE_PARSE=dmbc`) compares the view with the converted tree.

First parity run, before the view fixes:

| Category | Compared | Differ |
|---|---|---|
| Types present, parents | 53255 | 0 |
| Var declaration lines, flags, value lines | 31394 / 31394 / 198518 | 0 |
| Proc definition counts | 120417 | 0 |
| Proc lines | 120473 | 156 |
| Proc parameters | 120473 | 127 |
| Proc kind | 120417 | 371 |
| Var declared types | 31394 | 508 |
| Var names | 199161 | 643 |
| Var declared | 198518 | 16 |
| Type sites | 49529 | 203 |

The differences, and what each needs:

- Proc parameters (127 -> 4): the variadic `...` tail was missing; the view spells it now. The 4 left, and the 156 proc lines, are procs
  defined in several files (`/datum/__capabilities`, `/mob/set_viewsize`): their definitions come in another order than dreammaker's
  include order, and emission order did not fix it. The next step is to order definitions by the override chain (`MemberNode::previous`).
- Proc kind (371 -> 39): the 332 were builtin global procs, which have no code definition; the parity now skips them.
- Var declared types (508 -> 267): typed lists, `/list` plus `list_element_type`, which the view now joins. The rest are the
  `SpacemanDMM_private`, `_protected` and `_final` flags, which the semantic tree reads as a type path. That needs a dm-tree change: parse
  those three as declaration flags.
- Var names (643) and var declared (16): builtin vars (`AREA_LAYER`, `/atom/layer`, `/world/fps`) that dreammaker's builtin table declares
  and the semantic tree does not hold as members. The view needs the builtin member catalog (the engine seed's intrinsics) to answer
  `var_decl` for them.
- Type sites (203): dreammaker places a type at its first type block, and the view uses the first occurrence, which can be a macro-expanded
  member path (`MATERIAL_MIX(/obj/item/radio, ...)` one line above the `/obj/item/radio` block). The rule to adopt is the converter's
  `type_sites` rule.

After the fixes (merged master, 16cd549182): 1328 differences, from 2024.

Cold `gen` on the compiler front end: master's 6b7ead2416 declares the generated-only parent types in the stub. On this branch's base, a
model-less first pass and a bootstrap that wrote the no-model generators first both converged to the same output, and both differ from
dreammaker's cold and warm output in `plans.dm` (about 2000 `CGK_*` keys and their rows missing, such as `ckeys_version` and the `/area`
vars). The dmbc run's own `gen --check plans` with a fresh cache then reports that `plans.dm` stale. So inside a cold dmbc `gen`, a stage-1
result is computed from state that no longer matches its inputs. dreammaker's cold `gen` (caches and the gen store off) matches its warm
output exactly. Not yet re-checked after 6b7ead2416.
### 2a cutover (2026-11-27): the lints read dmbc's tree, the converter is gone

The view reached parity 0 before the port (`analyze sem model-parity`, since removed with the converter): every type, parent and site,
every declaration (lines, flags, declared types, builtin members), every var initializer and folded constant, proc resolution and
override chains, and the expression walk of all 120472 proc bodies identical to the converted tree. What that took:

- dm-tree: each declaration occurrence's expanded span is kept (`ColdFrontend::declaration_spans`), and `SpacemanDMM_private`,
  `_protected` and `_final` are declaration flags (bits 8-10), not type path segments (only analysis builds define `SPACEMAN_DMM`).
- The view: a type's definitions in the order dreammaker listed them (the declaring definition first, then source order); a proc placed
  at its parameter list; type sites from the first type block; `parent_type` assignments; nested and sized list types; BYOND's builtin
  members from `tools/analyze/src/model/builtins.tsv` (written once from SpacemanDMM's table); a constant folder with SpacemanDMM's
  rules (`model::consts`); `model::expr` (a chain as a root and hops, borrowed) and `model::walk` (statements and walks).

Then `sem/mod.rs` was rewritten on the view (`Sem::m()`), and every file that read dreammaker shapes was ported (sem, dm, lints, gens,
codemod, frontend). Deleted: `dmbc::analysis_bridge`, `analysis_parity`, `daemon/analysis_model`, the converted-tree half of
`analysis_tree` (what DreamChecker's native input reads stays), `DQ_ANALYZE_PARSE` and the provided-parse hook, `sem::ast`,
`sem/model_store.rs` (the stored dreammaker model), the dreammaker parse pipeline in `sem/mod.rs`, `DreamMakerFrontend` (frontend-diff
compares the text scanner with the compiler front end). The dreammaker crate stays only for DreamChecker's diagnostics types.

Two behaviour points, both kept byte-identical:

- `sem/handlers`' structural pass built a partial model (the candidate files and `code/__defines`); dmbc refuses a partial tree (macros of
  `code/__*.dm`, types the other files declare), so the pass reads the full model. The partial model never expanded the test macros
  (`TEST_ASSERT` returns early), so it never judged the unit tests; they are exempt by path in `tools/ci/lint_scopes.toml` (master had 0
  findings there).
- `sem/incremental`'s record validation read a changed file's facts off a partial model (the file and the defines); dmbc refuses that
  tree too (an override of a var another file declares), and the record then always missed: a one-line edit re-ran every semantic
  lint (87 s against master's 29 s, measured below). The validation now reads the changed files' facts off the full model, which the
  run's other consumers share (`Sem::build_partial` is gone).
- Fixtures: a tree the compiler's front end reads must be valid DM. Fixtures that wrote `GLOBAL_LIST_INIT(...)` with no macro, or a
  var only a subtype declared, define the macro (`code/__defines/...`) or declare the var; `tests/common` registers dmbc's front end
  and the native DreamChecker input for every test, and the unit tests register it under `cfg(test)`.

#### Performance of the view (2026-11-27)

The first port was correct and slow (a cold `gen --check deps` 127 s against master's 36 s). Sampling the run (`cdb -pv` attached a
few dozen times, stacks aggregated; there is no ETW without admin) found three causes, all fixed:

- A proc's site (its parameter list `(`) lexed the whole item, body included, on every first ask: two thirds of the busy samples.
  It is now a byte scan for the first `(` (the lexer only when a quote or comment comes first, never in a header the compiler accepted).
- The typed bodies, var initializers and folded constants were built lazily in a `OnceLock` that the first parallel walk reached:
  the one thread building it ran its `par_iter` while every other rayon worker blocked on the lock, so 120 k bodies parsed on one
  core. `Model::prewarm` builds them when the model is made (bodies and initializers side by side).
- Smaller: proc parameter and site caches sharded (`RwLock` per shard, was one `Mutex`), every included path resolved to its
  repo-relative spelling once when the model is made (each site miss took a global `Mutex`), and statement lines looked up once per
  block (`model::Block`) instead of on every visit.

Measured (`DQ_ANALYZE_DAEMON=0`, caches and the gen store off, single runs on a machine other lanes kept at 60-100 % CPU, so wall times
swing 2x between runs; CPU time is the steadier figure):

| Run | master (dreammaker parse) | branch |
|---|---|---|
| cold `gen --check deps` | 36 s | 47 s (127 s before the fixes) |
| cold `gen` (3 model builds), wall | 128 s, 260 s, 215 s | 302 s |
| cold `gen`, CPU | 125 s, 129 s | 280 s |
| model build per round, wall | 29 s / 82 s / 59 s | 67 s (two front ends) / 26 s / 25 s |
| `check --raw --no-cache` | 149 s, 304 s, 253 s | 171 s, 235 s, 349 s |
| cold `gen`, machine at 94-100 % (p6) | 314 s, CPU 131 s | 644 s, CPU 287 s |
| `check` warm no-op | 10.7 s | 1.9-9.1 s |
| `check` after a one-line body edit (standalone) | 28.6 s | 67-253 s |
| front end alone (`dreamchecker --parse-only`, its body parse included) | | wall 65 s, CPU 31.5 s |

The front end is parallel where dreammaker's parse is one thread: under load a model build is faster on the branch (rounds 2 and 3
above), and it costs about twice the CPU (about 46 s per build against 22 s, the front end's own share). The rest of the extra CPU is
the walks (`sem/handlers` 13-17 s against 3-6 s): the view builds a chain (`model::expr::chain`, a root and a `Vec` of hops) on every
visit where dreammaker's AST was matched in place. A cold `gen` from nothing builds the front end twice in its first round: the first
build fails on the parent types the generated files declare (`build_bootstrapping` then declares them in the stub and builds again).

On this machine, where other lanes keep every core busy, CPU is what a run costs, and the branch's model build costs about twice
master's: the front end alone takes about 20 CPU-s (dreammaker's whole parse took 20-22, on one thread), the typed bodies another 10,
then initializers, folding and the index. A cold `gen` builds the model three times. Standalone, a one-line edit pays a whole front
end and model (master kept its dreammaker model on disk, `sem/model_store.rs`, deleted here, and re-parsed one file); the daemon's
retained front end is the replacement for that, and standalone runs do not use it. Proof p6 (after every change above, master at
c2e3abdc08's merge base): cold `gen` identical (410 files), `check --raw --no-cache` identical (1605 lines).

Tried and dropped: keeping a retained front end session in the analysis process (the daemon's `hosted_frontend` path on a
process-local `BuildHost`), so a `gen`'s second and third model builds would be incremental. The retained cold build took 206 s (the
one-shot cold build 15-20 s) and the incremental ones 11-23 s after the generated files changed, so it was reverted.


Proof: master's `dmbc` (merge base) against the branch, `DQ_ANALYZE_DAEMON=0`, caches and the gen store off: a cold `gen` (all three
generated directories deleted first) writes identical files (410), and `check --raw --no-cache` is identical (1604 lines).

#### Read recording (the contract for per-file and per-proc queries)

`dq_analyze::model::reads` (branch `compiler/lints-native-tree`). A judgement (one file's findings, one proc's walk) runs under
`reads::recording(|| ...)` and gets back its result and a `Receipt`: the set of `Read`s it made. Every accessor of the view that answers
from the model notes one read when a recording is open on the thread; with none open, a note is one thread-local check and builds nothing.

Keys are the front end delta's stable identities (`dm_tree::frontend::DeclarationKey`: file semantic path, owner type path, member name
and kind, ordinal among the same owner, name and kind in the file; `dm_tree::frontend::declaration_keys` gives every occurrence's key in
a revision), so a receipt made on one revision is judged against the next revision's `FrontendDelta` (`RetainedSemanticTree::changes_since`).

| Read | Noted by | Stale when the delta has |
|---|---|---|
| `Declaration(key)` | `Member::initializer`, `initializer_at`, `parameters`, `declared_type`, `flags` | the key `Added`/`Removed`/`Changed` |
| `Body(key)` | `Member::body` (and `Proc::body`) | the body's key `Added`/`Removed`/`Changed` |
| `Site(key)` | `Member::site` (any file or line answer about a definition) | the key in the declarations or the bodies, `Moved` included |
| `Lookup { owner, name, kind }` | `Ty::var_declaration`, `Ty::proc`, `Ty::proc_definitions`, `own_vars_named`, `own_procs_named` | any declaration of `name` of that kind `Added`/`Removed`/`Changed`, or any type declaration changed |
| `Parents(owner)` | `Ty::parent` (so `is_subtype_of`, every walk up the chain) | any type declaration changed |
| `Everything` | `Model::types`, `Ty::members`/`vars`/`procs` (listings), `Model::folded` | any declaration added or removed, or any type declaration changed |

- A miss is a read: a lookup that finds nothing notes the same `Lookup` it would have noted on a hit, so a declaration that appears later
  invalidates it. A member without a key (none in the tree) notes `Everything`.
- Lookups are judged by name (any owner): a declaration of `name` anywhere invalidates, which is conservative and needs no ancestry walk.
- Work a recorded judgement hands to other threads is not recorded: a recorded judgement reads on its own thread (rayon inside it must be
  avoided or its reads noted by the caller).
- The view's own caches (sites, declarations, statements, folded constants) are pure functions of the revision; they note on every
  access, hit or miss, so caching never hides a read.
- `Receipt::holds(&delta)` is the reuse test; an empty delta holds everything, and no delta (a cold revision) means recompute.

## 2b DREAMCHECKER: the checker on dmbc's own tree (2026-11-27, branch `compiler/dreamchecker-native`)

### What landed

- **Oracle.** `tools/analyze/vendor/dreamchecker/tests/corpus`: 62 cases (the vendored crate's 55 test snippets, extracted, plus 7 seeded files
  that make every other diagnostic kind fire: control flow, settings and directives, static types and fields, sleep and purity call trees,
  filters, keyword arguments, BYOND constants). `expected/<case>.txt` is every diagnostic on dreammaker's parse, every severity, with line,
  column, error type and notes (`dq_analyze::dreamchecker::render`); the extracted ones agree with the old tests' (line, column, text) lists
  except where the old harness parsed a buffer instead of a `.dme` (end-of-file token places). `tools/analyze/tests/dreamchecker_corpus.rs`
  runs both checkers, serial and on three threads (one body per batch). The intended differences (13 cases, every one a parse: dreammaker's
  grammar, or a tree BYOND refuses) are `expected/<case>.dmbc.txt`, with the reasons in the corpus `README.md`.
- **Native checker.** `dreamchecker::native` (vendored crate, `src/native/`): DreamChecker's passes (var definitions, settings, bodies,
  override validity, call tree) over its own model of BYOND types (`model.rs`: the builtins as SpacemanDMM knows them, `builtins.txt`, dumped
  from dreammaker's table and checked against it by `tests/builtins_dump.rs`; the project's declarations registered by dreammaker's rules)
  and the front end's typed statements (`dm_syntax::Statement`/`Expr`, read in SpacemanDMM's terms by `view.rs`). dmbc builds the input
  (`dmbc/src/dreamchecker_input.rs`, from `analysis_tree::matched` and `front`); no dreammaker tree or AST is built for it. What it still
  uses of the `dreammaker` crate: `Context`, `DMError`, `Location`, `Severity` (the output) and `FormatFloat`/`Quote` (two messages' spelling).
- **Places.** A place is a `Where` (an offset, a line end, a declaration end, or a location) and is located only when a diagnostic prints it:
  locating was most of the cost (model 60 s and bodies 11 s eager; about 2 s each lazy). Fixed at the source so columns match dreammaker:
  a condition sits at its `(` (`dm_syntax::control_open_paren`), a switch case where its block ends, an override at its `=`, a token of a
  function-like macro's argument at the invocation (`dm-tree` `debug_site_column`; it had placed it at the argument), a var a macro declares
  at the invocation. The converted tree (`analysis_bridge`, `analysis_tree`) got the first four too.
- **BYOND constants.** dmbc predefines `NORTH`, `WAVE_SIDEWAYS`, `FLOAT_LAYER` as macros; dreammaker reads them as global vars. An expression
  that is exactly the expansion of such a macro written in the source, or of a macro whose expansion is only one of them, is read as the
  constant's name (`dm-tree` `SiteMapper::invocation_output`, new: it aligns a row's invocations with its output by the text copied between
  them). Constants dreammaker also defines as macros (`TRUE`, `FALSE`) stay values, as dreammaker sees them. The filter, condition, range
  and static-term checks then give dreammaker's diagnostics (corpus `seed__filters`, `seed__builtin_constants`). Left as a value: a constant
  inside a larger macro's replacement (dreammaker sees the name); nothing in the corpus or the tree reads one there.
- `DQ_DREAMCHECKER_NATIVE=1` selected it while it was proved (removed at the cutover below).

### Proof

- Corpus: every case passes on both checkers (49 identical to dreammaker, 13 intended differences).
- Whole tree (`analyze dreamchecker --json` in a worktree with its generated files, whose unit-test fixtures fire 131 diagnostics), and the
  same tree plus a seeded file (17 more diagnostics of 12 kinds: unreachable code, determinate conditions, a bad range, `NORTH` as a condition
  and as filter flags, `||` in a case, `!x & 1`, static-type fields and calls, a private var, keyword arguments, sleep and purity call trees):
  every DreamChecker diagnostic identical (line, column, text, notes, order). The three other differences are dreammaker's own parse, not
  checks: a parse error at `new L[1](...)` (`code/tests/benchmarks/map_plan_cost.dm:49`, a form BYOND accepts) and two constant-evaluation
  errors of dreammaker's tree finish (`unknown variable: GAS_ID_CHLORINE` and `GAS_ID_AMMONIA`, `code/domains/atmos/methane_and_fuel_gases.dm`,
  which BYOND compiles). So natively `Found 131 diagnostics` is 128, the hint count is 390 (the known `#define` doc hints), and include paths
  are canonical (`code/tests/unit_tests/x.dm` where dreammaker keeps the include's `unit_tests\x.dm`).

### Step 3 shape (for the ENGINE workstream)

Per-proc results are pure functions with stable identities (`model::ProcId`: type, proc slot, definition index):

- `native::settings_of(model, settings, context, site, proc, body)`: a proc's declared return type, final flag and leading `set` statements.
  Reads only its own declaration and leading statements.
- `native::body_facts(input, shared, site, proc) -> walk::ProcFacts`: one body's diagnostics, calls (callee, place, new context), blocking
  and impure operations, `waitfor`, keyword arguments. Reads its body, the model and the settings table (`walk::Shared`), nothing else.
- The rest of `native::run` folds the facts in source order and runs the override and call-tree passes (`CallTables`) over them only.

An edit then needs the model (rebuilt from the semantic tree, about 2 s, or spliced), the settings of the edited procs, and the body facts of
the procs whose body or read declarations changed; the call-tree pass reruns over the kept facts (under a second).

### Measured (single runs on a heavily shared machine; numbers swing 2-4x between runs)

| What | dreammaker parse (default) | native |
|---|---|---|
| whole tree, standalone, cold | 8.2-11.9 s | 23-35 s: the compiler front end 15-28 s (its own cold cost), input 3-8 s (matching 1-2.5 s, body parse 2-3 s, model 1.4-2 s), checks 2.5-8 s |
| whole tree through the daemon, warm | (no daemon path) | 22 s: front end 4.3 s (retained session), input 4.3 s, checks 3 s, the rest request overhead |

So the native checker is not yet the only path: cold it pays the compiler's front end, and warm the daemon still rebuilds the input on each
request. Next, in this order: keep the input (model, parsed bodies) per front end revision in the daemon; per-proc facts as dm-query queries
(ENGINE); then make it the only path and delete `lib.rs`'s checker on dreammaker's tree, its tests and `DQ_DREAMCHECKER_NATIVE`.

**For LINTS (2a):** the checker no longer needs the converted tree: the native checker reads dmbc's tree, and the default one reads dreammaker's
parse, never `DQ_ANALYZE_PARSE=dmbc`. The native input reuses `analysis_tree::{matched, front, Front, var_header, signature_parts,
line_end_column, source_line, locate_in, macro_warnings}`: keep them (or move them beside `dreamchecker_input.rs`) when the converter goes.

### Cutover (2026-11-27, branch `compiler/dreamchecker-native-2`): the native checker is the only one

- **Per-proc results as queries.** `native::run` takes a `Store`: `settings_facts` (a proc's settings as events, `facts::SettingsFacts`)
  and `body_facts` (`walk::ProcFacts`, its diagnostics as data, `facts::Diag`) come from it, and the override and call-tree passes read only
  them. dmbc's `QueryStore` (`dreamchecker_input.rs`) keeps them as entries of the analysis query database (`dq_analyze::incr::keyed_by`,
  stores `dreamchecker-settings` and `dreamchecker-bodies`): held in memory by the daemon, persisted under its analysis directory, under
  the stamp `check` uses (one session for both commands). A result's key is the proc (`ProcId`) and its body (expanded text, its file's
  path and bytes, its place); the context is the model key (every declaration's owner, name, kind, flags, spelling, line and column, the
  types and parents, the file ids) and, for bodies, every proc's settings facts. A body's places are stored relative to its start. A body
  is parsed only for a result that is computed (a body is taken from the arena once and shared by both passes).
- **Input per revision.** The model is rebuilt each request from the front end's semantic tree: the spelling walk runs per chunk on
  every core and the declaration records are prepared in parallel (matching 0.6-1.1 s, model 0.5-1.0 s, keys 0.2-0.4 s on a quiet run).
  Keeping the model itself between revisions needs its places in a form an edit does not move (they are offsets in the expanded text);
  it is the next step if the model shows up again.
- **Removed:** upstream's checker on dreammaker's object tree (`vendor/dreamchecker/src/lib.rs`'s `AnalyzeObjectTree`, `type_expr.rs`,
  `switch_rand_range.rs`, `test_helpers.rs`), its tests (`tests/*_tests.rs`, now the corpus), `analyze dreamchecker`'s dreammaker parse
  (`dreamchecker::check`) and `DQ_DREAMCHECKER_NATIVE`. `analyze dreamchecker` needs the compiler (`dmbc analyze`, the analyze alias); the
  standalone analyze binary says so. `sem::parse_for_checker` stays for dmbc's `analysis-parity`.
- **Accepted differences** (corpus `README.md`): dreammaker's own parse diagnostics on code BYOND accepts, its `#define` doc hints, and
  include paths spelled canonically.

Measured with one daemon per run sequence, each with its own namespace and analysis directory (`DMB_DAEMON_NAMESPACE`,
`DMB_ANALYSIS_DIR`), on a heavily shared machine (other lanes building; single runs swing 2-10x): cold daemon, unchanged, a one-proc body
edit (a string in `code/engine/actions/admission_query.dm`), reverted.

| `analyze dreamchecker --json` through the daemon | old (dreammaker parse) | native |
|---|---|---|
| cold daemon | 7.5, 13.3, 19.9 s | 32-197 s (the compiler front end cold: FRONTEND) |
| unchanged | 8.4, 16.1, 15.8 s | 7.8, 9.0, 10.6 s |
| one-proc edit | 10.5, 18.8, 111.9 s | 10.7, 15.2, 20.1 s (2 of 120480 procs recomputed) |
| reverted | 10.5, 23.3, 33.4 s | 8.1, 9.4, 11.3 s |

In a warm native run the checker itself is about 3 s (input 1.1-1.6 s, keys 0.3 s, settings and bodies read back 0.3 s, overrides and
call tree 0.5-0.8 s); the rest is the retained front end (2.7-5 s, the FRONTEND lane's) and the request around it.


### Proportional work (2026-11-27, branch `compiler/dreamchecker-proportional`)

Goal: a request's checker work proportional to the edit (inside the daemon, front end excluded): unchanged under 100 ms, a one-proc
body edit under 300 ms, a line-shifting edit recomputing only the edited proc.

**Why an unchanged run cost 3 s.** Nothing about the answer was remembered: `analyze dreamchecker` was not asked through the
analysis database (only `check` was), so every request re-registered the front end's 8.5k files (a `canonicalize` each, about
0.6 s on Windows), rebuilt the input (matching 0.8-1.3 s, model 0.5-1.3 s, keys 0.6-1.1 s: every body's expanded text and every
file's bytes hashed) and asked the query store for 240k per-proc entries (0.3 s) before folding them and running the override and
call-tree passes again (1 s). A computed answer also waited for the fingerprint walk of the whole root (4 s of a 4.7 s request on
this machine) before replying.

What landed:

- **The answer is a top query.** `dq_analyze::cli::rememberable` names `dreamchecker` (no `-c`, an `-e` inside the root); the
  daemon asks it whole through `ANSWER` (its `--json` is the checker's flag, not the report view's). The persisted copy no longer
  makes the reply wait: the fingerprint walk runs beside the computation and is joined on a thread after the reply, and an answer on
  disk is read back only on a root's first revision in the process (a restarted daemon), when it can be newer than memory.
- **A run is data.** Every diagnostic is registered on a context of the run's own (no config, nothing printed) and then onto the
  command's context in order, so the run's files and diagnostics are kept apart from the config. The registered spelling of a path
  is kept per canonical root (one `canonicalize` per file per process).
- **Kept per front end revision** (`dreamchecker_input::Resident`): the files, the preprocessor warnings, the model and its
  hints, and `native::Kept` (every pass's results: per-proc settings and walk diagnostics, the settings tables, the folded call
  tree, violations and keyword arguments, the override results, the call-tree findings). A request whose front end is the kept
  revision registers the kept diagnostics again.
- **Moved to an edited revision** (`dreamchecker_delta.rs`, `Kept::update`) when the front end's delta (`ColdFrontend::delta`,
  or `RetainedSemanticTree::changes_since` when other requests came between) keeps every declaration (each at most `Moved`) and
  every body occurrence:
  - model places (expanded offsets) move with their declaration (`ColdFrontend::declaration_starts`, new accessor): a place with
    no edited-file output between its declaration's start and itself moves by the declaration's shift; otherwise the
    declaration's text through the end of the place's line must read the same in both revisions;
  - locations move by a per-file `LineMap` of each edited file (common first and last lines): unchanged lines move by the edit's
    line difference, a location on a changed line is refused and whatever holds it is computed again (a proc's settings and walk,
    the var definitions, the keyword-argument check, one call-tree finding); a changed line that is a preprocessor directive, a
    setting that changed, or a place that cannot be moved computes a new run;
  - a body changed when its expanded text or a line of its source changed; only those are walked again;
  - **recorded reads in the later passes:** each call-tree finding (one per `should_not_sleep` / `should_be_pure` proc) records
    every proc its search looked up; after an edit it is judged again only when one of those procs got other calls, blocking or
    impure operations or `waitfor` (a walk's shape), other override lists, or entered or left a reach set (the reach sets are
    computed again then, from one callers map each instead of three passes). The violations up the inheritance chains are
    computed again from the violators only; the keyword-argument check runs again only when some proc's keyword arguments
    changed. A walk whose shape is unchanged moves nothing in those passes but places, and the fold tables' places are kept
    relative to their proc's body (`Bodies::start`), so they move with it for free.
- **Shift-stable keys for a new run** (the fallback path, and a restarted daemon): a per-proc result's key is its body's
  expanded text, its file's semantic path and the source text of the lines it spans (not the file's bytes and span); the context is
  the model's structure (owners, names, kinds, flags, spellings, types, file ids; no declaration lines). A result's places are
  stored relative to its body and its locations inside its lines relative to its first line; a location elsewhere (a note naming
  another declaration, another proc's directive) is a recorded read of its file's content (`incr::keyed_reading_by`, new: the
  keyed form of `keyed_reading`), so the result is computed again only when that file changed.
- `DQ_DREAMCHECKER_VERIFY=1` (debug tooling, kept): every moved run is computed again from scratch (fresh model, no store) and
  compared diagnostic by diagnostic; a difference is printed and the computed run is used. `DQ_ANALYZE_PARSE_TRACE=1` prints the
  front end and checker times (wall and process CPU) and what a move did.
- Front end revision numbers are unique in the process (`RetainedSemanticTree::next_revision`): a kept run of an evicted session
  must not find another lineage's revision under its number when it asks the new session for `changes_since` it.
- The recorded reads of the later passes are kept in the run itself, not as `incr` entries: they are judged against the kept
  run's own previous results (the 12.6k call-tree findings read 38.8k procs in all), so they need no store round trip; the
  per-proc results of a new run are `incr` entries with recorded reads (`keyed_reading_by`).

Measured (`analyze dreamchecker --json` through one daemon with its own namespace and analysis cache, `DQ_ANALYZE_PARSE_TRACE=1`;
the checker's time is the request's minus the front end's; the machine was shared with other lanes, so the first numbers are
with it at 100 % CPU and the second on a quieter stretch):

| Request | master | this branch |
|---|---|---|
| unchanged, in the daemon | 3.6-8.5 s (checker 3-5.5 s) | 2-8 ms (the answer from memory) |
| a change the sources do not see (a file the `.dme` does not include) | as above | 64 ms in the daemon, checker 7.5 ms (the kept revision) |
| one-proc body edit (a string in `admission_query.dm`) | 6-20 s; checker about 5.5 s (input 2.6 s, keys 1.1 s, settings and bodies from the store 0.6 s, overrides and call tree 1 s) | checker 200-314 ms at 100 % CPU, 93-100 ms quieter (the move 50 ms: set up 12, places 14, update 18 of which moving the folded places 13, now 0.3; 1 body walked) |
| line added inside a proc (every later proc moves) | every proc computed again (the model key held every declaration's line) | 1 proc walked; checker 95-265 ms |
| two lines added in two procs | as above | 2 procs walked; checker 95 ms |
| `sleep(1)` added to a widely called proc (12.3k new findings) | full run | 11.8k of 12.6k findings judged again, 14-15 s (the findings themselves) |
| a var or proc added, a file deleted | full run, every per-proc result computed (240k) | a new run, per-proc results from the store when its structure was seen before, else computed (structure key) |
| front end evicted (another session) | full run | a new run (no delta: revision numbers unique) |

Proof: the corpus (62 cases, serial and threaded) and the analyze gate-test suite (298 unit tests and the integration tests)
pass; dmbc's `dreamchecker_delta` and `analysis_db` tests and dm-tree's delta tests pass. Whole tree, through the daemon,
`analyze dreamchecker --json` stdout and stderr byte-identical to master's at every step of base, string edit, base, line added,
base, two lines added, base, `sleep` added, base, var added, base, proc added, base, file deleted (with its include), base; with
`DQ_DREAMCHECKER_VERIFY=1` every moved run equal to the run computed again from scratch in the same daemon (string, line, `sleep`
and their reverts: 516 and 12307 diagnostics), and the structural edits computed as new runs.

What is left:

- A new run after a structural edit (a var or proc added or removed, a declaration's spelling changed) still rebuilds the input
  (matching, model, keys: 1-2 s) and reads 240k per-proc entries; with a new structure every per-proc result is computed again
  (about 30 CPU-s). Keeping those per proc needs each walk's reads of the model recorded (the declarations it looked up, by
  stable key) instead of one structure key; with the stable member slots (lane `compiler/stable-member-slots`) a new member
  no longer renumbers the model's procs, which is the other half.
- (Done after the first landing.) The folded places (788k calls, the violations, the keyword arguments) are kept relative to their
  proc's body; an edit moves only the 120k body starts (0.3 ms, was 13-24 ms of the update).


## 1+3 ENGINE: analysis results as queries (2026-11-27, branch `compiler/analysis-queries`)

### Increment 1: the answer is the top query; results as data

- **Answers in dm-query.** The daemon keeps one `dm_query::Db` per project root (`dmbc/src/daemon/analysis_db.rs`). Its top query
  `ANSWER(argv, cwd)` is a command's whole answer (exit code, report, stderr). It reads `TREE`, an input whose hash moves only when the
  directory watcher (`fs_watch`, `changed_entries_since`) logged a change under the root that a command can read (everything but
  `.dmbc`, `.git`, `data` and any `target` or `node_modules`; a lost event, another epoch or an uncovered root counts as a change), and
  one `VAR(name)` per environment variable the run read (`dq_hostio::env_reads`; early cutoff: another shell whose other variables differ
  stays green). A run that started a child command reads the whole environment. `dq_analyze::cli::rememberable` names what is asked
  through it: `check` without `--changed-only`, `--timing`, `--no-cache`, `--rehash` or `DQ_ALLOW_USAGE` (an effect or an input outside
  the root); the rest runs as before.
- **dm-query `get_with`.** Kinds whose function each read supplies (`Db::define_local`): revalidated like any other; a dependant that
  finds one red with no function at hand sees it missing and runs itself.
- **Results as data.** `dq_analyze::report`: a check's stdout is `Report::render` of its report: per lint its text, its sites as
  `Diagnostic`s (lint, rule, file, line, column (0 until lints report columns), message, severity: `Error` for a site the verdict counts,
  `Baselined` for a legacy site its baseline admits, `Note` where the lint judges itself) and its allow uses. The daemon sends a remembered
  answer as data (`Reply::AnalysisData`: the report and its revision) and the client renders it, the same bytes. `--json` prints the
  report, `--file F` one file's diagnostics, `--since N` what changed since the report of revision N (the daemon keeps the last 16;
  standalone has no history: revision 0, everything added). The view flags are not part of the answer's key.

### Increment 2: incr on the query database, one persistence layer

- `incr::facts/keyed/keyed_by/two_phase/cached` keep their signatures (result types gained `Clone`) and run on one `dm_query::Db` per
  stamp, kept for the life of the process: every entry is named by what decides it (`ENTRY(store, context, content key)`,
  `VALUE(store, key)`), computed by the caller's closure through `get_with`, and held decoded, so a hosted request reads unchanged results
  without decoding them, and an entry is valid for every worktree the daemon serves.
- Persistence is one layer for both paths: per-store slot files (`persist-*.bin`) with per-root leases and a byte budget
  (`DQ_ANALYZE_STORE_BUDGET_MB`, 768): the worktree's `data/analyze-cache` standalone, `E:/dq-cache/analysis/<image>` in the daemon
  (`[cache.analysis]`). A lint's per-file results and whole-tree memo are entries too (`lint:<name>|<version>`, `lint-tree:...`).
- Deleted: incr's own disk stores (`incr-*.bin`, the sharded containers), `LintCache` and `lint-*.bin`, the daemon's byte store
  (`daemon/analysis_store.rs`, its `Provider` trait).
- Answers persist beside the slots (`answer-*.bin`) with a fingerprint of every file the watcher would report (path, size, mtime; taken
  as the run starts) and the variables read, written only when the watcher saw no relevant change while the run went. `ANSWER`'s function
  reads it first: a restarted daemon answers an unchanged request after one walk of the root.

Not yet (what is left, in order): the context keys are still whole-index keys (a judge reruns on any fact change of its store; the
fine-grained form needs judges to read index entries through a recording accessor, which changes lint bodies: the LINTS lane's port);
the sem record, `value_procs`, the walks and `gen/deps` still validate per run (about 5 s of a body edit's 7 s: `gen/deps` 1.8 s,
`value_procs` 1.7 s, the walk-cache validation, `sem/handlers` 0.8 s); the model store and walk store still decode from their own files
after each request (prewarm).

Measured (single runs; the machine was shared with three or four other lanes building, so edit timings are noisy):

| What | master | this branch |
|---|---|---|
| nothing changed, in the daemon | 0.8-4.7 s | 46-101 ms (client process end to end 0.17-0.27 s) |
| one-line body edit, then its revert | 6.0 / 6.6 s (82 s once, a cold model store) | 11.2 / 7.2 s with `DQ_ANALYZE_TRACE` on (13-19 s before increment 2) |
| first request of a new daemon | 56-209 s | 112 s (loaded machine) |
| restarted daemon, nothing changed | a full run (1.2 s with warm disk caches; minutes cold) | 0.57 s in the daemon (the answer read back after one walk of the root), 0.83 s end to end |

Proof on this branch: `check --raw` and `check` byte-identical to master's standalone answer on master and on seeded trees (a one-line
body edit, a new var, a new proc, a deleted file: daemon answers of increment 1 against master standalone, every pair identical); after
increment 2 and the merge of master: daemon `check --raw`, standalone `check --raw` (cold and warm slots), `check` and `check --raw
--no-cache` identical to master's; `gen` rewrites nothing; the analyze test suite (gate-test: 298 unit tests and the integration tests)
passes; dm-query's tests (`get_with` included) and dmbc's `analysis_db` and `fs_watch` tests pass.

### Workstream 4, front end edit floor (2026-11-27, lane `compiler/frontend-edit-floor`)

Detail and the per-phase table: tools/dmb/doc/retained_frontend.md, "Front end edit floor".

- The hosted analysis front end read every source from disk on every request (no change log, no prepared sources), so its plan
  never patched and its adoption declined every file. It now reads through `dmbc::watched_sources`: kept prepared sources,
  revalidated through the directory watcher (only files in a changed directory are stat'ed, only moved stamps re-read), with a
  change log the planner patches from. A request whose sources did not change gets the remembered front end back.
- Per-phase wall times on every build (`frontend phases:`; analysis requests print them with `DQ_FRONTEND_TRACE=1`).
- Origins, body indexing and body terminations are parallel; tree reuse compares skeleton leaves by pointer.
- Every revision carries a delta (files, declarations, bodies under stable keys: semantic path; owner, member, kind and per-file
  ordinal) and `RetainedSemanticTree::changes_since(n)` chains them, for the analysis queries to key on.

Measured on a machine at 100 % CPU (upper bounds): front end of a one-line body edit 6.5 s before (2.1-2.9 s on a quieter machine)
to 0.45 s; no-op to the watcher sync (0.007 s, front end not built); new var 2.6 s and new proc 1.9 s (tree splice and dependency
capture); a `#define SECONDS` edit adopts 6862 subtrees again (it declined all 8498 files); cold plan 22-192 s under load to 2.3 s
(parallel prefetch), cold front end 24 s under load. Targets met: no-op. Not met: body edit 200 ms (the O(declarations) adoption,
origin and body passes), var/proc 500 ms (dense-id tree splice, needs stable ids), cold 6 s (declaration parsing with the memo and
the 8-worker cap, single-threaded tree rebuild); retained_frontend.md says what each needs.

Proof: hosted (incremental) against a cold front end in the same daemon (`DQ_ANALYZE_HOSTED_FRONTEND=0`) over base, body edit,
line shift, new var, new proc and revert: `analyze dreamchecker --json` and `analyze check --raw --no-cache` byte-identical at
every step. dm-tree (312), dm-preprocess (165) and dmbc (1135) unit tests pass; a production compile is byte-identical to one by the compiler built from its master base; new tests for the watched provider, the prefetch, the parallel map, leaf
comparison and the delta.

For the ENGINE workstream: the analysis model memo (`daemon/analysis_model.rs`) still reads and hashes every model file on every
request (`same_inputs`) before the front end runs; the watched provider's token (`WatchedSources::token`) answers "did any source
change" without reading them.

Round 2 (lane `compiler/frontend-edit-floor-2`): copied regions reuse their declarations' origins and bodies' locations, the
authored lease inherits the previous request's claims (no replay of 25k owners on a body edit, only changed owners after a
declaration edit), and a cold hosted front end uses every core. Quietest runs: body edit front end 0.21-0.25 s (was 0.45),
`#define SECONDS` 10.1 s (was 14.7), cold 15.4 s; new var 2.0 s and new proc 2.2 s are bound by the dense-id tree splice, which
needs the stable-id decision (retained_frontend.md, round 2). Proof: hosted against cold dreamchecker and check outputs identical over
the edit sequence, compile byte-identical (equivalent for a new var), analysis-parity 100 %, ratchets pass. The published
`dmb-bin/dmbc.exe` at the bin root is a stale October binary; builds use `dmb-bin/v/<current>`, which matches master.

Round 3 (lane `compiler/body-edit-floor`): a reusing expansion says which spans of the joined text it copied
(`ExpandedRegions::carried`), and the declaration parse reads that instead of the bytes: the grammar check compares only receipts
that were not carried from a proved text (prefix and suffix by piece identity), a carried chunk takes the previous request's key and
bound contribution (no hash, no compare), the symbol catalog applies only the contributions that changed (spelling counts shared
between requests), and bodies in interior carried chunks keep their terminations. The plan shares its terminal macros and
dependencies with its patch, the joined text is copied in parallel without zeroing, the body index is dense, bodies find their
declaration from a cursor, and origin and body rows are built as columns. Measured interleaved against a master daemon on the loaded
machine (12 requests each): body edit front end 0.146 s quietest / 0.255 s median (master 0.335 / 0.474), line shift 0.133 / 0.283
(master 0.317 / 0.706); no-op 0.007-0.032 s (median 0.013); declaration parsing 0.022 s (was 0.13-0.17). What is left is a dozen passes of 2-20 ms over flat whole-program
arrays (origins, occurrences, bodies, regions); chunking those arrays so a revision shares unchanged chunks is the next step and
changes every consumer of the front end's output (retained_frontend.md, round 3). Proof: `DMB_FRONTEND_VERIFY=1` clean on every
incremental analysis and compile request (carried chunks, origins, bodies, terminations, plan, expansion); hosted against cold
`dreamchecker --json` and `check --raw --no-cache` identical at base, body edit, line shift, new var, new proc and revert;
analysis-parity 1168032/1168032 (tree) and 105883/105883; dm-tree, dm-preprocess and dmbc unit tests pass. A daemon patch compile is
`dmb-equiv` EQUIVALENT to a cold one, not byte-identical (the replaced string stays in the string table); master's compiler gives the
same bytes as this branch for that sequence, so that is older than this lane.

### Increment 3 (2026-11-27): stores held decoded, lints per file, the measurement fixed

- **Fair measurement.** `tools/dmb/scripts/analysis_edit_timing.sh` times a daemon per compiler, each with its own namespace and
  analysis cache (`DQ_ANALYZE_CACHE` under `data/`), one compiler after the other, and waits for a request's read-ahead before the next
  one (an edit is timed as a person makes it). The daemon's answer line now carries the request's process CPU, the steadier number on a
  shared machine (wall time moved 3x between identical runs while three other lanes built).
- **Held decoded between runs.** The model of the last hosted run stays in memory (`model_store::Resident`): the next run splices only
  the files changed since that run (the delta on disk stays relative to the base, so a new process reads a consistent store;
  `DQ_MODEL_VERIFY` proved every update against a full parse). Walks fold into a resident store the next run takes
  (`walk_cache::Resident`; `DQ_WALK_VERIFY`: 0 of 12850 differed). The read-ahead after a request has nothing left to read; the hosted
  end-of-run work (writing the stores) runs after the reply. The dmbc-parse model memo asks the watched sources' token
  (`service::hosted_sources_token`) instead of reading and hashing every file.
- **Lints per file.** Text facts kept per file (`incr::facts`): declaration_block, notice_publisher, map_edits (the maps keyed by
  content), weak_raw_read, rel_write_undeclared, `ui_windows::text_defines`; report_in_catch is a file lint. Proc-body judgements kept per
  file (`procs::per_file_in`) under exactly what else they read: weak_raw_read, untyped_member, rel_write_undeclared (structure,
  `Sem::placement_digest`: the file of every definition, and the index digests), image_dir_after_build (plus
  `procs::return_settings_digest`, the return types bodies declare).
- **Recording accessor.** `incr::keyed_reading` with `incr::Index` / `Reads::get`: a judge's result is kept while every index entry it
  read (absent ones included) digests the same. decl reads its own file's typed definitions through it and no longer re-judges every file
  on any edit.

Files this touched for the LINTS lane to merge: `tools/analyze/src/lints/{declaration_block,report_in_catch,map_edits,notice_publisher,
weak_raw_read,rel_write_undeclared,untyped_member,image_dir_after_build,decl}.rs`, `sem/{mod,procs,model_store,walk_cache,ui_windows}.rs`,
`incr.rs`, `cli.rs`; plus `#[derive(Clone)]` on about 30 result types (increment 2). Each change is at the caching boundary: a loop body
moved into a closure, its accumulator folded afterwards in the original order.

Measured (`analysis_edit_timing.sh`-style runs; CPU is the daemon's process CPU for the request):

| What | before increment 3 | after |
|---|---|---|
| one-line body edit, CPU | 22-25 CPU-s | 18-22 CPU-s |
| one-line body edit, single-threaded standalone `timing` (the CPU map) | about 32 s (model and walk decode included) | about 17 s |
| nothing changed | 46-100 ms in the daemon | the same |

Proof: `check --raw` byte-identical to master's standalone answer on master and on seven seeded trees (a one-line body edit, a new var,
a new proc, a proc moved to another file, a deleted file, restored); `check` and `analyze dreamchecker --json` identical; `analysis-parity
--tree` 1168032 of 1168032 and `analysis-parity` 105883 of 105883 with 0 difference categories; the analyze test suite passes.

What is left, and why it is not mechanical. The edit's remaining CPU is in judgements that read other files' bodies without saying so:
`value_procs` (its `config_class_clean` reads every proc body of a type; untyped needs its verdicts), the reads walks behind
`sem/handlers`, `gen/deps`, `untracked_inputs` and `setter_publishes` (walk results validated per run, consumers re-folded), ui_actions,
stored_refs, the layering lints. Keeping those per file needs every body and declaration read recorded where it happens, on the model's
accessors (the walk store already records `Proc`/`Var` reads for walks): that is the Sem API the LINTS lane is rewriting on dmbc's tree.
