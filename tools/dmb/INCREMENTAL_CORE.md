# Integrated incremental compiler core

This describes the implemented prototype. It is an implementation map, not a
claim that every operation is a minimal incremental query or that the new
integration has passed a runtime suite.

## Ownership and reusable APIs

| Layer | Owner and main API | Retained data |
| --- | --- | --- |
| Source inputs | `dm-compiled::Coordinator::prepare_project` | Detached `Arc<PreparedProject>`, decoded source content, includes, origins and filesystem proofs |
| Structural syntax | `dm-compiler::frontend::OutlineSession` | Content-addressed compact chunks and current source layout |
| Worktree retention | `dm-compiled::frontend_pool::FrontendPool` | Separate discovery, outline and canonical session for each full `SessionKey` |
| Declaration preparation | `dm-compiler::bootstrap::canonical::CanonicalSession` | Frozen pre-procedure DMB skeleton, invocation signatures and declaration bindings |
| Procedure semantics | `dm-compiler::ProjectProcedureGraph` | Stable inputs, actual positive/negative binding facts, prepared results and portable references |
| Map initializer semantics | `dm-compiler::maps::MapInitializerSession` | A separate project/configuration-scoped graph of prepared assignment helpers |
| Independent work | `dm-work::with_ordered_pool` | Worker-local state and bounded job/completion windows |
| Code materialization | `dm-codegen-byond::prepared_cache` and `relocatable` | Flat words, unique symbols, relocation slots and relative statement origins |
| Source tools | `Coordinator::project_frontend_snapshot` | The same prepared source, compact declaration AST and declaration index |
| Output publication | `dm-output` | Generation publication, verified archives and exclusive binary patch plans |

The CLI, daemon and source tools use the same preparation/front-end services.
`ProjectFrontendSnapshot` owns detached data rather than a live Salsa database.
Analysis exports report reference coverage as **unavailable** until a producer
supplies actual resolved reference occurrences. Binding witnesses record facts
read during lowering; they are not a substitute for reference locations.

### Lint migration readiness

The implemented public tooling surface is a detached declaration snapshot and
versioned `dm-analysis` JSONL export (`dm-compile analysis-jsonl PROJECT.dme`).
`DeclarationIndex` supplies local/inherited variable and procedure lookup,
override lookup and ancestor iteration. This is sufficient to start migrating
definition rules such as forbidden subsystem `fire()` definitions and content
`Destroy()` overrides. No repository lints have been migrated in this pass.

| Required lint facts | Current coverage |
| --- | --- |
| Canonical declarations, inheritance, source locations | Available, with coverage flags for partial inputs/origins |
| Procedure signatures | Exact headers; normalized resolved types/defaults are incomplete |
| Resolved calls, reads/writes, receiver types, body/control flow | Not exported |
| Reference occurrences/reverse references | Unavailable; dependency witnesses do not provide occurrence coverage |
| Authored comments, inactive branches, macro expansion provenance | Not a complete tooling model |

Consumers must check the snapshot's schema and required coverage before reporting
a clean lint run. Missing facts are an unsupported analysis result, not proof of
zero violations. Initially retain the Python ALLOW-annotation and ratchet baseline
adapters. Ownership/field-write/call-forwarding rules require the resolved-body
model; macro/comment rules require authored tokens and expansion provenance.
The JSONL export is not yet the planned public per-body query service.
The export covers the selected manifest/configuration. Existing Python lints scan
all authored `code/**/*.dm`, including inactive branches and files outside that
build. A migration must preserve that scope through authored syntax coverage or
an explicit configuration matrix; one successful project snapshot cannot certify
the entire repository.

DeepQuarry's actual `CBT,CIBUILDING,CITESTING` export was exercised: 147,733
declaration records, 68,410 exact-header signatures and 46,681 inheritance
records. Its snapshot reports complete declarations/inheritance/origins, partial
signatures/diagnostics and unavailable references. The full JSONL is 372,793,924
bytes because it includes the per-expanded-line origin stream; that is not yet a
compact or paginated lint protocol. Receipt:
`target/deepquarry-analysis-20261001.receipt.json`.

