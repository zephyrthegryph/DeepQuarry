# Unified native compiler, Analyze and DreamChecker

Status: implementation in progress, 2026-10-30. The shared native contracts and
ported consumer slices are recorded in the checkpoints below. The target design
is broader than the implemented surface: production Analyze/checker cutover and
the remaining semantic consumers are not complete. Proposed interfaces in the
original plan are not promises that those APIs already exist.

## Decision and endpoint

The native compiler frontend becomes the single source of program structure.
Each worktree's retained project session on the compiler version's daemon
serves compilation, Analyze policies and generation, and ported DreamChecker
checks over one immutable revision and one dependency-tracked query graph.
Analyze and checker command lines become clients. A combined gate requests
their common work once.

This supersedes the optional convergence in origin/master's `one_frontend.md`. That file is absent from this checkout, so this is a separate proposal rather than overwriting another lane's document.

Done means:

- No production Analyze or checker request invokes SpacemanDMM's parser or builds its ObjectTree.
- File bytes, expansions, symbols, declarations, procedure syntax, resolved references and common facts have one logical owner. Consumers borrow handles, not copies of the whole tree.
- Concurrent consumers of a query share its computation and result.
- Edits rerun the affected dependency closure, including other files when necessary; they do not automatically rerun every semantic check.
- Existing diagnostic coverage, configuration, suppressions, baselines, generated outputs and CLI behavior are preserved and accounted for.
- Benchmarks demonstrate lower total CPU and combined memory, as well as lower wall time.

Compilation, raw-source lints and checker inference have distinct work. Complete reuse means eliminating duplicate prerequisites; it cannot eliminate the unique work each product requires. A shared process alone does not meet this plan.

## Evidence and implementation anchors

Historical measurements from Claude sessions and origin/master's design need reproduction at a fixed commit:

| Work | Recorded cost | Consequence |
|---|---|---|
| DreamChecker | 385.6 s wall, 380 s CPU, 1.05 GB | Port and incrementally schedule checking, not only parsing |
| Analyze cold | 41-56 s, about 3.7 GB peak working set | Remove the separate model and duplicate indexes |
| Analyze after body edit | 18-27 s | Whole-tree semantic walks must become incremental |
| Native warm body edit | about 4.5-6 s | Preserve compile-only performance |
| Native quiet cold game build | 74.5 s, including 23.1 s cache write | Measure response time separately from deferred completion |

Source inspected in this checkout:

- `tools/dmb/crates/dm-query/src/lib.rs`: dependency recording, reverse edges, early cutoff, value eviction, shared computation. Cross-thread query cycles can deadlock; recursive inference must not issue cyclic blocking fetches.
- `tools/dmb/crates/dm-syntax/src/lib.rs`: spans, body parser, visitors, lexical scopes and reference roles. The module explicitly disclaims complete expression coverage: inventory actual gaps before promising parity.
- `tools/dmb/crates/dm-analysis/src/lib.rs`: existing typed-body and tree-export surfaces. Extend this analysis layer instead of inventing a separate frontend.
- `tools/dmb/crates/dmbc/src/query_db.rs`, `runner_analysis.rs`, `analysis_export.rs`, `engine_catalog.rs`: integration, native analysis and builtin-model audit points.
- `tools/analyze/src/sem/mod.rs`: Sem owns dreammaker ObjectTree; ProcBody exposes dreammaker AST and parameters. Its current interface is not representation-independent.
- `tools/analyze/src/sem/body_facts.rs`: fact-digest reuse already exists, but changed facts can still cause whole-tree rebuilds.
- `tools/analyze/src/tree.rs`, `strip.rs`, `incr.rs`, `sem/walk_cache.rs`: text semantics and cache contracts to preserve.
- `tools/analyze/vendor/README.md`: current parser pin. Only the checker executable was found under `~/SpacemanDMM`; its pass inventory requires pinned source.

Memory figures from different runs use different accounting methods and revisions. Do not add sampled heap, private bytes and working set or treat them as a controlled cumulative comparison.

## Target ownership and layering

| Layer | Owner / proposed placement | Shared products |
|---|---|---|
| Request host | existing dmbc daemon | admitted revision, cancellation, CPU and memory budgets |
| Source | native input snapshot and dm-preprocess | bytes, hashes, include/define dependencies, expansions and origin maps |
| Syntax | dm-syntax | immutable per-body syntax arenas and demanded raw/trivia views |
| Program model | dm-tree and dm-ir | declaration IDs, hierarchy, signatures, builtins, lookup results |
| Common semantics | dm-analysis using existing query store | scopes, resolved refs, body facts, CFGs, summaries, reverse indexes |
| Compilation | existing lowering/link/codegen | compiler-specific products using common semantics where equivalent |
| Analyze | dq-analyze library, later consumer crate if useful | ratchets, annotations, project checks, generators, codemods |
| Checker | proposed dm-check library | ported DreamChecker diagnostic policies and inference |

The host links consumer libraries. Shared framework crates must not depend on project ratchet policies or the dmbc executable. Audit the Cargo graph before extraction to avoid cycles; wholesale file moves are not required first.

Checker policy remains separate from compiler acceptance. A warning-only inference pass must not become mandatory compilation work. Preserve separate rule identities even when facts are shared.

## Revision, query and source contracts

Capture immutable revisions from root, manifest, ordered includes, defines, compiler/builtin version and relevant configuration. Every response and published artifact belongs to a specific revision. Separate define sets are distinct semantic views over shared content. Equal bytes are not equal issuance identity: retain the binding-table identity fix.

Use existing query identity/dependency machinery after auditing its receipt requirements, not another cache of the same facts. Register source, declarations, bodies and configuration as inputs. Split configuration by effect: baseline edits rejudge findings; severity edits rerender diagnostics; neither should reparse procedures.

| Proposed query family | Dependencies | Consumers |
|---|---|---|
| Body syntax/scopes | expanded body tokens, grammar version | all three |
| Declaration/lookup | relevant owner/hierarchy/name buckets/builtins | all three |
| Body facts | syntax and resolutions actually consulted | Analyze, checker, compiler where useful |
| CFG | body syntax | checker, semantic lints, compatible lowering |
| Inference summary | local facts and consulted signatures/summaries | checker and relevant lints |
| Diagnostics | facts/summaries and rule config | respective checker/lint |
| Policy judgement | diagnostics, scopes, ALLOW, baseline | Analyze |

Never key every result by a whole-tree digest: it recreates today's invalidation. Record failed lookups and name-bucket dependencies so adding a missing declaration invalidates prior misses. Hierarchy/order changes may legitimately affect many queries; measure and report that fanout.

Raw, stripped and expanded text are distinct. Preserve Analyze's two stripping contracts and source markers such as CAPABILITIES that preprocess away. Cache each necessary text view once by content and view version. Do not replace source-based rules with approximate semantic rules. Spans retain raw provenance, macro expansion chains, include sites and configured display paths. Equal content can share storage across roots without sharing root-specific issue identity.

## Incremental semantics and checking

Produce compact common facts once: reads, writes, calls, local bindings, returns, control flow and provenance. Use IDs/spans instead of copied names/trees. Demand additional facts lazily; do not make compilation pay for a maximal checker record.

Global indexes become collections of per-procedure contributions. An edit or deletion retracts old contributions and adds new ones. Reverse dependencies identify affected consumers. Rendering order is deterministic independently of worker order.

Value-proc classification and checker inference may recurse. Partition the affected call/dependency graph into strongly connected components (SCCs); solve each recursive component as a fixed-point task and schedule its acyclic condensation graph. Never let workers block on a cycle of ordinary query fetches. Recompute affected SCC membership when edges change. Across revisions support retraction and shrinking summaries, not only additions. An unchanged public summary stops invalidation downstream.

Inventory the pinned checker before setting concurrency boundaries. Pure per-procedure checks use the host pool; hierarchy checks use explicit dependency tasks; global checks merge contributions deterministically. Do not assume the current checker is thread-safe or that all compiler resolutions exactly match its inference rules.

## Hosting, scheduling and memory

One daemon per worktree under existing machine-wide admission, priority and daemon caps. A single bounded executor prevents nested Rayon/compiler pools oversubscribing the desktop. Same-revision requests coalesce common work. Cancelling one client does not cancel work another subscriber needs. Long cold checks leave bounded capacity for interactive work.

Read snapshots and serialized publication coexist. Generation is a revision transition: analyze source R, stage generated outputs, admit R+1 containing them, then compile/check R+1. Never mutate files underneath an active borrowed snapshot. Baseline/codemod writes serialize, validate source preconditions and publish atomically. A client must not blindly replay a possibly completed write after a lost connection.

Use one memory ledger for bytes, syntax, facts, images, query values, dependency metadata, pinned revisions and running-job scratch. Count shared allocations once; measure private bytes and working set too. Apply existing total daemon limits rather than granting Analyze another independent budget. Evict reconstructible values first; cap metadata and obsolete revisions as well. Active readers pin revisions, so admission queues work if pinned state leaves insufficient headroom.

Busy clients queue/coalesce; they do not spawn a duplicate whole analyzer after a timeout. Standalone reference mode is explicit validation tooling. Crashes fail clearly or retry only safe read-only work; no partial findings are accepted. Rebuilt consumer libraries initially relink and retire the unified host. Accept/measure that development cost instead of keeping a second production frontend. Session restoration is a later optimization, not a reason to introduce a dynamic plugin ABI now.

## Implementation sequence

Each stage is a series of reviewable lanes using current pool/train workflow. Preserve existing debug tracing; do not edit another active lane in place.

| Stage | Deliverable | Exit proof |
|---|---|---|
| 0. Inventory | Pin checker source/license; enumerate every diagnostic family and Analyze semantic consumer; audit syntax/builtins; reproducible benchmark harness | Every check assigned a destination; fixed-commit cold/warm/edit CPU, wall and memory baseline |
| 1. Native contract | Borrowed body visitor, stable handles, origins/config inputs, builtin coverage, native Sem facade under shadow mode | Declaration/body-fact/location parity on fixtures and real tree; no duplicate AST in native path |
| 2. Shared Analyze | Link Analyze policies to native host; port semantic walkers and generation in bounded groups; reuse source views | Per-group reference findings and generated bytes match; shared prerequisites compute once |
| 3. Incremental facts | Per-proc contributions, negative dependencies, reverse indexes, SCC summary engine | Cross-file invalidation/retraction tests; ordinary body edits avoid unrelated whole-tree walks |
| 4. Checker port | Port declaration checks first, then local/CFG checks and recursive inference onto shared facts | Every diagnostic family matches pinned reference corpus; complete coverage matrix |
| 5. Unified requests | Thin clients, combined gate, common executor/ledger, generation transition and transactional writes | One host, one native frontend; concurrent requests, cancellation, restart and writes proven |
| 6. Cutover | Default native Analyze/checker; remove production ObjectTree/parser and obsolete duplicate caches | Sustained parity/performance; reference executables remain independent CI oracles until explicitly retired |

Stages 2-4 can interleave by consumer. A borrowed transitional adapter is acceptable; constructing and retaining a complete dreammaker ObjectTree from native data is not the endpoint. JSON exports are debugging/parity artifacts, not the in-process data path.

Stage 0 must inspect checker source before estimating the port. This is plausibly weeks of staged work, not a few wrapper changes. Re-estimate from the pass matrix rather than announcing a completion date now.

## Validation and performance gates

Use fixed commits, identical define sets/trees and interleaved reference/candidate runs. Report medians/spread, CPU seconds, peak private/working set, retained memory, allocation owners, query executions/hits, and invalidated fanout. Include quiet and representative loaded runs. Distinguish warm-memory, warm-disk and empty-cache cases, and reply latency from background cache completion. Timing instrumentation must aggregate rather than print per-file thousands of times.

Required scenarios:

- Unchanged request and ordinary body edit.
- Return-summary edit affecting another file; deleted var still referenced elsewhere.
- Changed inherited signature; new declaration satisfying a negative lookup.
- Recursive group edit/deletion, macro/define/include-order change.
- Checker pragma/severity edit; lint scopes/ALLOW/baseline-only edit.
- Generated setter/read transition, malformed syntax and error recovery.
- Game/test alternation, two identical roots, memory eviction and daemon restart.

Independent proof tracks:

1. Compilation: production DreamMaker compile cross-check, dmb-equiv, shared_store_equiv and relevant focused runtime tests. No full DM suite unless integration or user authorization requires it.
2. Analyze: ratchet parity, ALLOW-use accounting, baseline identity and byte-identical generated outputs/codemod edits. No raised baselines.
3. Checker: diagnostic code/severity/message/span/suppression/multiplicity against pinned checker. Preserve deterministic CLI rendering; sorting is a comparison aid, not permission to change output order.

Use seeded errors and differential fixtures for builtins, inheritance, macros, strings/interpolation and malformed programs. A zero-diagnostic master run cannot prove checker coverage. Resolve differences with named reproducers; do not silently drop unsupported checks or replace the native compiler's compatibility gate with self-comparison.

Engineering targets, not measured promises:

| Scenario | Target |
|---|---|
| Warm unchanged all-three | <= 1 s after admission, no repeated syntax/semantic computation |
| Typical body edit all-three | <= 7 s, and <= 2 s overhead over native compilation alone |
| Cold all-three | At least 2x lower wall time and 40% lower CPU than measured sequential baseline |
| Memory | No duplicate AST/object tree; combined measured peak below retained compiler plus existing standalone-checker/analyzer peak |
| Compile-only | <= 5% median latency regression; no eager checker loading |

The 1 GB total goal is not guaranteed by consolidation. Compiler receipts, images and resources already retain several GB. Establish an ownership budget after the vertical slice before committing to an absolute cap.

## First concrete lane

Acquire the pinned checker source, create its pass/coverage matrix, and prototype shared native facts for Analyze's `untyped` plus one checker diagnostic family. Exercise a compile + Analyze + checker request and a body edit, counting actual source reads, parses, resolutions and fact executions. Demonstrate the same in-memory handles and computations serve all three. This vertical slice, not a sibling daemon retaining the old model, is the first implementation milestone.

## Stage 0 implementation checkpoint (2026-10-28)

Implemented `tools/dmb/scripts/unified_frontend_inventory.py` and six unit tests.
The inventory records source hashes and line-level lexical dependencies, native interface anchors,
configuration and explicit missing/unverified checker coverage. It does not certify semantic parity.

Run: `python tools/dmb/scripts/unified_frontend_inventory.py`.
Optional: `--checker-source <SpacemanDMM checkout>`; `--require-checker-source` exits nonzero when absent.
An available checkout is reported as pin-unverified until independently checked.

Current checkout results (files, not registered rule counts):

| Area | Rust files | Direct dreammaker references | Semantic-review candidates |
|---|---:|---:|---:|
| codemods | 4 | 0 | 2 |
| frontend | 1 | 1 | 1 |
| gens | 12 | 1 | 11 |
| lints | 98 | 6 | 36 |
| sem | 22 | 13 | 20 |

All seven inventoried native contract files exist. This does not prove those contracts cover every checker operation.
Full-tree inventory was run twice and was deterministic; all six audit tests passed.

Environment limitations: the session launcher cannot start MSYS Bash (0xC0000142), so lane leasing and
build-slot scripts cannot run. Moving temporary Python tests to the writable workspace fixed their
temp-file failures but did not fix Bash. Local network download failed; the pinned checker source is
not present, so diagnostic-family enumeration remains incomplete. No native build, production cutover,
benchmark, merge or push has been performed. Stage 0 is started, not complete.


## Active compiler lane checkpoint (2026-10-28)

Lane `compiler/unified-analysis`, pool-c2, started at `26044d00aff5`.
Bash, the cargo-slot wrapper and downloads work in this session; the earlier
launcher limitation above is historical.

Pinned checker source was obtained from the exact commit
`0290db5c752fa292f9824521515b603a2afd11dc` (the GitHub commit response was checked).
The codeload archive SHA256 is
`60cd3f4ed8b8231a342d7bedd40b2d292a275cb267a70d06699306706c9ed98c`.
The independent suite-1.11 Windows checker executable SHA256 is
`bafd54168a539e61d8c3f71d9778e92de76d7ffbf11c693541e10be10c9633ba`.
Diagnostic wording/policy ported from that source retains its GPL attribution.

`unified_checker_worklist.json` enumerates 28 literal family names and 103
construction sites. It is a lexical worklist, NOT a coverage certificate:
untagged/forwarded diagnostics, parser diagnostics, builtin knowledge, checker
settings, pragmas, suppression accounting and provenance still require audit.

The first native policy is `ambiguous_not_bitwise`. It borrows compiler-issued
`StatementBody`, checks issuance, preserves the three ordered reference notes,
allows warning/error/disabled policy independently of compiler acceptance, and
covers `&`, `|` and `^`. Fixture comparison is against the pinned independent
checker, not another rendering of native facts. Expanded fixture columns do not
claim character-level inverse mapping through macros.