`Coordinator::project_frontend_snapshot_bounded` accepts an explicit source
budget through the same preparation/frontend path. `analysis-jsonl` defaults to
64 MiB, honoring `DM_ANALYSIS_MAX_SOURCE_BYTES` first and an explicitly set
`DM_CHECK_MAX_SOURCE_BYTES` second. Malformed/zero overrides fail rather than
silently raising a caller's budget. Ordinary checking keeps its configured
16 MiB default. The measured DeepQuarry expansion is about 49.6 MB.

## Semantic and physical identities

`ProcKey { path, occurrence }` distinguishes repeated authored overrides in
source order. The frontend adapter owns occurrence matching across revisions.
`ProcDescriptor { body_digest, frame_digest }` covers the current expanded body,
its relative span shape, signature/defaults, owner and static aliases.

Neither identity contains a physical procedure ID or absolute source offset.
Output table IDs are allocated by ordered assembly for the current generation.
Prepared sections retain symbolic relocations, so code reuse does not require
preserving earlier table IDs.

Facts are scoped by procedure key because local static aliases and inherited
owner fields can differ between invocations. Every successful resolution and
unsuccessful resolution observed by lowering is represented by a `BindingFact`
and its exact `FactValue`. A missing member that later becomes declared must
invalidate the old result just as a changed positive resolution does.

Salsa tracks descriptor/candidate inputs and those actual fact values. Equality
checks avoid setting unchanged inputs. A descriptor hit returns an `Arc` to the
prepared result without requiring a body AST or reconstructed binding frame.
An installed asynchronous result must still match the current descriptor.

Invocation frame digests are computed once when the frozen skeleton is prepared.
Current compact chunks expose exact raw-procedure digests by current source span;
unavailable lexical layouts use a raw-slice hash fallback. Plain authored prepared
hits do not clone invocation bindings. Argument-source helpers and cache misses
still receive the complete frame.

## Build flows

### First compilation

1. Prepare decoded sources, macro/include expansion and exact origins.
2. Read compact structural chunks and prepare declarations/invocation frames.
3. Allocate the pre-procedure skeleton in deterministic source order.
4. Submit missing authored procedures as bounded raw-source jobs. The same
   persistent worker parses, rewrites modified types, extracts settings/statics
   and lowers the body; it returns the current body anchor with its result.
   Generated helpers can submit already parsed bodies through the same engine.
5. Capture their actual semantic reads and prepare baseline flat code sections.
6. Install prepared code plus witnesses in the persistent graph.
7. Resolve the current output ledger, add current source debug markers, and
   publish the ordered result. Persist cache batches independently of success
   of optional cache I/O.

The parser startup snapshot is loaded lazily once per stage and shared between
workers. Each worker keeps its own parser readers, pending writes and lowering
state. Prepared hits do not request an authored AST or initialize that snapshot.

Map reads and template/grid parsing use the same `dm-work` executor. Unique map
assignment helpers have a separate `MapInitializerSession` graph retained by the
canonical session. Exact assignment text determines their field overlay and
descriptor. Restored witnesses are refreshed from those current overlays before
reuse; they are not trusted merely because they were persisted. Misses parse,
lower and prepare in parallel, while graph installation and physical map table
allocation remain ordered. Current class/resource IDs are relocated at emission.
An indexed string table replaces per-helper scans of the complete string table.
The map session also retains template/grid byte spans keyed by the exact map
content digest, bounded to 16 MiB and 512 entries. Unchanged maps reuse those
spans without reparsing; source text remains owned by the input snapshot.
Spans also persist in `dm-store`/redb records, so a fresh process can restore
only the exact current content handles in bounded batches. The `DMMAP001` codec
and emission fingerprint guard compatibility; checksums, exact source digests
and span/delimiter validation guard reuse. Reads enforce a 512 KiB record cap
and approximately 8 MiB batch allocation cap before allocation. Missing,
corrupt or incompatible records fall back to parsing and optional batched writes.
Grid
cells use exact key lookups over precomputed distinct key widths: fixed-width
maps require one lookup, and mixed widths select the longest matching key
deterministically.

### Cold process with caches

The graph opens a worktree/configuration-specific current-procedure manifest.
Prepared payloads are content addressed and shared between worktrees. Startup
reads witness/descriptor headers, then prefetches only current payload handles
in batches of at most 256 records. Old versions from other worktrees cannot
consume the whole current payload snapshot.

Restored semantic inputs begin **unavailable**. The current declaration skeleton
must refresh their values before any cached result is observable. Valid hits
decode compact prepared sections rather than procedure syntax or symbolic trees.
Corrupt, missing, incompatible or over-budget cache records fall back to normal
lowering.

### Body edit

The changed descriptor invalidates its procedure input. An unchanged skeleton
revision skips semantic-fact replay. Other procedures can return retained
prepared code without parsing or lowering. Relative origins are resolved against
current procedure spans, so an upstream line shift cannot reuse stale absolute
debug lines.

### Declaration edit

The prototype rebuilds the frozen declaration skeleton and refreshes previously
observed scoped facts. Only changed fact values are set in Salsa. Procedures
whose facts and descriptors remain equal can retain their prepared results.
Deleted procedure keys lose both resident and persisted manifest observations;
input handles stay bounded and may be reused if the declaration returns.

This refresh is still a conservative pass over known observed facts. It is not
yet a declaration-delta-only traversal of an interned shared semantic graph.

### Worktree/configuration switch

The pool keys sessions by worktree, project, target, defines, build mode and
compiler version. Each pooled session retains its `DiscoveryCache` alongside
its outline and canonical graphs; discovery is not a singleton for the latest
worktree. All these components share the six-session/512 MiB aggregate retention
budget. Mutable Salsa inputs are never shared between those sessions.
Each entry also retains its `DiscoveryCache`: switching among six worktrees can
reuse prepared sources, exact origins and macro expansion frames without loading
another input pack. Frontend and discovery components check out independently;
returning one preserves the other. The same aggregate budget charges both plus
session keys, resource proof records and known checked-out footprints. Active
entries cannot be evicted until their checked-out components return.

Immutable disk stages use the coordinator/frontend cache root consistently and
remain shared. Successful check summaries are shared; diagnostic summaries are
scoped to the current revision. Under memory pressure, the pool trims expansion
values, duplicated body strings, encoded startup snapshots, decoded code values,
expanded input snapshots, declaration prefixes, and finally full source state.
It evicts a whole idle entry only after those component trims. Compact syntax and
semantic query identities can therefore survive code-value eviction. Raw source
Arcs, proof and context survive expanded-snapshot eviction, so the next edit can
read only dirty source files instead of restoring the old whole input pack first.
Trace output reports component charges and any final eviction reason. Six-session
retention remains conditional on the aggregate byte budget.

The authored/generated procedure graph and map initializer graph are separate
mutable instances with different input identities. They share graph/store
implementation and the executor, rather than introducing stage-specific worker
engines or cache formats. Both graphs' retained memory is charged to the owning
canonical session and frontend pool.

## Memory boundaries

| Retained component | Default boundary |
| --- | --- |
| Frontend and discovery pool | At most 6 idle/retained session entries and 512 MiB aggregate retained charge; known active footprints reserve this budget, active growth has separate stage limits; `DM_FRONTEND_POOL_BYTES` may increase it |
| Map structural spans | 16 MiB and 512 exact-content entries per map session |
| One procedure graph's decoded artifacts | 96 MiB |
| One graph's semantic/identity metadata | 256 MiB, 128,000 procedure inputs, 1,000,000 fact inputs |
| Encoded prepared payload LRU | 128 MiB |
| Current graph manifest startup read | 64 MiB |
| Graph pending write batch | 32 MiB |
| Individual persisted header / envelope | 4 MiB / 32 MiB |

Equal canonical skeletons share immutable allocations across worktrees through
`dm-store::SharedArtifacts`. Its weak index retains no payload. The pool divides
the skeleton's conservative serialized-size charge among its live Arc owners.
The graph charge includes decoded artifacts, semantic metadata, encoded startup
payloads and pending writes. Input counts include handles ever allocated in the
session: deletion cannot silently bypass the bounds.