The optional native body query uses Kind(4) in the compiler's existing
`dm_query::Db`. A private frontend-issued input supplies syntax; graph parameters
hold only weak input handles. Compiler `BodyArena` and archived source queries
receive the same typed syntax allocation. Foreign parser issuances are rejected
although their source text is equal. Dead issuance metadata is collected at the
next frontend admission; values are evictable and recomputable. An estimated
128 MiB admission budget limits this new derived-value family; this is NOT yet
the required total host memory budget or an RSS measurement.

`DMB_UNIFIED_ANALYSIS` opts a retained compiler host into this migration path.
The default compiler path and production checker/analyzer gates remain intact.
This is intentional until parity passes, not a claim that unification has landed.
The read-only `NativeCheckerFixture` source question executes this one policy
in-process; IPC carries findings only and explicitly reports incomplete coverage.
It is not a replacement checker command.

Important remaining limitations:

- Keys are conservative per parser issuance, so shifted/edited bodies cannot
  reuse absolute spans incorrectly, but cross-revision relative-AST reuse is not
  implemented. This does NOT yet meet the warm-edit target.
- The query retains lossless syntax for lowering fallback alongside typed syntax;
  transient lossless clones and the ownership census still need work before
  claiming a single fully shared executable representation.
- The original native `untyped` contributions remain the small assignment-fact
  interface. The follow-up native whole-program policy now extracts value-proc,
  local-transfer, argument-escape, polymorphic dispatch, mutable-field and schema
  facts. It is undergoing independent comparison, not enabled in production.
  Full-tree builtin coverage and the production baseline/configuration adapter
  must still be proved before cutover.
- Checker configuration/pragma integration, the remaining diagnostic families,
  SCC summaries, retractable indexes, transactional generation and thin production
  clients are still outstanding. No production parity or speedup is claimed.


Validation of this checkpoint (not production convergence):

- Source inventory Python tests: 6 passed; checker inventory/oracle tests: 5 passed.
- Native `dm-analysis` library: 31 passed, including policy, binding and SCC cases.
- Query per-key retention accounting: 1 passed.
- Shared native integration: 7 passed (same syntax and memoized resolution,
  concurrent parse-once, changed revisions, foreign issuance, eviction, cleanup).
- In-process checker-question regression: 1 passed; disabled policy parses no body.
- Independent pinned checker fixture: 3 diagnostics matched, including ordered
  notes and unexpanded fixture columns. Full-checker parity remains false.

All Rust work ran through the cargo machine slot, at below-normal priority and
with at most two cargo jobs. No shared compiler was built or published. The
candidate and reference tools use disposable E: caches. No DM full suite, look
pins or baseline changes were used.

The pure `value_equations` solver now computes deterministic SCCs and a greatest
fixpoint without recursive query fetches or Rust recursion. Its tests cover a
recursive group becoming non-value, recovering, splitting and losing a dependency,
plus a 20,000-node chain. The complete native extraction of production value-proc
and schema facts remains outstanding; this solver is not yet its replacement.


### Native return-equation extraction follow-up

`value_expressions` now derives procedure return/result-slot equations directly
from borrowed native syntax. Its semantic host must supply identity-resolved call
and field/argument proofs; it cannot certify a scalar from a function spelling.
Native global-call corpus tests connect actual compiler-issued `ProcedureIdentity`
values to the SCC solver, including recursion and an entity exit repaired to a
scalar exit. This is still NOT the complete production value-proc extractor:
mutable-field eligibility, polymorphic/unknown dispatch, argument escape barriers,
configuration reads, local transfer and value-schema policy remain to be ported.

A seeded malformed body (`return (`) exposed an important native contract gap:
it produces an Unsupported statement with an empty diagnostic list. The new
analysis consumers now use a lazy, shared StatementBody coverage check, rejecting
Unsupported nodes and unresolved/missing pending loop bodies, independently of
whether parsing emitted a diagnostic. Compile-only behavior remains unchanged;
its own diagnostics/acceptance policy is not replaced by this analysis check.
The four return-equation tests passed, and the focused regression covering the
malformed body, missing loop body and valid explicit-empty loop passed.


### Whole-program policy and shared literals (in progress)

The native policy borrows compiler-issued bodies and identity-qualified resolver
answers, solves return/parameter/local/field equations as one SCC task, and keeps
call-source classification separate from internal value-local proofs, matching
the reference policy's conservative boundary. Raw SCHEMA markers use the native
lexer and the existing semantic type hierarchy; they do not introduce another DM
parser. The independent legacy policy and its parser are unchanged oracles.

`LiteralText` now retains native interpolation expressions in the issuing syntax
owner. Emission, typed visits, checker rules and native constant decoding borrow
those leaves. Physical source mappings survive CR removal, continued expressions
and nested literals. Declaration-only strings still have an explicit raw-source
boundary. Unsupported bodies keep the prior lossless registration path rather
than silently dropping unrepresented string leaves. The ownership census counts
retained literal caches without causing a parse.

A seeded comparison exposed the native `in` binding power exceeding assignment,
and inclusion of `in` in a ternary's else operand. The shared primary grammar now
puts membership below both. The additional `ambiguous_in_lhs` policy is implemented
against that same AST; exact follow-token origins it cannot establish cause an
explicit error, not a guessed location. It remains a partial checker port.

The native untyped fixture matches all 36 findings from an independently built
legacy producer: all five fields (rule, file, line, message, identity), evidence
and row order, and multiplicity. The oracle rejects an empty seeded reference
and hashes its producers and fixture inputs. This remains an unconfigured fixture
comparison, not whole-project admission or production-tool convergence.

The shared syntax crate's 123 tests passed. Subsequent analysis and compiler-host
verification is recorded below. No production tool cutover, full-checker coverage,
warm-edit speedup or full-host memory bound is claimed by this checkpoint.


### Retained policy proofs and declaration consumers (2026-10-28)

Whole-program value proofs can now outlive the temporary frontend. Archive and
live paths borrow the same semantic owner and statement syntax; policy scopes
use the proof's exact resolver binding and validate archive/config issuance even
for empty or exempt reports. Configured exemptions are bound before inference.
The owned proof retains equations, SCC results and policy summaries, with weak
input evidence rather than an AST, source arena or copied object model.

The compiler query DB has a value-proof family (Kind 5), with explicit dependency
edges to issued body-syntax nodes (Kind 4). A repeated request shares the proof;
evicting it recomputes inference without reparsing resident syntax. Foreign graphs
and equal-source foreign issuances are rejected. Inputs and expired metadata are
pruned together. This is revision-scoped reuse: it does not establish relative-AST
reuse across shifted edits or a total host/RSS bound.

A bounded daemon migration query executes native untyped policy in-process and
returns findings only. It captures raw schema markers before releasing source
owners and labels its scope `captured_compiled_sources`; it neither represents
noncompiled workspace markers nor applies Analyze baselines/ALLOW/config admission.
Its explicit partial-coverage flag and strict reply validation prevent a client
from treating the fixture endpoint as complete Analyze support. Both executable
checker and policy queries use the existing daemon's worker admission.

New declaration consumers select tracked-list markers and lifecycle-definition
rosters from borrowed native declarations and source occurrences. Their legacy
raw scanners, output emitters and admission remain untouched. Incomplete intrinsic
metadata is an error, not an assumed absent field. Legacy lone-CR display-line
correction still needs a captured-source projection before lifecycle cutover.

Three checker families now have native implementations: `ambiguous_not_bitwise`,
`ambiguous_in_lhs`, and `invalid_set_value`. The separate policy normalizer covers
pinned family overrides, display thresholds, severity aliases and CLI treatment;
TOML loading and inherited proc directives remain client responsibilities. Review
identified further bitwise traversal/order cases, now covered by adversarial
fixtures. All 49 diagnostics across nine independent checker fixtures match in
message, severity, location, notes and order. This does not certify every input
to those families or the remaining checker families.

The build-time pinned builtin extractor validates reference source and macro
hashes before emitting declarations (20 explicit types, 444 field/default rows,
378 callable rows, 28 hierarchy types). It preserves effective macro semantics,
including discarded parameter defaults, and explicitly does not certify current
runtime inventory/ABI completeness. Native metadata import remains to be done.

An ancestry audit found that missing builtin parent facts could omit a legal
object-returning override from a dynamic call's value proof. Value inference and
lifecycle selection now require authoritative ancestry answers. Unknown ancestry
refuses explicitly; it never establishes a negative subtype result. The oracle
fixtures use a generated, hash-pinned reference hierarchy, with incomplete member
inventory clearly marked. Production engine defaults are unchanged.

Current verification: 131 analysis-library tests, 11 compiler integration tests
and the host's native-untyped query test pass. The seeded untyped fixture still
matches all 36 reference findings exactly. Protocol validation, literal
registration, budget and heap-census regressions pass. Repository ratchets pass
and the production DreamChecker run reports zero diagnostics. Rust builds still
emit warnings. No production CLI switch or performance claim is made here; most
Analyze policies/generators and checker families still need ports.

### Captured policy inputs and declaration parity (2026-10-28)

Raw policy inputs now have a separate, immutable boundary beside the compiled
file roster. Compiler-decoded text and Analyze's UTF-8-lossy/universal-newline
view are distinct; ordinary identical views share the original `SourceText`.
Policy-only files never become compiled declarations. Configuration, source
membership and decoded views contribute to policy revision identity. Coverage
remains explicitly limited to captured files, without a workspace-crawl claim.

The opt-in compiler host captures those views through the same `RecordingInputs`
ledger used for preparation. Optional missing files and requested directory
listings are recorded as dependencies. Publication/replay must contain every
captured fact, not merely equal text hashes. Policy, value and body consumers
share one archive issuance; idle release drops their retained handles together.
A conservative 64 MiB capture-admission charge is not a total allocation/RSS
bound. The heap census reports shared text owners and unknown map backing.
The next cohort adds explicit request admission, frozen intent receipts and a
separate externally pinned policy revision. Those changes are not yet verified;
the last verified opt-in runner supplied only compiled raw views.

The base-variable supplement independently matches all 12 reference rows,
including effective source defaults, same-line field order, list/array typing,
record methods and macro origins. Analyze's last-authored initializer differs
from runtime declaration normalization; the policy uses the native authored
ledger to preserve that distinction. Source-definition queries likewise retain
legacy variable-before-procedure and formal-before-override tie ordering.

The complete named `base_vars/records_data_only` rule is ported, with raw source
and configuration inputs explicit. This does not certify the other base-vars
rules or their admission. Checker control-shape/traversal prerequisites and a
bounded `control_condition_static` consumer are implemented; adversarial
literal/constructor cases refuse rather than infer from insufficient syntax.
The independent records-rule comparison matches all seven sites, and the
control-static comparison matches nine diagnostics exactly. These observations
do not establish full lint admission, checker configuration or macro parity.

The last verified cohort passes 192 analysis tests, nine capture/replay tests,
six native-query/protocol tests, eleven compiler integration tests and the
compiler binary type check. The subsequent admission and syntax cohort is still
awaiting verification. Production
Analyze/checker entry points remain unchanged; full convergence and the cold,
warm and edited-run performance objectives are not yet verified.

### Public policy admission and independent checker expansion (2026-10-28)

Explicit `policy_inputs` now travels through the ordinary compiler request,
canonical session configuration and frozen input receipt. A separately pinned
policy revision includes extra sources, configuration bytes and proven missing
inputs; changing only a noncompiled policy input invalidates that pin without
pretending that compiled source changed. Requests without this opt-in retain
ordinary compiler configuration and serialization. The source/capture unit tests
and eleven existing integration tests passed. The real Compile/IPC test exposed
a canonical-configuration omission, now repaired and covered independently.

The next actual IPC run also isolated a Windows launch defect: Compile completed
in about 0.4 seconds, but the client exited while an autostarted daemon retained
its capture pipe. An explicit probe measured client exit at 1.016 seconds, no
pipe EOF after that exit, and EOF after retiring only that owned namespace.
The production repair restricts inherited handles with an explicit
Win32 startup allowlist. Two focused startup tests and the real Compile/IPC
edit/retraction test now pass. Longer idle timeouts or
file-backed test output are not used to conceal this failure.

Eight checker families now have executable native consumers. Fresh independent
comparisons match 72 diagnostics across fourteen isolated fixtures, preserving
message, severity, position, notes, multiplicity and order. That includes the
three flow families and setting placement. One fixture accidentally declared the
builtin `range` proc; it now uses `range_probe` so its unrelated duplicate-proc
diagnostic is not mistaken for an unreachable-code policy difference. The
setting-placement fixture explicitly disables the independently tested
unreachable-code family. Mixed control-policy ordering remains a separate
verification cohort, not an inferred property of isolated-family parity.

Six exact-byte runtime probes compare DreamMaker 516.1687 with the private native
compiler. Five agree in value, length and bytes. They demonstrate that the pinned
checker interprets CR escape boundaries differently from actual runtime, so
runtime semantics are preserved. The sixth exposed a raw-CR admission failure,
then a second emission path bypassing shared literal decoding. The lexer repair
passes two focused tests; the emission repair still awaits verification. These
observations do not certify other grammar or runtime cases.

The staged host expansion reuses 27 existing raw-source policies over shared
`SourceText`, with semantic-model and uncaptured-read attempts rejected before
construction/I/O. Named-rule and configured-checker queries read captured
configuration bytes from the same request. Baseline judgment, global unused-ALLOW
aggregation, generators, remaining checker inference and production CLI cutover
are not implemented by those endpoints. Their coverage flags remain explicitly
partial. Captured fixture limits are admission bounds, not hard CPU/RSS claims.
The expanded cohort, checker builtin metadata import and Windows repair are
being verified together; no complete tool convergence or performance target is
claimed here.

### Verified expanded host checkpoint (2026-10-28)

The real client/daemon test passes in 20.09 seconds, exercising Compile, warm
queries, edits, finding retraction and stale-revision refusal. Six Windows
report-path regressions and the captured raw-provider regression pass. Report
projection equates safe DOS/verbatim paths without rewriting provider keys.
This is a bounded fixture test, not a full-workspace performance measurement.

Fresh independent checker comparisons now match 95 diagnostics across eighteen
fixtures, including nineteen combined literal/control diagnostics and four
parent-call diagnostics. Eight configured families and the bounded parent-call
consumer remain partial coverage; these results do not establish full checker
inference. The 27 reused raw policies independently match ten seeded sites,
notes and annotation-use records against the old executable loader.

The raw-CR lexer and shared-emission repairs pass focused tests. Actual private
native and DreamMaker runs now agree in value, length and bytes for all three
raw quote forms. The runtime/checker CR interpretation difference remains
explicit rather than changing runtime behavior to match the checker.

Per-file raw-policy QueryDb caching and original-owner checker-context expansion
are the next unverified cohort. Production tool defaults remain unchanged;
full policy/generator migration, checker inference, combined cutover and actual
cold/warm/edited performance proofs remain outstanding.

### Original-owner checker and per-file policy graph checkpoint (2026-10-28)

Configured parent-call and bounded undefined-call policies now borrow the
original retained compiler EngineHost, immutable tree, primary BodyArchive and
existing QueryDb. Default-declining resolver provenance rejects foreign or
unproven owners even when bytes and answer worlds agree. No decorated tree,
second symbol inventory or model serialization is used. Four original-owner
context tests and four actual PrepareQuery semantic-policy tests pass.

The existing QueryDb now owns per-file results for the 27 admitted raw policies,
shared file views and interpreted scope dependencies. Eleven graph tests cover
warm zero-recomputation/owner reuse, exact one-file invalidation, scope early
cutoff, configuration absence/presence retraction, concurrent pinned cohorts,
compiler-source revision safety, eviction, budgets and issuance. Four endpoint
and five adapter tests pass. These remain explicit bounded fixture findings,
not full-workspace baseline judgment or certified peak-memory bounds.

The expanded real IPC test passes in 18.66 seconds, including successful compiled
semantic queries and negative findings through the real PrepareQuery owner.
The independent pinned checker comparisons add 40 exact undefined-call
observations: 135 diagnostics across twenty fixtures are now covered. This
still does not certify other checker inference or complete grammar coverage.

Analyzer publication and ENGINE_HASH now account for local Cargo dependency
sources and declared external inputs. Six Bun closure/parser tests and five
Rust closure tests pass; malformed TOML and invalid UTF8 refuse identity. One
strict Python TOML batch validates the captured documents; Bun's permissive
parser is only provisional discovery. Missing Cargo config watches deliberately
favor correctness over warm-build efficiency, which remains unmeasured.
The compiler cache also includes its new Analyze dependency and shared Rust
sources; four isolated Git-fixture tests pass without publishing a compiler.

Earlier failing tests exposed invalid fixture engine/listing receipts and
incorrectly reconstructed Windows query keys. Repairs use the actual retained
engine and issued paths; admission/ownership guards were not weakened.
Production tool defaults remain unchanged. Complete semantic policies,
generators, inference/SCC coverage, thin-client cutover and end-to-end
performance proofs remain outstanding.

### Typed variables, owner accounting and declaration-policy checkpoint