Decoded procedure code is owned by graph records outside Salsa, matched to an
immutable candidate generation. Evicting/reloading identical code does not write
semantic inputs or advance the query revision. Restored headers initialize facts
as unavailable until the current skeleton refreshes them. Encoded payloads are
loaded in bounded caller-supplied emission order through `prefetch`, with an
8 MiB read-batch limit and a 128 MiB LRU; graph startup does not eagerly load the
whole payload namespace. Authored procedures, argument-source helpers, generated
initializers and map assignments all use this same refill API. Budget failures
split batches, missing rows are cached, and general I/O failure suppresses a storm
of individual reopen attempts until the next explicit refill.

These are retained-state and stage budgets, not a hard bound on process RSS.
Source/map/archive preparation and an active compilation have additional bounded
temporary buffers. The work engine bounds in-flight job estimates; completed
results are separately bounded by each caller's completion window. Timings from
`DM_BUILD_TRACE` distinguish elapsed operation totals and Windows worker CPU;
nested/overlapping totals must not be presented as a wall-time partition.
Per-build `ArtifactReuseStats` separates authored and generated prepared hits,
portable lowering-cache hits, and actual lowering. These counters describe the
current emission rather than cumulative graph statistics.

## Output and compatibility boundary

Normal project builds and CLI patch requests use canonical assembly. The old
linked-checkpoint path remains only behind explicit `legacy-history` requests
and regression fixtures. It is not the default incremental architecture.

Code reuse and binary patchability are separate. A semantic procedure can remain
cached while changed table IDs require relocation. An edit can also change the
physical output layout enough that the exclusive patch planner requires a new
generation. The compiler does not promise byte-for-byte compatibility with
native DreamMaker allocation history.

## Remaining architectural work

- Replace conservative structural refresh with explicit declaration deltas and
  shared interned facts while preserving invocation-specific overlays.
- Reuse one typed procedure AST between syntax tools and semantic lowering on
  cache misses; successful prepared hits already avoid body parsing.
- Export actual per-use semantic reference locations for lint/navigation tools.
- Give deduplicated generated helpers honest multi-origin sidecars. One shared
  helper cannot claim a unique authored debug location for all its call sites.
- Incrementalize ordered physical assembly and output records further. Reusing
  semantic procedure code does not by itself eliminate whole-image emission.

These boundaries should remain explicit in API coverage and performance reports.

## Initial prototype checks (2026-10-01)

The workspace and test targets typecheck, and the CLI/daemon binaries build.
Focused Rust checks cover canonical edit/fresh equality, positive and negative
dependency invalidation, stale result rejection, initializer and map relocation,
cache restart/corruption, six-session source/frontend isolation and trimming,
six-process store writes, daemon overlap/queue bounds/panic recovery, and bounded
cache reads. Small executable CLI/daemon builds and JSONL export also work.
A CLI body edit lowered one procedure and reused two; adding a procedure lowered
one and reused three, with the resulting DMB byte-identical to a fresh build.
This pass did not launch DreamDaemon or run the game's runtime test suite.

The supported `materialization_bench` used six separate 64-procedure fixture
roots, two concurrent builds and a shared cache. These are fixture measurements,
not DeepQuarry timings or a before/after comparison:

| Fixture case | Total elapsed range |
| --- | --- |
| Initial concurrent cold pair | 1.62–1.69 s |
| Unchanged rebuild | 79–94 ms |
| First build of later roots with shared cache | 0.48–0.62 s |
| Add a procedure | 0.29–0.51 s |
| Add a variable | 0.19–0.32 s |
| Change a default | 89–245 ms |

Later roots had 64 portable lowering hits and zero misses. The initial concurrent
pair can both miss before either publishes its cache batch. The benchmark now
uses the configured common frontend/cache root; separate output directories do
not silently create separate lowering caches. Real-project cold, structural edit
and six-worktree timings cannot be inferred from these fixtures.

### Real DeepQuarry measurements

The integrated compiler at `505f1f8e98` was measured against this worktree's
DeepQuarry source and generated assets, with `CBT`, `CIBUILDING`, `CITESTING`, two
procedure workers and one daemon compiler worker. An isolated adjacent manifest
included a private one-procedure/one-variable overlay; game source was not edited.
The test configuration emitted 68,411 procedures (68,412 after adding one), a
67,384,779-byte DMB and a 222,851,714-byte RSC.
No DreamDaemon or runtime suite was started.

| Real project case | End-to-end elapsed |
| --- | ---: |
| Fresh daemon, unchanged output receipt | 0.215 s |
| Fresh CLI, unchanged output receipt | 0.227 s |
| Fresh daemon, one procedure edit with disk caches | 82.514 s |
| Same daemon, second procedure edit | 81.157 s |
| Add a procedure | 89.885 s |
| Add a variable | 92.915 s |
| Change a variable default | 85.945 s |
| Final unchanged request | 0.208 s |

Body edits lowered one authored procedure and reused 68,410. Variable/default
edits lowered zero authored procedures. Semantic reuse therefore works, but
large-project iteration is still slow: source preparation, table assembly and
cache restoration remain substantial. The daemon returned to approximately
23--47 MiB private memory after each build, indicating that the pool had evicted
the large session rather than preserving a useful warm compiler state.

A fully empty-cache run failed after 98.15 s at the default 2 GiB process cap,
around authored procedure 55,000. The retry at a bounded 3 GiB cap succeeded in
approximately 130.5 s and peaked at 2.15 GiB private memory. That retry had fresh
lowering/prepared caches but a partially warm syntax cache; it is **not** a
fully cold timing. Its approximate total is reconstructed from redirect-file
creation/final response timestamps; edit totals use an external stopwatch.
The compiler stage was 87.586 s and final input revalidation was 4.951 s.

Receipts and stage logs are in `target/deepquarry-migration-20261001/`.
Follow-up changes address granular pool trimming, duplicate prefix data/buffers,
graph write/read bounds and syntax-cache root isolation. Their measurements below
show why substantial iteration work remains. Six full-sized concurrent worktrees
remain unmeasured.

A follow-up production Coordinator measurement in
`target/deepquarry-retention-retry-20261001/` still hit the default 2 GiB cap at
dynamic initialization, after completing all authored procedures (104.59 s until
process failure). At an explicit 3 GiB cap, the next run's initial build succeeded
in 109.834 s with partially warm disk caches, and its unchanged request took
0.186 s. Source preparation on the subsequent body edit took 11.784 s, but code
restoration then regressed to 140 s for the first 5,000 procedures. That edit run
was deliberately stopped; it is not a successful edit timing. Partial receipts
remain in `target/deepquarry-retention-3gib-20261001/`.

The traces show retained graph/proof state now survives session trimming, but
the prefix is still evicted: its 308,435,588-byte **estimated charge** exceeds the
remaining aggregate pool capacity. Graph metadata also reaches its 256 MiB cap
at about 47,700 of the 68,411 authored procedures. An evicted decoded payload
previously required both an individual store read and a Salsa input replacement
when restored. Follow-up code separates decoded payload ownership from semantic
candidate identity and uses ordered bulk prefetch for procedures, argument and
initializer helpers, and map assignments. Its own complete real-project edit
measurement was then run with the bulk-refill fix:

| Bulk-refill follow-up, real DeepQuarry | Coordinator request elapsed |
| --- | ---: |
| Initial build with fresh lowering/parser stage, existing resource proofs | 206.019 s |
| Unchanged request | 0.317 s |
| One procedure body edit | 116.099 s |
| Revert to cached baseline output | 48.383 s |
| Add one procedure | 131.661 s |
| Revert to cached baseline output | 27.480 s |

All requests succeeded with two workers and an explicit 3 GiB process cap.
The initial build lowered 68,405 authored procedures and reused six. The body
edit lowered one and reused 68,410; adding a procedure lowered one and reused
68,411. Both reverted DMB digests equal the original baseline digest. These
requests use a retained production Coordinator; CLI transport/startup and
post-request receipt hashing are outside the request timer. Full report:
`target/deepquarry-bulk-refill-20261001/iteration.json`.