The typed-variable cohort passes 102 focused Rust library tests across syntax,
tree, analysis, codegen, host capture and policy components. The real daemon
Compile/Prepare/query/edit/retraction smoke passes in 22.96 seconds. Independent
pinned checker comparison matches ten additional variable/typed-field errors;
covered checker fixtures now total 145 diagnostics across 21 fixtures, still partial.
The source-only formal-var query excludes runtime value/default overlays. Runtime
and checker share the same borrowed local-type-path projection without imposing
checker coverage restrictions on runtime arrays/stored locals.

The 64 MiB capture-admission limit is unchanged. Its exposed source/config payload
charge now deduplicates actual live backing owners rather than counting identical
views twice; separately acquired equal storage is never ownership authority.
Metadata remains conservatively estimated; this is not a process-RSS or
acquisition-peak bound. Focused tests cover separate wrappers, subranges, memo
capacity, exceptional encodings, independent equal config buffers and cache release.

The native Decl backend reuses all 14 existing rule matchers over captured raw
views and authenticated native lifecycle headers. Certified atom ancestry keeps
manual datum Initialize callbacks excluded; missing ancestry is Unsupported.
Four native tests and the existing legacy classification regression pass.
Independent actual Engine.scan comparison matches 22 sites plus exact consumed
annotations and notes across the 14 seeded rule families. This is complete rule
logic over an explicit fixture, not full-workspace/baseline admission. No new
Decl IPC endpoint or production default cutover is claimed.

The user manually cleared the verified obsolete private incremental-cache files;
read-only checks found zero pre-plan non-lock payloads remaining. Resumed builds
recreate some of those paths, so the old cleanup script now refuses reused
variants/files. No current binaries or lock files were deleted by the agent.
Production Analyze/checker defaults remain unchanged; subsequent acquisition
certificate, remaining semantic policies/generators and full inference work are
not yet certified, and end-to-end performance targets remain unmeasured.

### Acquisition, return facts and complete Init/BaseVars rule checkpoint

This cohort passes 78 distinct focused library tests (including eleven existing
legacy-helper regressions), eleven shared-graph integration tests, and the real
daemon Compile/Prepare/query/edit/retraction smoke in 21.95 seconds. The two
initial test failures were diagnosed and repaired: the frontend capture wrapper
now forwards actual acquisition receipts, and the no-read fixture uses timestamps
outside the existing racy-write window. A separate regression retains that
window's required reread. Init annotation state is restored on success, errors
and panics without changing its original annotation acquisition order.

Independent old Engine.scan comparisons match seventeen Init sites and twelve
sites covering all four BaseVars rules, including exact consumed annotations
and notes. Separate hot-home and candidate fixtures also match. These are
complete rule matchers over explicit captured fixtures, not whole-workspace
discovery, baseline judgment or production endpoint cutover.

The checker adds eleven exact independently pinned diagnostics across authored
return headers and constructor argument roots. Covered fixtures now total 156
diagnostics across 23 fixtures, still partial checker coverage. Initial return
settings borrow the original primary BodySyntax query; unimplemented field
static-type warnings remain Unsupported. The runtime return-annotation parser
was deliberately left unchanged because malformed-input admission differs from
the new strict policy-only token projection.

All ratchets pass. Regeneration rewrote zero outputs; hashes of all 382 checked
generated files remain identical, preserving the preceding zero-diagnostic
DreamChecker result on unchanged DM inputs. No look pins or full suite ran.

Source acquisition now preserves original encoding and private current-read
receipts separately from interned lexical identity, including warm authenticated
reissue. This checkpoint does not yet enable semantic encoding admission or
claim idle lexical-owner reclamation: the guard, retention census and lightweight
lease repair are the next cohort. Production tool defaults remain unchanged;
full policy/generator migration, checker inference, combined cutover and actual
cold/warm/edited performance proofs remain outstanding.

### Shared policy queries, source leases and byte origins (2026-10-29)

The native host now retains lightweight source-acquisition leases rather than
prepared lexical owners in its mapping and policy snapshots. Original encoding
and current-read authority are checked before semantic cache access, including
requests with no checker-policy override. The immutable admission verdict is
reused only with its exact issued mapping. Retention/census tests cover release
of lexical owners, same-decoded-text/different-encoding sources and source/config
hash collisions; this is not a measured RSS or performance claim.

Init, Decl and full BaseVars fixtures use the existing compiler QueryDb through
one cross-file policy node over its existing raw-file and configuration inputs.
Current-view authority stays separate from shared derived source projections;
query parameters keep weak captures to avoid retaining the owning graph.
A real private-daemon test compares all three policies with a separately built,
unchanged old Engine.scan oracle, including warm reuse, configuration edits,
canonical ordering and stale-policy rejection. The boolean-requirement facade
also reuses the original raw and typed matchers; its complete seeded union matches
twelve sites, including macro calls and physical argument lines. It is not yet a
fourth admitted cross-file host policy or a whole-workspace lint judgment.

That integration test exposed Windows DOS/verbatim path aliases entering the
raw roster twice. A private acquisition challenge now permits the filesystem
producer to prove a safe alias using current file identity and metadata. Both
observed provider keys remain in the ledger; one primary source payload/member
feeds policy work. Default/custom providers decline. Replay reissues against the
current challenge and stale, foreign and relabelled proofs refuse. Eight focused
regressions cover these contracts; no byte equality or relative path alone grants
authority.

Checker notes and locations use authenticated original byte positions, including
physical rows inside logical lines and a deliberately line-only single-row macro
receipt. Held or unproved transforms still refuse atomically. The field-static
and implicit-new cohorts share the existing evaluated visitor and original
native body graph; configuration severity/disable behavior has actual-host tests.
Primary explicit-global syntax, selected-reference export and code generation
now distinguish authored root declarations, builtins and member shadows. A
bounded native-versus-BYOND runtime fixture agrees on all six results, including
named arguments and arglist expansion.

Current selected proof: 344 distinct focused library tests, eleven shared-graph
integration tests and both real daemon tests pass. Thirty-one independently
compared checker fixtures contain 158 exactly matching diagnostics. This is the
current selection, not a claim that it is a superset of every earlier checkpoint
or that all checker families are implemented. Independent old-engine fixtures
match Init17, Decl22, BaseVars12 and requirement_bool12 sites with annotation use
and notes. All ratchets pass; all 382 checked generated-file hashes are unchanged.
DM, map and checker-configuration inputs remain unchanged since the preceding
zero-diagnostic DreamChecker run; that run was not repeated for Rust-only edits.
Normal host dependencies still exclude dreammaker. No pins, full suite, native
compiler publication or production default cutover occurred.

Remaining work includes exact variable-declaration token provenance, further
policy/checker families and inference, bounded full-workspace discovery and
transactional reporting, generators, thin-client cutover and actual end-to-end
cold/warm/edited performance proofs. DATA drafts for these are not implementation
or verification evidence until applied and tested.

### Primary variable provenance and typed policy expansion (2026-10-29)

The retained primary tokens now issue variable-name cursors and qualifier facts.
Private warm queries reuse those facts; restored portable headers must have them
reissued by the existing native lexer, rather than trusting serialized authority.
Original field metadata feeds the same borrowed value equations and policy walk.
This adds the complete untyped and untyped-member policy facades, not general
return-type inference. The admitted host roster is now Init, Decl, BaseVars,
requirement_bool and untyped_member in the same existing QueryDb.

Independent comparisons exposed an important source-location distinction:
legacy declaration locations at an included file's EOF can name the parent DME.
The native producer now issues that compatibility cursor separately from the
physical original-byte cursor. BaseVars uses it for legacy reporting and filtering
without losing the actual declaration source. CRLF original-byte positions,
continued declarations, token rebasing and qualifier/list defaults have focused
regressions. Unproved macro columns and transforms still refuse explicitly.
Concurrent preparation also preserves the already-published matching lexical
owner instead of replacing it at the second publication lock.

Current proof includes 81 selected core cases, 21 independent source/untyped
oracle cases, four BaseVars oracle cases, six qualifier checker fixtures with
24 exact diagnostics, and the real five-policy private-daemon comparison.
All known failures from this cohort were diagnosed and repaired; failure-only
reruns passed. The normal native host dependency graph excludes dreammaker and
dreamchecker. All ratchets pass and all 382 generated hashes remain unchanged.
These are selected proofs, not complete-toolchain coverage or a performance
claim. Complete workspace discovery/paging, more checker families and generators,
inference, production client cutover and end-to-end performance proof remain.

### Original-owner reuse, workspace policies and further checker facts

The current host admits complete `player_link`, `weak_raw_read` and `untyped`
policy facades over the same original native body/declaration owners. The
`untyped` host route records its real value-equation dependency in the existing
QueryDb. These remain explicit captured-input contracts; an unissued manifest
alias is refused rather than guessed. The `sparse_slots` generator policy also
has an original-view producer and independent old-generator comparison; it is
not yet the production generator client.

Diagnostic declaration preparation can retain the original native tree despite
an inherited-variable redeclaration that strict compilation rejects. This is an
explicit diagnostic profile, not a fallback parser. An actual daemon test proves
that a following valid compile reuses the same tree, syntax, body inputs and Db,
with one original parse/rebuild. Source, plan, engine and acquisition changes
still invalidate that reuse. Source frames are staged before the final freshness
check, so cancellation or a stale candidate cannot replace the published frame.

Primary local declaration/visibility facts, increment expressions and macro
invocation note receipts now serve additional checker consumers. Reporting a
legacy macro invocation point remains distinct from claiming an original
physical-byte position. Unissued multiline transforms, local-array constructors
and other missing syntax contracts still refuse explicitly; they are not clean
checker results. Independent pinned-checker fixtures cover the admitted cases.

The raw-workspace producer captures its original source and directory closure
once during preparation, then serves bounded pages from that frame. One actual
main-project comparison captured 7,273 sources and matched all 27 admitted raw
policies against the independent old Engine, including sites, notes and ALLOW
accounting (226 output records, two pages and an exact warm-page repeat). It uses
the main DME, not a substitute fixture project. This proves that raw policy group,
not every semantic lint, generator or checker family.

That correctness run also exposed and repaired a daemon idle-clock bug: a long
request could finish after the idle period measured from its arrival, causing
retirement before the next page. Idle age now restarts on connection completion.
Page resource accounting uses one operation-local inventory of existing Outcome
owners, with weak handles in inputs, conservative coordination admission and
cleanup on success, refusal or cancellation. It does not duplicate source or
semantic payloads. Real cancellation is returned as an operational error and
cannot become a cached semantic refusal.

The actual run took 23.922 seconds to prepare and 127.625 seconds for the first
raw query; subsequent page and warm-page requests took 0.188 and 0.140 seconds.
These are observations from one correctness run under shared-machine load, not
benchmarks or an overall speedup claim. Cold performance still needs work.
Production clients/defaults are unchanged. Full inference/checker migration,
further policies/generators, unified installation/gates and end-to-end resource
and performance proofs remain required before cutover. Unapplied DATA drafts
are not implementation or validation evidence.

Checkpoint verification: the affected resource/checker repair selections contain
54 distinct passing Rust tests after one diagnosed fixture repair; the shared
query-graph integration has eleven passes, and the original daemon and three
policy IPC checks pass. Earlier current-cohort proofs include the seven-policy
IPC comparison, original-owner reuse and diagnostic-profile IPC, independent
player-link/weak-read/untyped oracles and exact checker-location fixtures.
Ratchets pass, all 382 compared generated-file hashes are unchanged, and a fresh
DreamChecker run reports zero diagnostics. Its elapsed time was 632.849 seconds
under below-normal shared-machine priority; this was the independent cross-check,
not a native performance result. The normal native host dependency graph has
neither dreammaker nor dreamchecker. The main-workspace proof coordinator and its
bounded-evidence tests are tracked, so its integration entry point does not rely
on ignored working-data scripts. No production defaults or compiler publication
changed, and no pins, full suite or benchmarks were run.

### Original headers, local arrays and effect queries

The next verified cohort retains original procedure header tokens on the existing
declaration syntax owner. Native signature interpretation and the allocation
ledger borrow that owner instead of separately lexing each parameter. This is
not yet a one-parse claim: body and default-expression reparses remain work for
the following cohort.

The original local-variable ledger now owns array-dimension expression roots.
Native ordinary and C-style local-array lowering, checker evaluation and the
ported policy visitors borrow those same roots. Explicit list construction and
implicit array construction retain distinct provenance; unknown source points
are not manufactured into physical positions. Unsupported range-array runtime
lowering and unissued or foreign source receipts still refuse.

Internal QueryDb nodes now cover evaluated body effects, their plan and SCCs,
purity, resolver observations and sleep checks. They use the original callable
and body owners, preserve the old evaluated expression order and distinguish
operational cancellation from a semantic refusal. Their current admitted domain
is bounded; these nodes do not enable the complete checker by default.

Native original-view producers also cover system-accessor generation,
undeclared relation writes and stored references. Independent old-engine
comparisons cover their admitted policies, including constant declaration flags,
parameter qualifiers, implicit construction and exact empty-result controls.
Generator query-graph integration and whole-workspace semantic coverage are
separate remaining steps.

A qualified hierarchy query family delegates to the certified original tree.
Nine admitted type/parent/ancestry observations match the real runtime host.
The evidence separately retains two intentional differences in ordinary
uncertified queries; it does not relabel Unsupported as Missing or false.

Verification for this cohort includes 170 distinct selected core tests, ten host
tests and nineteen native-policy tests passing after diagnosed repairs. The
original-owner, diagnostic-profile and bounded workspace IPC proofs pass. A fresh
optimized main-DME proof again matches all 27 raw policies: 7,273 sources, 226
records, two pages and an exact warm first page. Preparation took 27.141 seconds,
the first query 117.375 seconds, and subsequent requests 0.063 and 0.078 seconds.
These are correctness-run observations, not benchmark or speedup claims. An
initial debug-binary run exhausted the unchanged request deadline; it is recorded
as a failed run, not used as evidence for the optimized result.

Ratchets pass, all 382 compared generated files remain byte-identical, and fresh
DreamChecker reports zero diagnostics (362.326 seconds). All checks are headless.
Production defaults remain unchanged. Full shared inference, the remaining
policy and generator clients, resource admission and end-to-end cutover still
need implementation and proof.

### Shared cold tokens and bounded native generator queries

Native demanded bodies now borrow the original cold token buffer retained by
the existing declaration owner. The formal-path parser consumes the same token
representation without building another owned token-text array. Tests exercise
original code identity, foreign ranges, warm reuse, Unicode, comments and error
locations, and verify that this route adds no whole-procedure lexer call. Body
grammar interpretation and further expression sublexes are separate remaining
work; this does not claim complete one-parse convergence.

The existing parameter signature owner also retains optional default, in-source
and dimension expression roots, with a typed input annotation rather than a
fabricated annotation expression. Unsupported or excessive optional work records
an expression-specific refusal. It preserves the independent type-path receipt
and existing body admission; aggregate optional storage must fit the unchanged
header allowance. Actual body-query tests cover that boundary. Production default
and helper emission have not switched to these roots in this checkpoint.

Internal Kind 11 generator nodes use the existing compiler Db and original raw
file/configuration inputs. Sparse-slot and system-accessor outputs are borrowed
under the existing family gate, so result owners cannot escape eviction and
accounting. Legacy and captured producers share the same output templates.
Captured formatting writes through an admitted sink instead of constructing an
unbounded intermediate formatting string. This remains the explicit bounded
capture interface, not a main-workspace generator installation or public cutover.
Four independent old-producer comparisons match complete output and diagnostics.

Original answer-slot, pooled-weak and binding-history storage now has an
allocator that charges its actual backing Layout before source allocation and
releases it after the actual free. Private wrappers preserve the existing
canonical answer Arc and the lifetime of late resource attachments, including
old runtime aliases, marked bases and weak-only retention. Runtime storage keeps
its existing uncapped behavior. Source-scope publication is still held pending
the full final-fence and resource transaction.

A narrowly qualified std Arc allocation contract records Cargo's actual
compiler, target, installed source and liballoc artifact. A headless standalone
probe matched all nine cases, including weak-only allocation lifetime and the
shared lease's physical free before quota return. That evidence does not itself
enable a source endpoint: profile approval remains false in this checkpoint.
Unknown toolchains must not gain an allocation permit from an address or client
option. Requested Layout accounting is not an allocator RSS claim.

Current focused selections contain 262 distinct passing Rust tests after
diagnosed test-fixture repairs. The generator poison test uses a genuine
preexisting lazy-view denial; an in-producer allocator failure is statically
reviewed but has not been dynamically injected. Ratchets pass and all 382
compared generated files remain byte-identical. Another optimized main-DME run
matches all 27 raw policies, with 226 records over two pages and an exact warm
repeat. Preparation took 21.390 seconds, the first query 137.266 seconds, and
later requests 0.125 and 0.109 seconds under shared-machine load. These remain
correctness observations, not a benchmark or speedup claim. Production defaults
are unchanged, and full unification is not complete.

### Original header consumers and qualified source answers