The body edit reached 50,000 procedures in 31.987 s with 187 bulk reads and zero
single-payload reads (rather than 140 s for the first 5,000 before the fix).
The restore regression is resolved, but overall edit latency remains poor and
does not show an improvement over the earlier 81--93 s run. Body-edit source
preparation took 26.731 s, the compiler/materialization operation 75.026 s, and
final proof revalidation 8.038 s. Add-procedure compiler/materialization took
92.342 s. Even returning to a previously emitted generation still requires
substantial source/proof work after an edit. The declaration prefix remains
evicted at the pool limit; graph metadata cannot retain all authored candidates.
The complete pipeline is not yet minimally incremental, and these measurements
must not be presented as achieving the three-second structural-edit target.

### Follow-up source, declaration and output prototype (unmeasured)

The next coding pass addresses each remaining boundary in production paths:

* `PreparedProject.expansion` owns immutable content-identified expansion pieces.
  Source edits proven independent of the temporal macro namespace splice pieces;
  other edits replay contextual preprocessing. Repeated include occurrences and
  missing include namespaces remain part of the proof. Consumers currently still
  receive a contiguous expanded-text/origin bridge.
* Prepared inputs use segmented CAS records and compact origin blobs rather than
  rewriting one pack containing all expanded and authored source bytes. Cached
  subtree origin replay interns path allocations.
* Invocation syntax/settings/static fragments and inherited owner field/type
  frames have separate persistent identities. A structural prefix rebuild reuses
  matching fragments. Retained invocation overlays no longer duplicate parameter
  names, flags, defaults and types in full lowering frames.
* Symbolic declaration default plans cache parsed variable flags/types, normalized
  constructors and literal list shapes. Physical resource/path slots are supplied
  from the current generation. Cold syntax preparation uses the existing bounded
  ordered worker pool; inherited frames memoize each owner once per prefix revision.
* Declaration-scoped semantic observations share one Salsa input and one refresh;
  invocation-scoped facts remain distinct. Skeleton accounting measures decoded
  owned data rather than multiplying the JSON size by two.
* Constant queries reuse parsed expressions and results after checking the exact
  positive/negative resolver values they observed. Their bounded disk namespace
  restores in bulk and writes batches. Nonfinite JSON values are persistence
  misses. Recursive resolution never occurs under the cache lock.
* Prepared code uses exact assigned-ID/debug-origin output projections, including
  a persistent bounded projection namespace salted by the emission implementation
  fingerprint. Immutable `OutputWords` lets authored procedure results share a
  fragment rather than copy it twice. Final wire lists still need a copy.
* Reference validation caches successful class/procedure records with exact
  dependent-list witnesses and table extent bounds. A borrowed immutable validated
  image can serialize without another reference scan. A digest-bound bytecode
  receipt lets archive-reusing publication avoid reparsing that serialization.
* Resource preparation observes an existing asset proof once per transaction;
  publication still independently revalidates the combined input proof.
  Existing CAS blobs can reuse a digest verification only when a strong file stamp
  still matches a bounded process-local proof. Unsupported stamps/exact-input mode
  continue to read and hash bytes.

These are prototypes, not new timing or correctness evidence. No tests or
benchmarks were run for this coding pass. `cargo check --workspace -j1` passed;
it does not verify runtime behavior or incremental/fresh equivalence.
Full deterministic table allocation,
the contiguous frontend bridge, unsupported preprocessing changes and scalar
output checks still perform program-wide work. New generation publication writes
the complete DMB and links a verified unchanged RSC. Cache capacity can still
cause safe recomputation. These changes do not establish a guarantee that every
edit recomputes only a minimal closure or meets the real-project latency target.

### Production boundary migration (2026-10-02, unmeasured)

The production canonical path now consumes the new boundaries throughout:

* `dm-preprocess::preprocess_project_cached_segmented` writes newline-anchored
  immutable pieces. Unit digests stream piece ranges; bounded subtree cache
  records materialize their own ranges only. Legacy preprocess entry points
  explicitly assemble their returned `text` for compatibility.
* `PreparedProject.expansion` is the source authority. Production prepared
  metadata has empty `project.text`; disk restore and direct splices retain
  pieces without assembling a project-sized buffer. Build snapshots retain the
  expansion and install its view on the frontend before compilation.
* `dm-syntax::SegmentedSource` supplies checked ranges, shared line indexes and
  memoized lexical piece transitions. Canonical declaration parsing does not
  create an all-procedure body-text outline. Body lowering requests only the
  changed procedure range. Modified-type discovery caches chunk-local facts and
  rebases their presentation spans. Resources, diagnostics and JSONL analysis
  consume the same source view.
* Owner declaration plans persist symbolic field expressions, flags, parent
  relationships and signatures. `semantic_declarations` resolves constants and
  qualified defaults against immutable owner/global nodes, independently of
  allocated DMB values. It imports the builtin schema, handles shadowing and
  cycles, and delegates expression dependencies to exact-observation constant
  queries. Worker jobs receive the same immutable semantic model.
* Persistent `EmissionPlans` retain immutable procedure binding ledgers.
  Unchanged plans replay deterministic string allocation and reuse bindings;
  structural edits check the section's actual referenced assignments. Numeric
  allocation remains a separate current-generation projection.
* `Ledger` exposes canonical table assignment fingerprints and assignment deltas.
  Prepared sections reuse binding-ID projections and immutable output words.
  `DmbWireCache` reuses exact wire fragments across offset-independent sections;
  offset-dependent strings are encoded for the current generation. Scoped
  validation covers class/procedure dependent lists and the other large record
  tables. Verified serialization receipts reach generation publication.
* Retained output caches contribute to the coordinator's aggregate frontend
  budget; shared semantic nodes are charged once. Cache misses and eviction
  remain safe recomputation paths. Disk caches use the existing shared project
  cache root and implementation/configuration identities.

This is a code migration, not performance or correctness evidence. The final
`cargo check --workspace -j1` passed without warnings. No tests, benchmarks or
DreamDaemon runs were performed for it. Deterministic dense-table
allocation still traverses records, mutable output vectors require exact-content
fragment checks, and publication writes a complete new DMB generation. Flat
origin/unit metadata and final filesystem proofs can still require linear work.
Changed macro context falls back to contextual preprocessing replay. None of
these operations is evidence that semantic bodies were re-lowered; neither does
cache reuse guarantee a minimal invalidation closure or a three-second build.

### Measuring the real production iteration path

`dm-compile/examples/iteration_bench.rs` calls the actual
`Coordinator::handle(Request::BuildProject)` path with canonical output. Supply a
real project; the harness appends a unique, owned overlay to a copied manifest
beside it so relative includes and generated assets resolve normally. It never
changes the original manifest/game sources and removes the two owned source files
on exit. Prepare the project's generated assets before running it.

The default retained process measures the initial build, unchanged request, one
procedure body edit, adding a procedure/variable, and changing a variable default.
Each edit starts from the baseline; its revert is also recorded. A subsequent new
process measures the cached baseline after the retained process exits. Optional
`--cold-body-edit` uses a previously unseen body revision in another fresh process.
An initial build can use existing disk caches; it is not labelled an empty-cache
build. There is one heavy compiler process at a time, two compiler workers by
default, a 2 GiB Windows process limit, and a configurable phase timeout.

```powershell
cargo build -j1 -p dm-compile --example iteration_bench
E:/cargo-target/dmb-architecture/debug/examples/iteration_bench.exe `
  --project C:/path/to/deepquarry.dme --output C:/path/to/NEW_REPORT_DIRECTORY `
  --cache-root C:/path/to/shared-cache -DCBT -DCIBUILDING -DCITESTING
```

Use `--builtins` for a different supported schema, `--workers 1..4`,
`--memory-mib 1..3072` (default 2048), `--timeout-seconds`, `--skip-cold`, or a reduced
`--cases baseline,unchanged,body-edit` sequence. `iteration.json` records typed
native responses, lowered/reused procedure counts, pair cache hits, streamed DMB
and RSC digest receipts, process wall times, and per-case coordinator trace/stage
times. Coordinator request time includes input preparation/proof validation,
compilation or receipt reuse, and generation publication. Receipt hashing is
outside that timer and has its own duration. Stage timings overlap/nest and must
not be summed as a wall-time partition. Failed native responses and completed
measurements remain in the report; there is no DreamMaker fallback or runtime.