Native procedure lowering now consumes the existing original header expression
owner for evaluated defaults and input-source helpers. Typed and automatic
lowering, reference capture, source-neutral helper recipes and current diagnostic
locations use that owner; they do not retry a default-text parser or manufacture
a return-statement AST for a helper. Native ABI formal classification similarly
uses original tokens through the existing single ABI policy. Independent
compatibility entry points remain available for standalone, unissued inputs.
Focused tests count actual formal re-lex calls and require zero on this route.
Settings, return annotations, initializer expressions and further body/string
grammar work remain separate convergence work.

The full-project compile exposed an important existing language distinction:
an absolute path inside a parameter header declares a type, rather than a formal
argument. The original syntax owner now retains a separate written declaration
receipt, checks the type against the same native tree, and excludes it from formal
ordinals. This preserves `Heal`'s real `M` and `actual_power` slots and its existing
type-declaration side effect. It does not edit the game signature, normalize an
absolute path into a parameter, or loosen modifier/array guards.

Internal source-answer publication now uses a final freshness transaction with
explicit Required and NotRequested modes. Required failures preserve the prior
published frame; an ordinary NotRequested publication retires the old source
scope without rebinding runtime authority. Scoped reads require the exact
original request, generation, tree, mapping, archive and answer world. They use
the original answer table, pooled values and backing allocators, with actual
source reservations retained until physical owners release them. The retained
heap census includes a generation held only by the current binding. Existing
uncapped runtime/framework baseline and allocator RSS remain separately stated.

The std Arc allocation contract is now enabled only for the exact audited
compiler, standard-library source/artifact and local geometry/ownership hashes.
The tracked receipt records an independent headless nine-case allocator probe
against those actual inputs, including the final-free-before-credit case. Unknown
profiles cannot issue a source allocation permit. Sixteen real source-answer
tests cover publication/cancellation, quota exhaustion, collisions, foreign
owners, runtime-world changes and strong/weak lifetime order. This is not yet a
public source-query preparation plan or a production client cutover.

Stats and action generators now have borrowed original-RAW_FILE producers under
the same existing Kind 11 graph and resource gate. They share the old producers'
templates and intentionally preserve old lexical and inheritance quirks. Complete
output and diagnostics match independent old implementations on the expanded
BOM/CRLF, continuation, quoting and error fixtures. Like sparse-slot and system
accessors, their current admission is explicitly fixture-scoped; it is not a
full-workspace generator installation.

Verification for this cohort includes 354 distinct passing focused Rust tests,
the actual small IPC owner/diagnostic/paging checks, a native production compile
with zero errors/warnings, DreamChecker with zero diagnostics and passing
ratchets. All 382 compared generated files remain byte-identical. No game client,
look pin, full test suite or compiler publication was used. These are correctness
results; production Analyze and DreamChecker defaults remain unchanged, and full
toolchain unification is still in progress.

The optimized actual-repository IPC proof also passes on this checkpoint: the
main DME is prepared from current acquisitions, all 27 raw policies match the
independent old engine, and all 226 records over two pages match with an exact
warm first-page repeat. The proof explicitly does not claim full semantic-policy
parity, production client cutover or complete native compiler integration.

### Source-query clients and operational failure boundaries

The actual typed source-query preparation route now carries an ordered question
roster, including subject presence and bytes, rather than a boolean authority
claim. A real headless IPC check proves source-only preparation skips invalid
ordinary ABI work, keeps the original tree/query owners on warm re-preparation,
and rejects altered or superseded rosters. The CLI's existing two-row JSONL
framing, v2 batch schema and explicit coverage description are preserved.

Checked body demand now carries operational I/O failures separately from genuine
syntax diagnostics through query verification, body arenas, value inference,
effect queries, untyped reporting, ABI preparation and public body exports.
Operational failures escape before reusable semantic results; focused tests
exercise same-input recovery after real eviction and later report demand. The
new checked lowering and artifact-admission APIs retain the original algorithms
and compatibility hooks. Full memo/replay/completion integration and native
settings-provider selection remain unfinished.

Cancellation tests exposed a real retry loop: standard write_all retries an
Interrupted writer indefinitely. Operation-local adapters now preserve the
original error while stopping serializer retries in source-query, policy,
body-model and resolved-query writers. Tests cover mid-stream cancellation,
partial destination writes, unchanged successful bytes and recovery.

Pool policy and declaration-ID generation use the original RAW_FILE/config
inputs and existing Kind 10/11 graph, sharing the existing policies/templates.
The independent old generator matches all 2,186 declaration-ID output bytes and
four diagnostics on the seeded fixture; the independent pool IPC comparison
also passes. These remain explicitly bounded interfaces, not whole-workspace
generator installation or a production default switch.

Selected Rust checks and the source/pool IPC checks pass after diagnosed fixture
repairs. Ratchets passed during this cohort, and all 382 compared generated files
remain byte-identical. The last production compile/DreamChecker result is the
preceding checkpoint; a fresh combined production verification remains required
before completion. No game client, pins, full suite or compiler publication was
used. Full toolchain unification remains in progress.

### Canonical setting storage, before caller activation

Original reusable header owners now retain a lazily issued setting-expression
root with a checked current-source projection. A real include-offset regression
requires the same original body and root pointers across the rebase, with correct
new spans. No AST is copied or shifted after publication. Private retention
anchors preserve body-work charges while literal aliases survive; final cleanup
uses an iterative worklist. Source identity, counter-domain, cancellation,
quota and concurrent-drop controls are explicit.

The additive settings-only provider borrows the existing QueryDb weakly, rejects
foreign rebinding or returned roots, and preserves an actual late cancellation
before returning success. A valid immutable sub-root completed before the parent
cancels can be reused on retry. This provider is not yet attached to normal
requests; Kind4, projected Set consumers and ABI selection remain separate work.

All 46 selected foundation and existing literal regressions pass after fixing one
incorrect private import. The source tree is merged with master a004b31592. This
is a checked storage/ownership checkpoint, not settings activation, a fresh
production compile result or completion of toolchain unification.

### Checked native body consumers and shared setting selection

Native body demand now preserves operational I/O through startup, incremental
selection, memo replay, completion, Analyze policies, effect reports and variable
visibility. A completed worker's I/O failure takes precedence over an earlier
semantic refusal from another completed worker; the semantic-only ordering stays
unchanged. Recovery tests require the original OS error, no reusable failure
outcome and a successful retry on the same source and query owner.

Canonical setting roots are now selected by native Kind4 and the native ABI
setting evaluator. The source-free opaque projected view separates original
expression shape from current source coordinates. Old policy traversal quirks,
statement anchors, assignment boundaries, return equations and generated JSON
shapes remain explicit. Actual ABI-first/body-first, include-offset, one-shot,
cancellation and executable-modifier tests pass. Return annotations still use
the separately inventoried compatibility scalar path at this checkpoint.

The complete declaration and UI generator policies share the original RAW_FILE
inputs and existing Kind11 graph. Independent frozen implementations match all
4,921 declaration bytes with three diagnostics, and the ordered UI file set
(Bundle 444 bytes, Panel 592 bytes) with five diagnostics. These remain bounded
seeded interfaces; whole-workspace installation is not claimed.

The latest core and native-consumer batches passed 35 and 18 selected tests
respectively; one newly affected policy recovery test is in both batches. Five
additional UI policy tests also pass. Compiler/type integration errors and a
zero-match test selector were diagnosed and repaired rather than counted as
passes. The last full production compile and DreamChecker results remain the
previous checkpoint; a fresh combined verification is still required. Analyze
and checker production defaults have not switched, no compiler was published,
and full toolchain convergence remains in progress.

### Return roots, multiple effect targets and tracked-list generation

Native return-annotation path fragments now reuse lazy roots on the original
header owner, without rendering/relexing the fragment or demanding a complete
body before ABI preparation. Five focused tests cover original token/error
parity, actual lowered words/default helpers, warm offsets, cancellation and
foreign-budget refusal. Transitive initializer scalar parsing remains separate.

Effect reports support multiple targets on the existing plan and graph. The
pinned checker prints targets in hash-map order, so independent repeated runs
produce different whole target-group permutations. The documented comparison
preserves family phases and every within-group row, note and source order; it
permutes only complete groups. Four focused tests pass against all 24 captured
old-checker runs, including negative controls for the normalizer.

Tracked-list generation shares the original raw matchers and exact emitter,
using the native tree for declared list types, inheritance and collisions.
An independent frozen generator matches all 12,523 output bytes and three
diagnostics. Native tests cover warm reuse, quota/cancellation recovery and
lexically aliased paths. Verification exposed and fixed two real assumptions:
a retained ancestry index is optional, and a procedure must use an issued
callable header origin rather than the variable-only source cursor. The alias
control also requires zero executable body queries. These generator interfaces
remain bounded; main-workspace installation is still pending.

The source remains on the existing production Analyze/checker defaults. No
compiler publication, game window, full suite, pins or benchmark was used.
Full production verification and complete client convergence remain required.

### Fresh production verification of f526e572b0

The private release compiler passed the official production build with zero
errors and warnings (72.842 seconds cold, with the daemon explicitly disabled).
The sequential DreamChecker run found zero diagnostics. The complete ratchet
wrapper, generator checks and disk/scratch self-tests passed. This is current
source verification, not a warm-build or unified-default performance claim.

Official manifest regeneration added the guarded DOC_SNIPPETS include. A hash
comparison against the older pre-master-merge generated-file inventory found
378 unchanged files and four changed files (actions, declare, plans and stats).
That inventory predates the master merge, so it does not establish regression
or parity for those four; complete independent generator oracles remain the
separate evidence recorded above. No generated output was hand-edited.

Analyze and checker CLI defaults remain on their old production paths. Full
client cutover, remaining generators and initializer first-owner convergence
are still required; no compiler publication or game window was performed.

### Nine complete raw policy families on captured source owners

The existing policies for cooldown, declaration blocks, duplicate input keys,
entry slots, interactions, latent state, pollers, read-back and capability bits
now run over the same admitted captured source owners. The original per-file
27-policy roster remains separate: tree and mixed scans retain file phases
followed by their whole-tree phase, including phase-local annotation handling.
Operation-local direct computation prevents these captured calls from consulting
the old disk caches; that mode grants no source authority and adds no cache.

Eight Analyze tests and three native-host tests pass. Independent full old-policy
runs match all nine complete finding lists, messages, ordering, notes and
annotation-use rows. Frozen original latent/read-back policies also validate the
shared literal-name matcher against their old per-input regular expressions.
Warm same-database reuse, changed source/config, foreign databases, operational
denial, quota/cancellation and recovery have direct tests.

This remains explicit bounded capture coverage. The conservative temporary
reservations admit these complete small fixtures; larger input needs native
per-file facts and count-based reservation, not a raised cap. No workspace
coverage, affected-closure performance, default client or full cutover is claimed.

### Initializer operational transport and shared client report policy

Initializer evaluation, modifier collection, value/key construction, classification,
artifact reuse and parallel aggregation now have checked paths that transport the
actual operational error outside semantic findings and caches. They share the
existing algorithms with the compatibility entry points. Completed sibling
operational failures take precedence over earlier source errors; worker and
cache-admission checkpoints retain the original error before publishing results.

Original initializer handles borrow authenticated primary-chunk source. Their
AST-only runtime recipes retain no source text and require an authenticated
current owner to reborrow it. These are additive interfaces: native initializer
selection remains disabled until the earlier adapter constant-fold path uses the
same original header owner and checked propagation. They do not establish whole
compiler one-parse convergence yet.

The existing report judgement is now one parser-free routine shared with the old
Engine wrapper. It preserves notes, changed-file filtering, rule and source order,
raw/baseline/ceiling behavior and custom/post hooks. Baseline filesystem access
belongs to the client after query delivery, never inside native semantic queries.

Verification passes 45 focused new-contract tests plus 12 existing initializer
compatibility controls. Three incorrect fixture assumptions were repaired and
only those failures rerun: primary preprocessing blanks comments, a runtime-name
fixture needed its symbol interned, and Sites reports use fingerprint source text.
Two test-module paths were also corrected after the first compile. All nine
complete raw-policy oracle comparisons still match through the shared report
wrapper. Logs retain failed attempts and repair evidence separately. No production
client default, compiler publication or game window changed.

### Shared marker-key policy before native admission

The key-index and key/source-call policies are extracted from the legacy
Decls consumer into parser-free routines over borrowed marker rows and the
original raw source view. The legacy wrappers project their existing rows and
reuse those routines; no general DM declaration model was moved into the native
host. The stage-op desugaring is the same shared unique declaration policy.

Both original unit tests pass without the legacy semantic feature. A frozen
independent original key-index and full key lint match all table fields,
duplicate/source order, 16 complete findings across all six rules, annotation
usage and complete report text. This verifies the extraction, not native
whole-lint admission: the remaining authenticated raw-call, entry-op and system
field joins still need their native query adapter and bounded admission.

### Original initializer producer and current-frame source joins

The original declaration header pass now issues initializer coordinates and the
sole original expression slots before adapter constant folding. Checked frontend
builders pass the same existing QueryDb provider and worker context into that
pass. Local/shared declaration cache acceptance checks the completed producer and
same resource counter before claiming a value; a replacement never grafts a new
owner onto escaped old data. Operational failures remain outside findings.

Transitive constant source lookup now has a sealed additive interface over the
same original occurrence target grouping. Exact selected metadata, declaring
owner, current frontend and original source cursor are checked before borrowing
the existing expression root. Its index reservation lives with that physical
index and uses the existing counter. This is not a separate declaration model.
The actual QueryDb caller tests cover early-root reuse, worker cancellation,
current-frame refusal, warm selection and same-source recovery without Kind4.
Native runner selection and the remaining classifier/runtime/static/dimension
consumers are still pending; this does not establish full one-parse convergence.

### As-of report data and unique policy comparisons

Raw workspace result rows retain their whitespace-normalized original source
line from the same captured file. That report data is paired with each site,
charged before allocation, counted in retained ownership and included in the
result fingerprint. It grants no current-source authority. Native file/page
queries propagate typed resource refusal before Outcome publication; constrained
then recovered queries reuse the same input without a poisoned cached error.

The complete key judgement and header/call joins now share the old unique policy.
The complete plans emitter and raw hook discovery are also shared through borrowed
policy rows. Frozen independent originals compare all 16 key findings, tables,
annotation use and report text; the plans positive output is exactly 5,240 bytes,
and its genuine temporary-file failure compares 212 bytes and one ordered
diagnostic. Hook discovery matches all 12 ordered rows, including capability and
world-action contexts. These are whole unique policy comparisons, not proof that
the still-unregistered native reactive-read producer or native keys adapter is
complete.

Across this cohort, 77 distinct focused tests pass. Earlier failures are retained
in separate logs: fixtures initially supplied equal text from different physical
owners, expected a superseded roster claim to stay published, or exceeded the
existing cleanup-depth allowance. Repairs preserve guards and limits. Source
report recovery also accounts for the sink's existing 64-slot allocation. No
production client default, compiler publication or game window changed. The last
full production native/DreamChecker/ratchet gate remains the separately recorded
f526 gate; this cohort has focused Rust and independent policy evidence.


### Admitted body literals and original scalar evaluation

The body demand now prepares literal children from the original parsed body under
its existing admission and physical owner. Header and raw queries do not demand
body syntax. Scalar evaluation shares the original interpreter and carries the
same held admission through transitive roots, including observer-only descents.
The new private scoped scalar consumer and AST-only runtime recipe remain
additive: production runner selection and complete static/dimension/runtime
integration are not enabled yet.

This cohort passed 48 distinct focused tests, native-only Analyze checking, and
the independent plans positive/failure/restoration comparison. Coverage includes
actual cancellation and OS error propagation, same-source recovery, physical
aliases, original constant behavior and model-free report judgement. A fresh
healthy left-deep control confirms the existing cleanup-depth refusal is not a
leaked cancellation. Resource limits were not raised. The body cleanup reservation
is conservative; main-workspace availability and performance remain unproven.
No production client default or shared compiler binary changed. These focused
checks do not replace the final production compile, DreamChecker and ratchet gate.


### Complete initializer source identity and projected borrows

The complete issued initializer plan now joins the original finalized plan with
its actual current frontend and sealed static receipts. Static roots borrow the
same retained statement body and variable RHS. A warm source-prefix change uses
explicit span projection and requires the same body-code identity and termination
profile; equal text from another frontend grants no authority. The compatibility
owned-expression API remains separate from projected native borrows.

Thirty-three focused native tests passed for issued complete plans, current-frame
and foreign-counter checks, one-shot body admission, warm root reuse, projected
source access, owned compatibility hooks and scalar evaluation. The native test
build and native-only Analyze build passed. Two census callbacks and one older
owned-API test needed type corrections; their failed build logs are preserved.
The production runner, dimension consumers and runtime lowering are still not
switched to this complete source factory. This is a verified source-identity
checkpoint, not completed one-frontend client convergence.


### Whole key policy over captured source

The borrowed native key adapter now runs the original complete key policy over
captured marker, call, define and requested system-field rows. Only marker rows
follow manifest order; other facts preserve original file order. It constructs
neither a legacy semantic model nor a replacement type index. The existing raw
first-return projector reserves only recognized entry bodies, and the system
candidate matcher borrows its original Unicode run slices. Operational failures
remain typed and partial findings are discarded.

Checked stages expansion uses an admitted iterative DFS, preserving the original
stages-first order without depending on Rust recursion. Compatibility keeps the
original traversal. Fifteen focused tests pass, including actual OS failure,
quota refusal, same-source recovery, deep nesting and all six rule families. The
native fixture matches all 16 findings, one annotation use and full report text;
the frozen independent original separately matches complete key tables and the
same report. Native-only Analyze checking also passes. This remains bounded
explicit-file coverage: query registration, production workspace admission and
client defaults are separate pending work, with no admission-limit increases.

### Original initializer/query continuation

The explicit source-required startup role now rejects foreign-budget cached
static parents before claiming them and reissues a valid parent through the
existing checked producer. Declaration and procedure-static array dimensions
borrow the original header/ledger roots; genuine no-RHS declaration terminators
are accepted through their exact issued cursor. Contextual body loans return
the actual queried owner directly and record the dynamic body dependency without
a second host lookup. Complete key policy is registered in Kind10, including
the original manifest dependency.

The global/write classifiers share their original policy core, with legacy
source scanning kept as an independent oracle. Across this cohort and its
failure-only/affected-boundary repairs, 58 distinct focused tests pass. Native-only
Analyze checking passes; the frozen full global/write result matches, and eight
complete literal spellings match the independent old lexer. These are component
proofs, not a current production compilation or client-convergence proof.

Native initializer runtime/artifact/ABI selection and complete reactive reads
remain separate work. Full-project global classification also needs compact
facts and bounded temporary windows: the existing conservative per-node
envelope exceeds the unchanged 64 MiB policy limit on the real project. Neither
that limit nor the bounded fixture domain has been widened to claim coverage.

### Original-source runtime and reactive result checkpoint

Original-source initializer runtime, constructor diagnostics, and an explicit
cold ABI path now share the admitted native roots and checked static facts.
Reactive read results are exposed through the existing query engine, retaining
original-source ownership and nested admission checks. The global policy core
uses compact interned facts while preserving the old classifier.

This checkpoint passes 35 distinct focused Rust tests after failure-only repairs.
A separately frozen whole old read interpreter matches six actual native requests
across all ten result fields, including array and diagnostic order. Independent
whole global/write and annotation oracles also match. These do not certify
full-project memory admission, retained ABI reuse across rebuilt requests, or a
client-default cutover. Those remain explicit follow-up work; no limits were raised.

### Retained source reuse and compact policy storage

The explicit source ABI path now reuses original produced roots across genuinely
rebuilt frontend wrappers. Its retained receipts check the physical source owner,
original procedure row, root recipe and admission domain before any warm lookup
or cache claim. Equal source text alone does not certify reuse. Complete-plan
initializer and dimension inputs share the same checked provenance path.

Global classification now interns persistent graph facts and drops admitted
per-body scratch before the next body. Nested retained values keep their parent
charge; errors and unwinding conservatively retain scratch reservations. A native
source-only global producer uses the original compiled roster and active body
query context without constructing a raw-source model. A real 129-include test
covers cancellation, admission refusal, retry, warm reuse and source-read counts.
The old lexical setter-call policy is shared without acquiring excluded code.

The combined focused cohorts pass 35 distinct tests. Complete frozen old/native
global and typed-write results match, including traversal through the real root
ancestor; six complete read results match all ten fields in order. A failed new
fixture assumption was corrected to the observed old behavior, without changing
the frozen producer. This remains component proof: the real cold/incremental
source selection, remaining generators, full-project checker admission and final
client cutover are still pending. No budget or baseline was raised.

### Auto-tracking facts and defensive child-read binding

The existing compact global scan now also produces the exact outside-setter
write facts used by auto-tracking, sharing interned names and the original body
loans. Generated setter files, constructor writes and setters' own fields keep
the old exclusions. The query dependency fingerprint includes these additional
facts even though the historical public Globals JSON remains unchanged; a real
query regression verifies that an outside-only change cannot be cut off.

Auto-tracking's collision/refusal/inheritance decision is shared with the old
consumer. The independent frozen old decision matches the complete ordered
result on the fixture, including refusal text. Explicit authored tracking is
kept as a bit on the existing tracked-name rows, separate from generated-origin
tracking, without building another name table. Native consumer completion and
generated-vs-authored origin integration tests remain pending.

Child read loans now prove the exact receiver, procedure, optional context and
flavor as well as original source ownership. The provider contract rejects
omitted, repeated and wrong-root answers and preserves real IO/cancellation
over semantic failures, including wrapped callback-stop errors. Thirteen
focused native query tests pass. Complete frozen old/native outside-write and
read-result comparisons pass. Oracle-only private file access is projected
through the existing public accessor without widening the production API.
A capture-roster allocation in the shared setter-call helper still needs its
admitted streaming replacement before native auto consumer selection; this
checkpoint does not claim complete resource admission or default cutover.

### Original compiler and auto-inference checkpoint (2026-10-31)

The actual native request runner now selects the original-source scalar,
retained ABI, runtime/classification and cold initializer paths together.
The cold/warm regression compares complete DMB bytes, verifies initializer-stage
and retained-output reuse, and checks that neither coordinator nor worker enters
the old scalar text parser. An adjacent no-RHS array exposed a real source search
bug: ancestor-end equality previously prevented reaching its exact issued leaf
cursor. The repair permits descent at equality while preserving the leaf's
original cursor, kind and declaration-slot checks.

Auto-inference now has shared lexical/candidate/receiver policies and native
producers for actual outside-setter writes, typed receivers, own declarations,
setter definition groups and called candidates. The actual original-source
fixture matches the independent old complete receiver, variable and setter
rosters, owner-vector order and all candidate decisions. It also checks genuine
provider IO, foreign-source rejection, recovery and lazy constant/explicit-state
short circuits. Raw macro-origin checks require the real Analyze raw view;
compiler-decoded text is not promoted to that role.

The combined evidence records 36 distinct focused passes. Complete frozen read
results match six requests across all ten fields, including array and diagnostic
order. Global/write/outside-setter results match the complete old fixture, and
the old/shared decision results match 15 tracked and 450 blocked rows with exact
refusal text and order. Both Analyze feature configurations and the three native
crates' libraries/tests pass metadata checks.

The new 12,000-edge checker-window regression hit its unchanged 300-second cap.
Its process was terminated by the test runner. Inspection identified repeated
full validation of the same immutable builtin profile; a narrowly authenticated
borrowed validation capability is being implemented separately. This checkpoint
does not claim that stress case passed, full-project checker admission, fresh
production/DC/ratchet verification or a client-default cutover. The full
dependency generators and complete raw-workspace scope remain follow-up work.

### Shared dependency and checker graph checkpoint (2026-10-31)

The borrowed immutable-profile proof now validates the original tree once while
preserving exact tree/profile identity on reuse. The unchanged 12,000-edge window
test passes in 91.813 seconds under its original 300-second cap. The profile,
wrong-body, return-fact and actual page IO/cancellation tests also pass.

The native dependency aggregate uses the same source-bound read and global
queries and supplies the actual Kind11 dependency generator. Two independent
legacy fixtures match all twelve ordered dependency fields and complete generated
artifacts (1,464 and 1,652 bytes), including diagnostics. The legacy oracle retains
the complete original producer; its private-access projections are asserted
explicitly and do not widen production APIs. Constructor and fixed-source
allocation refusals now retain their actual out-of-memory error and publish no
successful query result; the failure-only regression passes after that repair.

Actual Kind24 graph and Kind25 SCC-summary queries now consume original page
results through the same query database. Their focused tests pass for original
edges, warm reuse, semantic source errors, IO, cancellation, quota recovery and
escaped ownership. Physical graph-buffer destruction precedes release of its
charge, including when the last public strong handle is already gone or the
database has been dropped. Whole-workspace original-file loans pass their
late-page IO/quota recovery, typed recursive-discovery coverage and 257-file
no-reread tests, including the repaired independent-recorder negative cases.
The combined component evidence records 35 distinct focused passes; only failed
or previously unrun cases were repeated during repairs.

Both Analyze configurations and the native libraries/tests pass metadata checks.
This remains component verification: the remaining read/automatic-tracking
generators, complete dependency fold over workspace loans, ordered checker
reporting, full-project admission, fresh production/DC/ratchet checks and final
client cutover are not yet claimed.

The full-workspace query transport now carries only pre-admitted weak identities
for the actual mapping, query database and workspace capture. It reconstructs a
borrowed guard only after exact owner/revision checks against the current input
frame. A typed operational/semantic split preserves real IO first, while both
successful values and semantic refusals pass final cancellation/current checks.
Five focused tests pass for admission-before-downgrade, foreign and expired
owners, no rereads, cancellation/error precedence and the affected workspace
page paths. The registered-query helper reuses the caller's existing raw-family
gate and creates only one reader budget; this transport alone cannot certify a
completed raw-workspace dependency fold.

Registered computations can now reborrow that scope through their actual query
context. The context's database identity check adds no reads or dependencies;
the callback receives the same mutable context for child queries. Two focused
tests pass for exact database identity, real dynamic child edges, warm reuse and
refusal of a foreign executing context without a published result. The registered
function retains only weak source owners, avoiding a database ownership cycle.

### Original-page generators and full workspace dependency loans (2026-10-31)

Reads and derived reads now use parser-free shared renderers with independent
frozen original templates. Native automatic tracking consumes the same completed
dependency candidates and shared decision policy. Two independent whole automatic
tracking fixtures match complete paths, generated text (727 and 725 bytes), and
ordered diagnostics. The two whole dependency fixtures again match all twelve
ordered fields and complete 1,464/1,652-byte artifacts. Automatic tracking's
blocked/debug decision presentation is not established by the artifact comparison.

Actual full-workspace read/dependency jobs now run as children of the existing
query database and use the current operation's root budget, even when an old
cached child's value is evicted and verified after that earlier budget has died.
The registered functions retain no old budget or strong database cycle. Tests
cover 130 genuine original files, demand-only body parsing, no source rereads,
actual IO, cancellation, constructor/weak-owner admission and callback unwinding.
The generator CLI's test-type source domain has its own completed receipt: unlike
ordinary CODE_DM discovery, that exact old CLI domain includes hidden code files.
Neutral raw-page data cannot be promoted into a finite capture's verified read.

Effect pages retain the original report metadata without retaining syntax or
strong source archives. Their query hashes now cover report-observable fields,
including waitfor/directive and original line changes. An actual cancellation
during hashing prevents publication and permits a healthy same-key retry.

The first runtime batch exposed a real quadratic allocation estimate in hook
discovery: one small marker could exceed the existing 64 MiB limit before its
provider ran. Discovery now shares the original algorithm through fallible actual
row/string growth, with borrowed argument slices preserving the old grammar.
The limit was not raised. Other repairs corrected independent-template projections
and fixture setup; no source guard, output equality or refusal was weakened.
Finite generator artifacts remain bound to their issued capture evidence: the
same cohort reuses its artifact, while a fresh cohort rerenders it but reuses
original-owner-checked read/global/dependency children without IO or body work.

The combined cohort records 50 distinct focused Rust passes and zero remaining
failures, preserving the failure history and rerunning only failed or newly
affected checks. Both Analyze feature configurations and native libraries/tests
were type-checked; the final fixture-only repairs were built and run through the
native focused harness. This is a component checkpoint, not a default cutover.
Canonical shared policy metadata, Plans, complete ordered checker reporting,
full-project capacity checks, fresh production/DC/ratchets, and the real CLI and
generation-stage lifecycle still require completion.

### Generator, staging and raw-policy component checkpoint (2026-10-31)

All thirteen original generator roles now have explicit native workspace paths.
Declare and TrackedLists match complete independent original outputs and ordered
diagnostics; Plans shares the original renderer and authenticates required
callable source loans outside CODE without broadening discovery. The two newly
ported unknown-setting checker families match the pinned original checker.
Unknown settings use a separate diagnostic preparation profile: strict native
compilation still rejects them, and that diagnostic frame cannot be promoted.

Generation can now consume a genuine prepared snapshot into anonymous staged
output and a complete input-freshness closure. Ordered files and diagnostics are
streamed without copying generated text or retaining a source guard or operation
budget. Real filesystem, quota, cancellation, ownership and failure-recovery tests
cover this boundary. The seven source-only bootstrap generators also run from
actual recorded originals with missing registered outputs, preserving negative
input observations. This is not yet the transactional installer or native gen CLI.
The typed map/skin occurrence issue is fixed: those genuine non-text inputs
remain dependencies but are not fabricated into DM source loans. Both the real
bootstrap fixture and the unacquired-source negative control pass. Main-project
bootstrap availability is not established.

Fourteen additional unchanged raw scanners use the native workspace path,
expanding it from 27 to 41 policies. Independent complete old-policy comparisons
preserve findings, annotation usage, configuration and ordering. Registry tests
keep those file policies separate from the nine bounded cohort policies. The
latest component evidence contains 112 distinct passing observations and four
whole-original comparisons, retaining failures and failure-only repair receipts.
That count is not a fresh whole-tree test run, lane stamp, current large-case
availability proof or production/performance qualification. Existing scanner
internal allocation baselines and strict/diagnostic preparation reuse remain
explicitly unqualified.

The actual cutover audit counts 101 Analyze policies. With this cohort, 62 have
some native dispatch: 41 workspace file policies and 21 still bounded to fixture
roles. Another 39 need native dispatch. Those limits, remaining checker families,
genuine typed bootstrap consumers, transactional generation, complete CLI and
custom reporting/baseline hooks, removal of duplicate models, and fresh combined
production and performance verification still block the default cutover.

### Missing-output native question frame (2026-10-31)

Generation can now prepare native inherited declarations from actual recorded
original inputs without constructing the legacy semantic model. Its body questions
use the existing Kind4 body path, with distinct private issuance and the same
query graph. Six focused runtime checks pass: inherited declarations and shared
body demand, dynamic edges and foreign-owner refusal, IO/cancellation/quota
recovery, unsupported selection and all-present decline, and the two source-domain
controls above. An ordinary transient symbol-table clone inherited from the native
frontend remains; this checkpoint does not claim zero allocation.

This frame is not a replacement for the unfinished Auto/Tracked bootstrap
consumers, transactional installer, native command cutover, full checker policy
coverage, or combined production/performance qualification. Those remain explicit
work, rather than falling back to the old parser under a native label.

### Shared policies, diagnostic projection and generation repair (2026-10-31)

DeadlinePolling now shares its original scanner and custom report over recorded
native files, bringing the workspace file-policy roster to 42. The public audit
therefore has 63 policies with some dispatch (42 file policies and 21 bounded
fixture roles); 38 still lack public native dispatch. Hygiene, Resolvers, Tables
and SystemBoundary also have complete internal source-page folds with actual
CODE/MAPS completion checks. Internal callbacks are not public CLI coverage.
SystemBoundary's original cross-file policy, phase order, annotation usage and
source text pass the complete independent original comparison; its custom report
also passes its separate original comparison.

The missing-output Tracked consumer now uses the actual native question frame.
An explicit independent legacy preparation runs genuine source-seven generation,
then a byte-frozen original Tracked producer over the real partial original model.
The whole paths, output text and ordered diagnostics agree with native generation;
unrelated missing includes and changed negative observations remain refusals.
The independent original preparation is feature-only and never native authority.

Three directive families and the new invalid-value producer use original header,
file registry and token coordinates. All nine current whole-checker fixtures agree
with the pinned executable, including the ten invalid-value messages. The broader
original-Debug unit inventory still exposes NaN tokenization and accepted legacy
escape-spelling gaps; these remain active failures, not omitted cases. The current
42-test component batch has 31 passing observations and 11 failures being repaired.
Its 13 independent whole-output comparisons pass. These are component results,
not a whole-project proof or a claim that every original checker family is ported.

A source-free rollback-capable installer, same-host fixed-point coordinator and
explicit native generation client are implemented but still under repair. Windows
runtime checks found that a strict directory guard blocks child renames, and that
freshness checks must retain the exact recorded generated-output membership
policy. The dedicated publication guard and membership repairs await runtime
verification. Server transport and genuine Auto bootstrap remain separate pending
cohorts. No default native command cutover, removal of all duplicate models,
full-project capacity result or combined performance qualification is claimed.


### Component repair checkpoint, 2026-10-31 13:36 CDT

The failure-only repair sequence is now green. Native publication uses a
separate directory guard that permits its own atomic child replacement while
preventing deletion and reparse replacement; Windows runtime controls exercise
that behavior and release/recovery. Freshness retains the exact generated-output
membership exclusions. Snapshot binary encoding now always writes its positional
directory field, including an empty field, while preserving the existing JSON
omission contract. Both empty and nonempty actual observations round-trip.

The checker retains primary literal spellings even when the native runtime
correctly refuses their decoded value. Complete original literal and Debug-word
inventories pass. The compact ternary fixture was corrected using the pinned
original checker: `a?b:c` is rejected, `a ? b : c` is accepted, and bare `new`
remains accepted and covered. The explicit compact negative control passes.

Fresh native and analyzer type checks passed. The final six focused repair
checks all passed; preceding successful observations and the thirteen independent
whole-output comparisons are preserved in their separate receipts rather than
presented as a new whole-project run. No default cutover, main-project clean gate,
complete checker/policy coverage, or performance qualification is claimed here.


### Auto generation and resident transport checkpoint, 2026-10-31

Missing-output Auto generation now consumes genuine native generation questions
and the original source acquisitions, with shared canonical facts, dependency
reads and typed setter selection. It preserves required callable sources outside
`code/`, uses the existing body query graph and denies quota, cancellation,
foreign-owner and IO failures without publishing partial findings. Four actual
host controls pass, including warm body-query reuse and existing target grouping.
The independent original Auto producer matches both complete generated artifacts
(727 and 725 bytes) and ordered diagnostics. That artifact comparison does not
claim parity of every decision/debug presentation field.

The explicit daemon generation request now uses the existing resident service,
serialized host and request lifecycle. Nine controls pass for actual check/write/
warm behavior, bounded fragments, final seals, real IO failures, stale or malformed
responses, and check-mode replies that falsely claim writes. The standalone
Analyze generation client remains explicit; this is not a default cutover.

The original definition-directive warning gate is also integrated. Its five
native controls and three complete original-checker fixture comparisons pass.
Unused absent generated registry paths decline restricted generation before a
second declaration parse; unrelated missing includes remain failures.

The shared report/baseline finisher passes five independent original-policy
comparisons. Source discovery, all selected custom/post-policy evidence and the
public full-report route remain separate obligations. This checkpoint has 25
focused component passes and six independent oracle observations, with fresh
native/analyzer type checks and no whole-project/default/performance claim.
The full cold-start fixed-point coordinator and remaining question consumers
remain under integration; no complete-convergence claim is made.


### Cold generation, checker access and report integration in progress

The remaining generation question consumers and the cold fixed-point coordinator
are now connected to the same host. Three fresh independent purpose comparisons
pass: the original basic producer, the original cold producer, and byte-for-byte
six-purpose output equality. The current combined component run exposed real
failures rather than establishing complete convergence. Repairs address an
incorrect fixture configuration intent, source-only syntax traversal, recursive
list projection and authentic synthetic diagnostic locations. The original
private-procedure fixture remains unchanged; its whole-output comparison must
pass after those repairs. Physical source-error propagation remains under test.

The explicit native check and baseline clients now assemble the selected raw
policy pages with captured source text, whole-file ALLOW digests and interpreted
scopes. A private completion capability requires actual typed discovery to cover
the selected policy roots; the earlier partial raw endpoint cannot claim that
completion. The clients currently admit only 41 audited generic policies and
refuse policies whose custom evidence or post-processing is not yet ported.
They do not replace the default Analyze commands or claim full policy parity.
Compile checks and focused runtime controls for this integration are pending.


The next verified checker cohort adds diagnostic-only duplicate procedure values
without permitting them through ordinary compiler admission. Five native controls
and three complete original-checker comparisons pass, including the disabled
warning case, which retains the original untagged declaration error. Both original
private-procedure fixtures also pass without removing any diagnostic rows.

The shared report client and newline/digest repair passed twenty focused controls
in their repair cohort; five cold-generation controls still failed. Subsequent
header and first-I/O-error repairs passed their direct controls and advanced the
same cold tests to a missing native body-input attachment. The narrow attachment
repair is applied but has not yet been verified. Real command/baseline equivalence,
the remaining keyword checker, auxiliary policies and default cutover remain open.


### Source-bound report and cold-generation checkpoint, 2026-10-31

Cold generation now installs all thirteen generator families on the same host and
reuses the final body-query inputs on an unchanged follow-up. The actual cold/warm
regression and retained prepared-owner regression pass. An independent original
producer, built without `native-policy`, converges through the original eight/five
stage loop in three passes. Its complete final files and ordered diagnostics match
all thirteen native families on the shared fixture. The earlier original `cold`
mode remains a one-phase observation and is not substituted for that fixed point.

The source-backed Hygiene, resolver, table and system-boundary report controls pass,
as do the complete private grep producer controls, including compiled nontext maps.
The ALLOW validator uses actual complete registration metadata: an independently
captured pre-move registry matches all 106 names and 101 registration entries after
the move. Complete known-name metadata does not certify complete policy execution
or authorize a full unused-ALLOW report. That public route remains disabled.

The keyword call checker passes its seven source, order, builtin and failure controls.
The argument-error checker now has authentic builtin-profile fixtures, actual ledger
quota controls, typed I/O and unwind recovery, and the original distinction between
an exact-owner private call and a different static child receiver. Missing-profile
admission refuses before body parsing. All verification failures observed in these
cohorts have passing repair receipts; these are separate focused runs, not one
whole-project proof or a recovered lane-ready stamp.

This remains an explicit integration checkpoint. Mixed source/builtin callable
selection, filter values, remaining checker diagnostics, public report composition,
and remaining semantic policies are still under development. A further prerequisite
is a genuine native analysis-default context: the pinned original preprocessor uses
build 1666 and checker-specific predefined macros, whereas ordinary native compilation
uses build 1687. Those contexts must not be equated merely because a template matches.
Native analysis must use the same frontend and query system with correctly admitted
context dependencies. No default cutover, full-main-project gate, complete checker or
policy parity, total-memory bound, or performance target is claimed here.


### Callable ordering and explicit command proof, 2026-10-31

Mixed source/builtin callable groups now preserve the original formal/builtin/
implicit value positions, predecessor selection and displayed ordinals. Ten focused
ordering/control tests and five current-source Keys tests pass. Four further Keys
policy/oracle controls pass, including quota and stopped-provider behavior. An
independent immutable-original producer matches all five complete native Keys
records (ordered sites, notes, ALLOW use and digests, failure result and text).
Keys is still a private selected producer at this checkpoint, not a public/default
policy route. Its hard-message policy does not require invented source-line text.

The real command proof also passes for scheduler, qdel_src, deadline_polling,
sys/hygiene, sys/resolvers, sys/tables and system_boundary, including the exercised
raw/CI/thin/warm and baseline seed/update paths. Complete output, status, baseline
files, configuration bytes and ALLOW accounting are compared. This is seven
executed names, not proof that every admitted policy has run. The test-owned daemon
retired successfully. Valid explicit proc declarations and a genuine local static
list getter repair the paired fixtures; no lint behavior or positive assertion was
weakened. Four full argument-checker and three keyword-checker original comparisons
also pass after the callable changes, including both mixed implicit/parent cases.

Public Keys delivery, the full filter family, remaining untagged checker cases,
analysis-default preprocessing/diagnostic-only retention, remaining semantic policy
adapters, default cutover and main-project/performance qualification remain open.
No whole-toolchain completion or lane-ready stamp is claimed by this checkpoint.

### 2026-10-31: original analysis context and source-policy delivery (in progress)

The native frontend now has an explicitly admitted original-checker preprocessing
context on the existing host, prepared-source pipeline, retained variants and query
database. It is distinct from ordinary compilation; a diagnostic-only owner cannot
be promoted to a runtime ABI, including when it has no errors. The previous analysis
owner and its retained declaration records participate in the existing deduplicating
heap census. Unexposed allocator/index geometry remains explicitly unknown.

The context installs the pinned 104-entry macro environment and original conditional
arithmetic/definition-stack behavior. It preserves a shared resident host and query
database while isolating incompatible request and retained-variant identities.
Targeted tests found a real preexisting publication-order defect: QueryAttempt bound
the old query-state Arc before engine selection switched variants. The repair binds
the actual selected variant before source capture and restores the exact moved
publication metadata on the stashed predecessor. Existing cached-publication behavior
is unchanged. Real Native/Original/restoration and metadata failure controls pass.

The evaluated-expression walker also gained the filter, relative navigation, catch
parameter and static-reference slices. These borrow existing syntax and resolution
owners; they do not add a second expression parser or semantic model. The static
reference controls cover inherited receiver identity, real proc/verb/builtin kind,
ignored reference arguments, foreign scopes, actual first-I/O failure, cancellation,
quota refusal, unwind and warm reuse. The filter's previous eight-versus-nine-row
mismatch is resolved by using the actual original context rather than changing the
old flag algorithm or suppressing a row.

Verification for this cohort is deliberately scoped:

- All three nominal build routes passed: native compiler, native-only Analyze, and
  reference-enabled Analyze.
- The initial 29-test context/static batch had 25 passes and four failures. Repairs
  were verified by running only those four failures and two new metadata controls;
  all six passed. Analyze's independent original constant-display test also passed.
- The independent original-tool comparison now passes for all 104 defaults, the
  complete guarded type/parent graph, and the full canonical expanded program.
  A paired fixture correction kept a multiline argument inside parentheses.
  The reference observation transport now preserves actual token punctuation;
  its previous pretty-printer had silently discarded braces and semicolons.
  Actual implementation fixes distinguish condition buffering from ordinary body
  expansion and preserve the original context and location dependencies through
  parameter substitution. Four exact preprocessing controls also pass, including
  formal parameters named __FILE__/__LINE__ taking their actual argument values.
- Public Keys paging/whole-report controls and the fresh actual-command proof pass.
  All five fixtures match complete original check/baseline text and status through
  direct and thin-client delivery; captured configuration stays unchanged. The
  composite command proof took 169.578 seconds and retired its private daemon in
  0.11 seconds. It also exercises the seven previously qualified report names.
  This is not execution of the entire admitted roster, default generation, or
  the full registry's required-list validation. The three selected client and
  old registry-contract tests pass. The original complete registry contract was
  captured before metadata moves: 101 ordered descriptors and 55 required-list
  entries, with verified source, artifact and test provenance. Capturing that
  contract does not yet implement native global required-list validation.

None of these results certifies full checker coverage, all Analyze policies or
commands, a production default switch, a whole-project combined run, or the stated
performance objectives. Several additional semantic/raw policies and the complete
ordered checker union are still being implemented. Analyze's default legacy
Tree/Sem command routes have not yet been retired. Use the existing gate-test
profile for subsequent Analyze test harnesses; the optimized binary profile used
for this cohort's test build was unnecessarily expensive.

### 2026-11-01: semantic policies and checker type/range integration

The extracted semantic-read and untracked-input policies now share their unique
policy logic with the legacy reference route. Their focused whole-report tests
pass for all six semantic-read and four untracked-input cases, including ordered
ALLOW consumption. Genuine current-source ownership, manifest handling, bounded
allocation and failure-ordering controls pass. The loop/range checker family also
passes all five selected host/dispatch controls, and physical-source, source-value
predecessor and parameter-cursor controls pass.

The initial batch had 23 passing tests and five failures. The native runtime
lookup/checker-source absence mismatch and missing original builtin variable
inheritance (`/atom::name`) were repaired. All declared-type controls, the
same-query-graph missing-to-declared transition and both builtin declaration
controls pass. Four independent whole-fixture loop/range and declared-type
comparisons against the pinned checker also pass exactly.

The next 32-test batch has 28 passes and four failures. Complete native registry
metadata matches all 101 originally observed descriptors; shared global list
validation matches the original whole-registry loop. Public rejection of a
missing unselected list, strict client report families and shared command argument
controls pass. The remaining failures exposed Windows verbatim-path spelling in
actual root checks and unnecessary byte-column requests by line-only consumers.
Those repairs are applied; failure-only verification is pending. Adding the next
switch family also exposed missing recorded EOF facts in the compact coordinate
projection, caught by the cheap type check before another test build.

No expected diagnostic, baseline ceiling or fixture source was changed to hide
these failures. The independent end-to-end ten-case semantic comparison, complete
checker union, remaining command/policy cutover, main-project proof and performance
qualification remain open. The production default is still the legacy route.

### 2026-11-01: source-path, switch-cursor and full-subject integration

The three Rust compilation configurations pass with the complete required-list
metadata and explicit public semantic reports. Nine focused parser/source-mapping
controls also pass, including real inline trailing semicolons, continued else
ownership, typed cancellation and completed-reader invalidation.

The strict independent ten-case semantic comparison still failed after the first
path repair: report paths and annotation usage were corrected, but a reverse
compiled-file lookup still lost definition identities and READS_AS accessors on
Windows. The subsequent repair selects only the actual issued compiled-file
roster; the comparator and original expected records are unchanged. Its runtime
comparison is pending, not a qualified parity result.

The original Analyze subject issuer is now integrated for actual include-bearing
manifests and for absent, non-include or invalid-UTF8 manifests. The latter use a
private generated include header over the genuinely discovered CODE files, with
physical manifest evidence kept separate. Compilation passes; its four-case
independent type/parent comparison and current-frame controls are pending.

The once-per-body checker union, remaining policy ports, original-context
generation, default command cutover and main-project/performance qualification
remain implementation work. No default routing or full-task completion is claimed.

### November 1 integration checkpoint (not completion)

The genuine Native two-file braced include compatibility control passes after a fresh dm-tree harness build. The previous harness cache had been removed; the first rebuild hit a shared sccache connection reset, and the serial retry succeeded. Eight complete-source lint ports and their public adapters, the switch-range bridge, and the declaration/init/base-vars/requirement-bool complete-source adapters are now integrated with exact preimage/postimage checks. A missed aliased switch destructuring was found by Rust and fixed. Combined configuration checks and runtime qualification are pending; these changes do not establish full 101-policy coverage or activate a new default command path.

### November 1 runtime qualification and repairs

Fresh builds passed the Native, Native-only Analyze, and independent-oracle
configurations. The bounded parser/analysis/tree controls passed eleven tests;
the Windows include-prefix control also passed. Complete independent comparisons
passed for Tracked (seven cases/fourteen records), nine raw policies (eighteen
basic/configured reports), declarations, init, base vars, and boolean requirements.
Actual original/direct/thin CLI comparisons passed all nine raw families, all four
declaration cases, and all six init cases, including baseline/configuration bytes.
Every owned CLI namespace was retired by the proof runner.

The first large Native batch exposed real report-validation/admission defects and
incorrect fixture assumptions. After the reviewed repairs, its focused follow-up
passed nineteen of twenty-two checks. Analyze passed twenty-five of twenty-six.
Remaining failures concerned synthetic-manifest admission and two fixture setup
errors; their source repairs are applied but require fresh verification. One deep
receiver-chain test also needed the primary parser's actual Assign node. No
expected production output was re-recorded to hide a discrepancy.

A raw-byte audit caught copied Unicode test literals being re-encoded through the
Windows default codepage. The original Greek controls and multibyte fixture bytes
are restored, independently checked against raw HEAD/preimages, and have explicit
regressions. Frozen original reference sources remain byte-exact.

Additional checker phase aggregation and semantic/raw producer packets are in
progress. These selected-cohort results do not establish complete checker coverage,
default-command cutover, cross-revision body reuse, or final performance targets.

### November 2 shared literal and acquisition qualification

The shared lexical values now retain their actual integer/float kind and bits,
resource path, and producer-issued normal/raw/generated string mode. Compiler,
checker and constant-evaluation consumers consult those values before displayed
spelling. Raw acquisition admits the physical allocation before reading and adopts
the same retained buffers into the existing source ledger; original I/O failures
are preserved rather than recorded as missing files.

All four current metadata configurations pass: core compiler crates, Native,
native-policy Analyze, and the combined independent comparison configuration.
The focused core/checker/bytecode batch passes 107 distinct tests. One new test
incorrectly required an unoptimized numeric instruction; it now compares the
complete code against the ordinary parser and existing emitter, which also uses
compact integer instructions. An independent, headless DreamMaker compile confirms
the three string-mode payloads in its DMB string table. No game world was started.

These results qualify those particular boundaries, not the full task. Genuine
streamed preprocessing/declaration activation, demanded-default ownership transfer,
the remaining policy ports, whole-body inference/retraction, default routing and
duplicate-model retirement still need integration and qualification. Draft-only
macro-factory tests absent from the real test registry are explicitly unqualified.

### November 2 streamed syntax and resource boundaries

The shared final token buffer now retains one immutable allocation across primary
and header consumers. Demanded defaults, parameter-source expressions and array
dimensions can lend their already-parsed expression roots to the existing native
parameter metadata without a second Pratt parse. Focused tests cover identity,
foreign-owner rejection, stopping before future formal tokens, nested delimiters,
and release of admitted storage. The shared-stream cohort passed twenty tests;
the subsequent dimension/source and macro-stack cohort passed six. These are
component proofs, not activation of the complete source driver.

The original conditional-value kernel passed six focused tests. A separate
resource wrapper for the existing macro dictionary passed five tests, including
quota refusal before cloning, unchanged state after refusal, and release of old
history before retaining the final metadata map. Its conservative allocation
envelope is admission credit, not an asserted heap measurement. Driver integration
must keep the final map and its credit together and must not introduce an
unfunded deep clone through a public plan.

Independent observations of the pinned parser show that the tools have distinct
demand frontiers: Analyze's real 8192-token, 64-batch protocol can report a later
macro-arity error after an earlier parser failure; DreamChecker's lazy path does
not demand that later input. The batch counts indentation-processor output, not
raw newlines. A separate include-inside-expansion fixture produces the included
definition's value in both original profiles. The unified driver must preserve
these differences rather than flattening the two transcripts.

Complete formal/body diagnostic ordering, the real source-driver joins, remaining
policy ports and full-model/default routing remain unfinished. Passing the
component tests above does not qualify those paths.

The setter comparison exposed a real frontend defect: an absolute static-scope
call inside a procedure was normalized to root indentation and offered to the
formal-declaration observer. A focused regression failed on the actual current
source before the correction. The shared structural cursor now preserves a body
scope whose physical indentation is known; that regression and four dedent,
namespace and include-prefix controls pass. Ambiguous Original indentation after
an expanded include remains explicitly unavailable until the genuine indentation
producer supplies its provenance. Whole-rule qualification is recorded below.

The repaired comparison passes all 27 setter inputs, each with more than
140 source files. The complete op-order comparison also passes its 30 inputs:
ordered sites, ALLOW usage, full report text and failure state match the immutable
original implementation. Seventeen selected policy tests pass, including quota
and first-I/O-failure controls. These prove the particular DATA folds and report
contracts; native-host authority checks, complete source-driver activation and
default routing remain separate unfinished work.


### November 2 retained formal diagnostics and raw coordinate controls

The same formal producer retains actual annotation unions, var/static/semicolon
notices and the ignored post-in annotation. Returned diagnostic rows retain their
admission credit; the formatter preserves the original integer-token display.
Eighteen selected syntax/tree tests pass, including the existing static-scope
regression and the ordinary-compiler annotation partition control. This does not
cover every default-expression grammar form: intrinsic input/locate clauses and
binary-in default extents are still being joined to the genuine Pratt producer.

The existing source decoder now supplies allocation-free sparse point geometry.
The frame must fund the emitted BOM and legacy-byte exception rows and bind them
to its actual acquired source. Lookups reject BOM and UTF8 interiors and accept
real EOF; geometry alone grants no source identity. Three focused controls pass.
Two bootstrap controls pass for the exact default/caller recipe, ordered issuance,
quota-before-copy, atomic rollback and a real first I/O fault on a fresh operation.
Those bootstrap controls use a callback stub for token production; they do not
qualify productive initial lexical expansion or full source-driver activation.

The combined core result is 23 distinct passing selected tests. Eight small public
native-host tests also pass: strict input-opening errors, genuine source failures,
retained diagnostic transport, exact escaping, quota bounds and fresh-operation
recovery. Five selected Analyze tests pass, including the complete setter and
op-order comparisons. The Sys reactive comparison matches its first ten inputs
but still exposes a missing plain-line receipt on BOM/CRLF input; its repair is
under focused verification. No external DreamChecker executable or game world
was started for this batch.


### November 3 joined raw/header primitives

Four actual metadata configurations pass: core library and test targets, native
host targets, native-only Analyze, and Analyze with independent legacy oracles.
This is type qualification, not runtime equivalence.

The earlier core run recorded 61 successful selected assertions across the
initial run and focused repairs. The macro expectations called out below were
subsequently found incorrect and are not retained as parity evidence.
They cover default-expression partitions, retained messages, shared parameter
storage and BODY adoption, raw coordinates, logical cadence,
conditional transitions, trace callbacks and operational failures. The complete
workspace controller and default frontend are not activated by those tests.

The run repaired a driver that could resume after failure, incorrect unary
punctuation classification, and loss of the original retained I/O error. The
arena test now drops its still-owned emitted token before requiring zero storage.

Sys, Lifeforms and handler fixtures now capture raw and compiler-decoded views
from the same initial read. The raw view preserves BOM and uses the real Analyze
newline normalization. Production already follows this contract. Reference
reports are unchanged. The complete comparisons now pass all 11 Sys, 27 Lifeforms
and 17 declared-handler inputs, each with more than 140 source files. Sixteen
distinct selected policy controls pass after failure-only repairs for sibling
scratch scopes and the shared canonical null-term classification.

Full controller traversal, rich notices and mapping, structural partial-TU
purpose, remaining policy admission, checker inference, default routing and
duplicate-model retirement remain unfinished.

### November 3 macro-stack correction

Review of the actual pinned `DefineMap` found an incorrect assumption in three
earlier macro controls. Definitions push onto a stack and `#undef` pops it,
restoring the previous definition, including `FILE_DIR` and builtins. The prior
replace/remove expectations and their passing results are superseded, not parity
evidence. The implementation and focused controls have been corrected against
that source and an independent pinned-library observation. Native caller-defined
bootstrap values are an extension; their existing effective-map precedence stays
unchanged and is not presented as an upstream command-line contract.

The independent pinned-library observation now passes both authored-stack and
builtin-shadow/pop fixtures, with actual invocation values and line/columns.
The source, fixtures, executable and output hashes are recorded together; this
ran the parser library, not the external checker or a game world.

The next selected core cohort has 35 distinct passing controls after two
failure-only repairs. It covers the real raw-to-primary handoff, callable stop
frontier, retained macro trace, inactive-definition drain, conditional EOF
history, typed interpolation, literal decoder state and partial-purpose refusal.
Two new archived-template controls borrow the exact existing parser input and
same issued fragment owners, including shifted views; missing facts or changed
input refuse rather than reparsing. General archived punctuation identity remains
unissued until its real producer supplies the ledger. These component results
do not qualify complete controller traversal, default routing or model retirement.

The next policy cohort records 19 passing selected controls and two genuine
failures: complete silicon-entry reports and output-signature reports refuse
with unissued Original parameter metadata. Their expected reports are unchanged.
Those ports are not qualified until the streamed primary/formal binding reaches
the real frontend handoff. The shared scalar actor judge, partial-input recipe,
selected ALLOW tree plan and output judge controls do pass.

Incremental subtree replanning now forwards the same admitted generation reader
and omission set, and returns a real read failure without retrying a full pass.
Both new regression controls and three existing subtree reuse controls pass.

The bounded-delivery/history/colon cohort now has 25 distinct passing selected
controls after repairing its genuine callable fixtures. Four source-origin
controls also pass, including exact receiver-frontier trimming and refusal of
foreign same-offset/zero receipts. Current core, native host, native-only Analyze
and legacy-oracle metadata configurations all pass after repairing the actual
full-ALLOW integration types and unintended cross-family guard insertions. The
two unissued-header policy failures remain open; no default cutover follows.


### Productive source handoff checkpoint (2026-11-03)

The real bounded producer now feeds the same primary/header owner and retains a
restricted diagnostic plan rather than converting it into a compiler plan. Four
interface configurations passed metadata checks before the latest conditional
successors. The real full/purpose-barrier header-and-body control passes after
repairing newline token classification in the shared transport. Empty physical
files and LF-only files now retain their actual final-newline locations; three
independent pinned-library observers supplied the location/condition evidence.
An earlier test assumption that an empty physical file has no origin was false.

Nine recorder controls pass after a test-only typed u128 codec repair. The
actual output-signature policy comparison now passes with genuine streamed
parameter metadata and no BODY query. The silicon whole-policy comparison reaches
its ALLOW case, where an incorrect cross-phase deduplication was identified:
legacy raw-file and semantic Sinks record distinct uses. Its repair preserves
actor-phase deduplication and awaits the focused comparison rerun.

The remaining malformed-formal prefix failure is still under investigation.
Derived cold-host/query integration, structural handler integration, unavailable
preparation witnesses, literal-transform resource closure, checker inference and
retraction, default routing and duplicate-model retirement remain unfinished.
These component results are not a whole-source gate or a completion claim.

### Actual host and diagnostic boundary checkpoint (2026-11-03, later)

The restricted notice owner now has a real native report writer and source-epoch
replay owner in source. The integrated attempt defers only its own preparation
output, so its report can emit once; standalone preparation keeps its independent
output. Pressure release explicitly requires re-preparation. These new report,
fatal, warm-replay and first-writer-error controls have not yet run. Review also
caught and fixed an adapter that returned Interrupted after a real output error:
write_all would retry that sentinel indefinitely. The actual first error remains
stored separately; the sentinel is now non-retryable.

The latest public host repair run selected 13 failed or new controls: five pass
and eight fail. Four passing controls prove actual independent second reads,
changed and deleted root payloads, foreign resource-lender refusal, and recorded
replay; the fifth preserves Windows noncanonical metadata lookup semantics.
Six failures identify the real workspace join still expecting prepared-cache
acquisitions instead of the actual exact-read leases. The other two expose a
missing filesystem-alias delegation in the fixture and an invalid-path metadata
boundary. Those two repairs are in source; the exact-lease join is being repaired
without overwriting the independent first marker observation. No passing host
report, current-source stamp or full-policy qualification is claimed yet.

The fresh, exclusively owned BODY literal geometry path has three passing
controls covering retained allocation identity, foreign/shared refusal, quota,
first IO, and neutral static data. It does not qualify mutation of shared legacy
literal templates. Independently pinned library observers now qualify 39 further
condition cases with unique package/binary identities, exact source and executable
hashes, ordered case rosters, and actual output. New conditional constructor,
prefab, compound, delimiter, RGB-warning and pragma cases are in source and await
their implementation tests. Reference observations are not implementation passes.

No default flags, broad semantic-unavailable fallback, checker executable, game
world, full suite or performance claim was enabled by this checkpoint. Handler
whole-report integration, formal recovery at real boundaries, shared checker
inference/retraction, default cutover and duplicate-model retirement remain open.

The next focused implementation run passes all 14 new conditional/value/resource
controls. Two diagnostic controls still fail before rendering: the formal
metadata trims trailing source whitespace, while the typed fatal-receipt join
uses the following delimiter's untrimmed start. The proposed repair joins the
same trimmed header endpoint while preserving the real delimiter's span and
owner; it is not yet applied or qualified. The native host metadata check found
one additional compile error in the new Derived page abstraction; its budget
error now maps to the operational failure type, with verification pending.

The formal-boundary cohort now has 13 passing controls, including both genuine
fatal report/resource cases and the actual missing-member notice order. One
foreign-owner negative fixture needed its own authenticated authored stop before
it could test the intended refusal; only that repaired fixture was rerun. The
native host library and ten small public test targets pass metadata checking at
source hash de82c9a2308ed6b4b04721181fc8b2eb4cd22cde79339b749b60ff18b5808d4f
(the receipt records the exact measured hash; this paragraph is not a stamp).
The complete frozen silicon-policy comparison also passes after preserving both
legacy ALLOW phases. Two failed-root raw policy controls pass; a third matched
the old report but had a false non-vacuity assertion on CRLF headers. Its source
now retains that file unchanged and adds a separate LF refusal/ALLOW witness;
the failure-only repair build is in progress.

The existing resident protocol now has an explicit exclusive Derived request
and honest current versus failed-root report disposition. A scoped embedding
provider enters the same actual preparation/retry/recorder factory, so the old
invalid replay-based failure fixtures have been replaced with genuine second-open
OS failures. These interfaces are type-checked but their new public runtime and
resident transport controls are not yet qualified. Baseline mutation, transient
report/client memory closure and default activation are still excluded. In
particular, renderer allocation must use the already-held source-family gate's
resource loan; calling the ordinary locking allocator there would deadlock.

### November 5 frontend and report checkpoint

The Handler preparation now borrows the actual for-loop binding span from the
primary statement. A bounded non-empty array declaration remains an unsupported
loop binding under the original grammar. The original token path now carries
scope selectors, joined safe-member tokens, arithmetic operands, and exact
parent and self calls into the shared Pratt parser. The six pinned reference EOF
cases distinguish a real terminal semicolon from a consumed End. The native
producer lends an End receipt only after the receiving frontier drains. A
formal syntax stop still leaves a prefix, even when the underlying source ended.

The checker controls passed for exact parent and self targets, SCC effect
propagation, first I/O failure preservation, compound assignment, CRASH,
weighted and unweighted pick, and chained dynamic and external calls. The 22
selected frontend controls passed across the initial run and failure-only
repairs. These runs cover the selected productive fixtures. They do not establish
complete grammar or incremental checker coverage.

Derived report rendering and transport now account for output while it is live.
The renderer borrows the already-held source-family admission so it can reserve
output without acquiring the same gate again. Its client validates the borrowed
wire document before emitting ALLOW use. Lifeforms and reactive-system report
pages share their semantic envelope identity with the validator. The explicit
check-only cohort for semantic reads, untracked inputs, and setter publication
uses one retained preparation and a common delivery budget. Public host
verification and resident transport verification remain in progress. The
default Analyze and checker routes have not switched.

The 48 public controls now pass across the initial run and failure-only
repairs. The affected Handler cases cover structural-only preparation, the
complete structural, declared, and output report, and a genuine failed full
open. The Windows joins retain the logical workspace path and the canonical
source path separately. The report resolves ALLOW against an acquisition
already issued by that same source mapping. The Derived controls distinguish
decoded frontend revisions from raw workspace policy revisions, including a
BOM-only edit and uncompiled files.

The actual resident Derived control passed with a 73,436-byte cold report,
warm reuse, an edit, and byte-equivalent delivery through the native Analyze
client to the same daemon. The earlier cold refusal identified cumulative
charging for short-lived lexical regex captures. The lookup now reuses the
maximum live capture reservation while preserving the same operation cap.
The resident control also verifies one warning per request and refusal of
mixed or baseline requests. These results cover the explicit Derived route.
Complete checker invalidation, whole-policy parity, and default routing
remain open.

### 2026-11-05: three semantic read policies through the resident route

The actual APC semantic-read fixture and a setter with a missing publication
now pass the resident comparison. The cold cohort, warm thin client and three
independent native requests used the same daemon. The full cohort text, exit
status and ALLOW rows also matched the legacy Analyze executable on that
fixture. The malformed policy roster was rejected without report bytes.

The fixes keep a line doc comment separate from the declaration it documents,
so masking the comment cannot manufacture indentation. Analysis now validates
Original literal syntax independently of runtime string decoding, and visits
prepared interpolation children. Each report series also establishes its own
aggregate and count while retaining the captured roots and revisions across
the cohort. These checks cover this explicit resident path. Normal Analyze
routing and complete checker parity remain open.

The explicit Analyze check now has a normal CLI opt-in for the same three
policies. Its stdout, exit status and single ALLOW output matched the resident
JSON report on the shared fixture. An edit that adds the missing setter
publication retracts that report's previous findings on the same daemon
without changing the two read reports.

The public resident generation test ran all thirteen roles against the four
shared Original source cases. The 52 artifact and ordered-diagnostic records
matched the independent legacy runs. Cold write settled, warm write and
settled check left bytes and modification times unchanged, and the real
cold check refused without writes. The resident test does not exercise
mid-install rollback.

The real-workspace check reached three source forms the smaller fixtures had
missed. Typed procedure returns now keep their annotation and body. An inline
procedure body is separated before the Original stream's synthetic semicolon.
A block doc at a committed line boundary cannot indent the next declaration.
Focused actual-source tests cover all three, including the native external
call's string value. The real workspace now reaches the retained syntax
budget and refuses without a report. It is still outside the opt-in's verified
fixture coverage.

The prepared token queue now drops producer-only source tracing after recording
the source mapping. The admitted row fell from 328 to 168 bytes on Windows.
The focused tests preserve the original read-ahead cadence, source owner and
EOF/colon receipts, and first operational error. The three-policy resident
comparison still matches legacy output after the change. The real checkout
still reaches the 128 MiB limit during queue growth, so further compaction
is needed before this route can run on the full checkout.
The queue also borrows identifier and literal values from their adopted owners.
Nine focused checks preserve exact source geometry, the Original value variants,
and delivery cadence. The resident three-policy comparison again matched the
independent legacy report and retracted the stale setter finding on edit.

The full checkout then reached signature storage. Shared empty macro traces,
temporary include-path credit, exact primary-vector growth, and releasing
unchanged-symbol signature scratch advanced it further. Eighteen focused
signature tests and four allocation and provenance tests passed. The latest
5,885-source run refused the next primary token array allocation under the same
128 MiB cap, without emitting a report.
The selected Original checker routes now exercise the same resident query graph.
The parent-switch case replaces the previous type finding without changing the
caller, rejects the stale source revision, and matches a fresh workspace.
The ordered reader emits declarations, settings, body, keyword, sleep and
purity phases in producer order through one captured scope. Its focused fixture
checks five findings, warm equality, and closed rejection of foreign context
and configuration. These routes still declare partial checker coverage.

The pinned library confirmed the distinct registration and fatal behavior
of bare and decimal-initialized class comma declarations. The real filesystem
controls verify the fatal and the retained prefix. The native ordered report
and pinned library also agree on four root and typed increment diagnostics.

The live Original producer now writes compact eight-byte token pages directly.
The primary, expanded source and header consumers retain that same owner.
An ordinal window establishes the exact range before local parsers borrow a
funded temporary slice. Standalone dense input keeps its existing representation.
The packed tests cover wide coordinates, page boundaries, actual shared
ownership, and refusal under the existing cap. Both resident fixture families
still pass, including the independent three-lint Analyze comparison.

The 5,885-source probe advanced from a declaration-vector growth refusal
to the next 16 MiB raw source-map growth at 127,942,910 bytes retained. It
returned no report and the private daemon drained. Whole-checkout coverage,
complete checker parity, default routing, and duplicate-model retirement
remain open.

### November 5 master merge and retained-source verification

The branch merged master `0660476914` at `6c6254fb09`. The merged standalone
and native-only Analyze libraries and the native compiler library type-checked.
The production DM source and lint baselines match that master revision. Native
generation exposes the twelve roles still registered on master.

Focused comparisons covered the current Init table rules, capability-part
source coordinates, Declare part ordering and lazy accessors, complete-source
relation types, the host and library boundaries, and Plans side overrides.
Both native tracked-list paths emitted the same 17,895 bytes and zero
diagnostics as the current legacy generator on the copy-on-write fixture.
The native stored-reference body tests covered alists, nested indexed writes,
first-write identity and cancellation. The resident stored-reference hard-ban
route remains closed pending the remaining current-master parity checks.

The public library-layering request detected a downstream reference, matched
its exact legacy baseline fingerprint, and accepted an exempt source set
without opening a manifest. The selected native checker requests preserved
diagnostic ordering and retracted a stale undefined-field result after a
parent change. These controls exercise the actual resident request paths.

The latest whole-project semantic cohort captured 6,755 sources and returned
an operational refusal with zero report bytes at the unchanged 128 MiB syntax
limit. The failure-only trace recorded 6,023 completed signature rows with
33,974,492 bytes of header reservations. Of those, 25,777,391 bytes in 802 rows
were above the current reconciliation floor. These are reservation counts,
and the trace separately identifies the counter sampled after unwind.
The producer also attempted a 28,908,656-byte final macro grant after the
receiver failed. The receiver-failure path now skips this finalization and
preserves the exact first I/O error in both batch schedules.

Whole-project parity and default cutover are still open. Cold Declare
bootstrap must account for variables in the omitted generated source, since
they can shadow inherited fields. Full ALLOW accounting still needs a cohort
proof for layering.


### November 6 source ownership and public policy reports

The checked Original pipeline now keeps compact origin rows, shares source
encounters and final macro allocations, and reuses scanned physical line
ends. Origin coordinate pages and their directories retain their exact
allocations through the existing source arena. The syntax and source budgets
remain 128 MiB and 256 MiB. The syntax owner still verifies the actual token,
acquisition, expanded output, and delivered frontier.

On the same 6,755-source checkout, successive three-policy probes reached
7,126, 8,878, 11,436, and 13,375 completed procedure headers before declining
the next syntax reservation. The latest held 32,820,224 bytes of actual
coordinate-page storage under the source budget at that point and emitted no
report. This is preparation coverage, not whole-checkout semantic parity.

The public standalone notice publisher completed on the checkout with zero
findings using the exact CODE discovery without a manifest or semantic model.
Its legacy/native controls match exact sites and annotation use. The catch
policy shares the authored CODE scanner and preserves ordered findings and
empty annotation use; a public report distinguishes a throwing call inside a
catch from a call outside it.

Focused native and pinned-library tests establish that the final contentless
declaration in an include can take its diagnostic location from the actual
root EOF token. Native declaration diagnostics now use that exact receipt
while strict policy and initializer anchors retain authored provenance. The
public library-layering report also matches its authored-manifest result
when the fixed manifest is absent or supplies the old synthetic-input recipe.
The resident checker test observes three ordered findings and preserves type
hints through both operands of logical OR.

Full semantic and checker parity, cold Declare on the checkout, transactional
full generation, and default routing are still open. The stored-reference
hard-ban route remains closed pending full-policy evidence.

### 2026-11-06: retained preparation and Declare transaction

The checked Original body query preserves `:=` and `%%=` with the pinned
right-associative assignment precedence. Both focused controls passed,
including the negative check against ordinary expression grammar.

The three-policy probe completed 13,506 headers after numeric payload reuse
and completed-header identity compaction, up from 13,375. The compact path
index and paged macro arguments moved it to 14,710. Funding completed
signatures and later adapter metadata at their actual owners, plus shared
trace spellings, moved it to 18,756. The probe captured 6,754 source files,
one fewer after regenerating the manifest without the retired sparse-slot
output. It declined under the existing 128 MiB syntax limit, without emitting
a report. At that refusal the receiver held 198,140 literal rows, with
8,388,608 bytes of row capacity and 18,149,520 bytes of exclusive payload
reservations. The producer held 16,563 exclusive live macro products, with
6,625,200 bytes reserved for wrappers and 10,525,008 bytes of replacement-row
capacity. Producer and receiver census points are separate and their totals
cannot be added as a simultaneous peak.

The opt-in fixed-DME Declare transaction collects its initial markers from
the actual directive and physical acquisition roster. It probes the generated
bytes and re-probes the completed relation table through the same checked
assembly. Its type-only projection avoids starting a body-query revision under
the generation policy lock. The private IPC control observed a stale Check
with no write or prepared frame, one Write that installed the final output, a
retained installed source, and an ordinary warm Check that returned fresh.
The paged typed Declare comparison matched the existing reference fixture.
The real checkout's cold Declare is still unverified. The current coarse
prepared-source pregrant exceeds its existing budget at the measured file size.

Two handler comparisons and eight native host controls passed. The handler
recipe preserves the original output signature gate and finding order,
configured selection, migrated define roots, and last duplicate manifest
precedence. The explicit public report distinguishes complete structural and
full requests from a genuinely failed full preparation. The latter emits an
incomplete envelope and the partial structural findings. The standalone
Silicon report passed an actual hidden actor file and annotation-use control.
Neither route supplies full-registry completion.

Checked procedure header encoding now funds its scratch as the existing lexer
emits the canonical bytes. The focused byte framing, malformed input, first
I/O error, and final-credit controls passed.

### 2026-11-06: static retention and selected report staging

Short repeated string and resource literals now share exact typed storage.
Each occurrence still requires its own issued raw loan and keeps its own
identity. Compact macro definition names retain their actual source origin.
After merging master at `cff6e2b3d0`, the three-policy probe captured 6,754
sources and reached 20,663 completed procedure headers. It emitted no report.
The first denied reservation was 1,802,240 bytes to grow the pending formal
default buffer, with 133,987,643 bytes already retained under the unchanged
128 MiB syntax limit. The merged tree differs from the preceding measurement,
so the header count does not isolate savings from a single change.

An additional macro storage change keeps compact replacement rows only when
the existing frame, occurrence, typed token, source backing, and coordinate
proofs all match. Other definitions retain their full token rows. The focused
driver and allocation suites passed 26 tests, including real replacement
expansion, quoted fallback, stack restoration, and first I/O propagation.

The private selected-report embedding stages actual findings and annotation
usage from the same captured source. The focused control passed for the four
base policies and for the roster that also includes `cooldown`. It verified
used and stale annotations, the source text and hint of a cooldown finding,
the failed-policy summary, and zero output when required configuration is
missing or a producer is unsupported. No daemon endpoint, default routing,
or full-registry completion follows from this embedding.

The pending formal-default queue now uses 64-row pages and releases each
page after consumption. The allocation test crosses the old 2,048-row
boundary with one 28,160-byte page and the small directory growth. Final
default lookup storage reserves its actual row layout. Forty focused default
tests passed, including a checked frontend fixture that borrows 210 default
and source-expression roots across page boundaries in order.

The bounded checkout probe with paged defaults and compact macro replacement
rows hit its 300-second deadline at 16,305 completed headers and emitted no
report. It did not reproduce the prior allocation refusal before the deadline.
The probe measured 4,981,040 bytes of live replacement-row capacity at that
earlier frontier. This and the earlier 10,525,008-byte census cover different
frontiers and cannot establish isolated or whole-project savings. The separate
empty-region change shares the two immutable empty backing vectors across the
actual include records. Its two focused producer and accounting tests passed.

The qualified selected report can now include Silicon Entry. Its typed actor
lookup uses the same hidden-inclusive `code` and `maps` source capture as the
legacy selected tree. Its raw checks and the standalone Silicon report keep
their original scope. The native host fixture passed cold and warm. The
independent legacy comparison matched the hidden-map actor finding, the code
shortcut, and the map annotation consumption. The standalone oracle also
passed after its frozen and native rows were rendered with the same frozen
policy. Derived Reads remains excluded because its existing discovery proof
does not cover the aggregate's `maps` input.

Completed procedure signatures now keep their exact ordinal lookup in
128-row pages. The adapter borrows and consumes the same rows without
flattening the pages. Six focused storage controls passed, including
reverse-order consumption, full span and foreign owner checks, and exact
allocation refusal. At the earlier 20,663-header frontier the layout would
reserve about 2.0 MB less for the row directory and backing arrays.

The explicit `dmbc analyze-exclusions REQUEST.json --report-batch` route now
uses the existing resident build coordinator and host. It accepts only the
three qualified rosters. A validated terminal binds the two private streams
to the actual preparation revisions, and the client verifies both streams
before emitting the machine-readable header, report and diagnostics. Invalid
request shape is refused before it may supersede another request. A failure
before publication returns a typed rejection, and an output failure after
publication returns its first actual I/O error.

Five wire controls and two embedding controls passed. The private resident
test observed a 21,497-byte fragmented report, identical cold and warm
output, and a clean report after editing the source, all on the same daemon.
Unsupported selection, inexact input, missing deadline and missing
configuration each failed without a report or preparation notice. This is
an opt-in path, with no change to the default Analyze or checker commands.

On the same 6,754-source checkout, the next bounded probe reached 21,678
completed headers and 2,196 pending defaults. It crossed the earlier
2,048-default allocation refusal within the same 128 MiB syntax limit.
The probe reached its 300-second deadline and emitted no report. This
measurement predates the later master merge and packed coordinate change.

The source arena now packs group coordinates while retaining the exact
trace owner. Full-width coordinates have a sparse, lossless fallback. Ten
coordinate controls passed. Exact retained subview checks also avoid
temporary reference-counted copies, with two equivalence controls and a
real macro expansion test passing.

`analyze-native native-exclusions` uses the shared wire schema and runs
without the legacy or native semantic-model features. The daemon remains
the source authority. The client verifies the requested roster, exact
report and diagnostic bytes, end of stream, and process status before
forwarding. Three client controls, five wire controls, two host embedding
controls, and the extended cold, warm, and edited resident test passed.
The latter compared both outputs through Analyze and rejected a foreign
roster without forwarding either stream.

The selected Original checker preserves the builtin parents of `/alist`,
`/datum`, `/list` and `/savefile` for direct known builtin parent assignments.
The checked source receipt carries the exact rejected edge. The retained
diagnostic reader emits the rows at their original declaration positions and
body lookup uses the sealed hierarchy. Unsupported assignment shapes still
refuse the selected route. Three checked frontend controls passed. The resident
IPC fixture matched six reader rows against the pinned Original reader and
confirmed four negative body lookups and one positive lookup on `/world`.
This covers only the selected checker phases.

Selected report preparation now truncates its private diagnostic spool when
a freshness retry begins. The committed stream belongs to the last successful
attempt. The retry-spool test and both generic diagnostic writer controls
passed.

Library Layering is available as a separate selected exclusion roster. It
reads the original workspace configuration, runs the existing library
producer over the same semantic capture, and accepts an empty selection
only after the visible CODE discovery proves it. The focused host test found
the content reference, then changed only the scope configuration and
confirmed a clean report on the same warm host. The scheduler annotation
was consumed in both reports. Default routing remains unchanged.

Original byte loans now reject a non-header receipt before constructing the
synthetic root's canonical path. The exact synthetic and recorded-source
checks still govern both paths. Three focused native report and diagnostic
controls passed. The current 6,751-source real semantic probe reached the
128 MiB syntax limit before its 300-second deadline and emitted zero bytes.
The denied request was a 26,624-byte macro-token page at 134,212,574 bytes
retained. This checkout and binary differ from the earlier deadline-only
probe, so the result identifies the current memory frontier without
attributing an isolated time improvement.

A separate selected `sem/handlers` roster now uses the same resident attempt
for its genuine structural and demanded-full subjects. The structural scan
uses the original visible CODE recipe. The full report borrows hidden-
inclusive CODE and MAPS from the same captured workspace for ALLOW checks,
proves the full tree once, and authenticates each file loan against it.
Partial and full preprocessing notices appear once in their original order.
The cold and warm report matched the frozen legacy mixed-scope Engine,
including the real map annotation consumption and the unused annotation
result. Structural-only and incomplete full inputs failed without
publication. The two standalone handler controls still passed.

Cold Declare now reserves each named render for its exact output bytes and
drops the first buffer before rendering the next. Its focused test verified
matching bytes, reclamation, and a one-byte-short refusal. This does not
lift the whole-project directive/expansion admission boundary.

Original macro trace rows now reuse the exact allocation as a boxed slice
inside a thin shared owner. Literal facts retain fixed-size pages and lend
ordinal windows to syntax, declaration, and body consumers without flattening
or weakening source identity. Ten focused controls passed. The resident
Declare fixture also passed Check, Write, and warm recheck on this binary.

The 6,751-source probe reached 22,958 completed headers, 2,364 pending
defaults, and 229,983 literal facts. It stopped with 134,211,382 bytes
retained before a 16,384-byte syntax reservation and published no report.
The paged literal directory and rows reserved 7,405,568 bytes. Exclusive
literal payloads still account for 12,529,499 bytes at that frontier. The
private daemon drained normally. Whole-project semantic parity and the
default cutover remain open.

The paired selected semantic-read roster runs `sem/reads` and
`untracked_inputs` from the same current Original model. Their marker and
publisher passes keep visible CODE. A finding in hidden CODE or MAPS can
borrow its exact source for ALLOW lookup from the complete selected tree.
This contract uses distinct cache keys. The resident host fixture matched
the frozen legacy report bytes, including warm and edited map annotations
and a map-only publisher that did not hide the CODE finding.
`setter_publishes` remains outside this roster pending its distinct legacy
setter-header lookup contract.

The Original physical-row lookup now reuses the active frame index, with
the existing exact search for older frames. Both provider-loan tests passed.
On the same 6,751-source checkout, boxed traces and paged facts advanced
the completed-header frontier from 22,365 to 22,958 under the same cap.

The separate selected `setter_publishes` report now qualifies handwritten
setter headers using the legacy selected Tree's membership and raw model
line, including the `TRACKED_STATE` spelling. Its result and dependency
candidate keys are distinct from the ordinary lookup. The cold, warm, and
edited fixture matched the frozen legacy report, including a true
`interface/` Tree miss and retraction when that declaration moved into MAPS.

Packing literal span rows and storing the seven typed literal kinds in
a smaller payload passed 19 focused controls. The same 6,751-source probe
advanced to 23,999 completed headers and 239,503 literals before the same
syntax cap refused 16,384 bytes. Literal directory and row reservation fell
from 7,405,568 to 5,832,704 bytes at those respective frontiers. The
private daemon drained and the probe emitted no report.

Completed leaf defaults release only the temporary parser credit after
demand ends, keeping the actual tokens, syntax, and independently funded
literal data. Complex and incomplete expressions retain their prior
admission. The unit test, the real 210-root paging fixture, the lazy/batch
role fixture, and the repaired fatal-parameter control passed. The real
checkout advanced from 23,999 to 25,526 completed headers. Pending formal
roots held 1,938,842 bytes at the new frontier, down from 7,035,760 bytes at
the previous one. The probe still emitted zero report bytes and the private
daemon drained.

A checked-provider audit also reached a separate existing sharing gap.
Direct Checker and Original Analyze preparations over unchanged source
interpret the signature twice. The existing exact reuse test remains
unchanged. The two requests need a real shared source freshness handoff
before either can skip its primary stream.

The Original layout now funds each returned batch independently of the
retained producer identity. Five layout controls and four real producer
controls passed. Original macro traces now borrow each frame's parent
names from its preceding frames. Seven preprocessor controls, the native
source projection test, the public diagnostic test, and the pinned sealed
parent IPC fixture passed on the new representation.

An opt-in combined host entry prepares one complete authored Original
workspace for the paired semantic-read roster and the selected ordered
Checker phases. The same recorder captures both policy scopes, including
the genuine absence of an autodetected Checker configuration. Each
consumer uses the same frontend tree and archive with its own scope, and
all three spools are checked before publication. The fixture compares the
Analyze output to standalone execution and confirms a fatal input publishes
nothing. It also exposed a Checker-only literal prefix bug, fixed by
requiring the Original syntax contract for its authenticated body input.
This is a host entry point. The daemon wire and default commands are
unchanged.
