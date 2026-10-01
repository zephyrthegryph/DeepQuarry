# Persistent incremental DM compiler architecture

Status: proposed implementation architecture. This document designs the next
performance iteration; it does not claim the structures below are implemented.
Baseline: ac1af55d1a, October 1, 2026. Read PERFORMANCE.md for the measured
implementation and FORMAT.md for format evidence. This supersedes the performance
and query design in INCREMENTAL_COMPILER_PLAN.md; that file remains historical.

## Reading guide

- [Goals, reuse contract and measured bottlenecks](#1-objective-and-scope)
- [Crates and dependency flow](#4-crates-and-module-boundaries)
- [Identities, source graph and syntax](#5-identities-and-fundamental-structures)
- [Semantic queries and HIR](#9-semantics-and-the-salsa-graph)
- [Linking, maps, assets and binary patches](#11-incremental-linking-and-allocation)
- [Disk persistence and shared scheduling](#14-persistent-store-and-restart-behavior)
- [Tooling APIs and edit flows](#16-public-tooling-api)
- [Algorithms, measurements and implementation gates](#18-algorithms-and-cost-model)

## 1. Objective and scope

Compile DME/DM directly to supported BYOND DMB/RSC without an OpenDream or Dream
Maker dependency at build time. Expose the same parsed and resolved project to
documentation generators, lints, navigation, reference search, and future tools.
Retain current backend behavior while replacing broad reconstruction with explicit
dependencies, immutable records, persistent revision roots, and output deltas.

The full pipeline is incremental: source discovery, preprocessing, syntax,
declarations, resolution, constants/defaults, initializers, symbolic code,
maps/resources, table allocation, relocation, validation, encoding, and publication.
A change category alone must never force unrelated procedure bodies to compile.

### Reuse contract

For a demanded query, reuse a resident or compatible persisted result if its
recorded semantic dependencies are unchanged. If execution produces an equivalent
result, stop propagation at that boundary. Missing/corrupt/evicted records permit
recomputation. Target/schema/stage incompatibility permits rebuilding the affected
stage. Explain all such decisions.

This is a guarantee relative to a complete dependency model and available cache,
not a guarantee of the mathematical minimum work for arbitrary source changes.
Dependency validation costs work; equivalent results may require computation to
discover equality. Macro edits, inheritance changes, constant propagation, or
observable declaration order may legitimately affect much of a project. Physical
binary rewriting is distinct from semantic recompilation.

The pinned Salsa dependency is 0.28.5. Its tracked queries record field/query reads
and compare returned results; equal results prevent change propagation. Avoid
no_eq at semantic cut points. Compare input fields before calling setters.
See the [Salsa algorithm](https://salsa-rs.github.io/salsa/reference/algorithm.html)
and [pinned API](https://docs.rs/salsa/0.28.5/salsa/).

### Output policies

- Incremental development: preserve valid wire IDs from a compatible link lineage;
  append permitted records and patch eligible output. Bytes may depend on history.
- Canonical: derive table IDs from the current ordered semantic snapshot and target
  rules; produce reproducible bytes. Reuse AST/HIR/symbolic code, then relocate any
  references whose IDs changed.
- Both preserve observable DM behavior: inheritance, override/dispatch chains,
  type enumeration, verbs, startup effects, maps, resource resolution, and reflection.
  Native byte-for-byte parity is not a requirement.
- Removing an observable declaration cannot be implemented by leaving a visible
  zombie class/proc/variable. Update inventories and all affected references or
  compact/relink that table. Retain dead strings/code lists only where target
  semantics prove they are unobservable.
- Canonical materialization is a link/encode operation. It does not imply reparsing
  or lowering every body.

## 2. Measured bottlenecks and design responses

Measured against the frozen full-project test configuration: 48,681 ordinary
procedures, warm operating-system file caches. These are historical observations.

| Path/stage | Measurement | Architecture response |
| --- | ---: | --- |
| Warm daemon body edit | 3.240 s | Explicit changes through all stages |
| Discovery/preprocessing on that edit | 0.951 s | Shared source/expansion segments; macro convergence |
| Resource work on that edit | about 0.15 s | Incremental literal inventory and resource-resolution edges |
| Compiler/emission on that edit | 0.278 s | Changed-ID input, shared scope/ledger indexes, delta validation |
| Checkpoint encode | 0.193 s, 44,105,927 bytes | Small durable revision delta instead of whole JSON checkpoint |
| Artifact CAS writing, including checkpoint encoding | 0.394 s | Packed records, one atomic revision root |
| Final input validation | 0.347 s | Shared journal frontier and incremental namespace dependencies |
| Generation publication | 0.738 s | Reuse validated output records and archive object |
| Fresh CLI body edit with caches | 11.722 s | Lazy restorable project graph |
| Fresh CLI discovery on that edit | 4.073 s | Original source IDs and expansion/layout roots persisted |
| Fresh CLI resource preparation | 3.939 s | Persist inventories, maps, and asset proof subsets |
| Fresh CLI compiler/emission | 1.721 s | Indexed binary checkpoint and lazy linked records |
| Fresh CLI unchanged | 0.152 s | Preserve compact receipt shortcut |
| Compiler-version rebuild | 103.928 s, compiler phase 80.840 s | Continuous pipeline, algorithms, cache packs, phase fingerprints |
| Two concurrent body edits | 3.834 s total; 1,898.6 MiB peak private memory | Share immutable objects; global memory admission |

The 103.928-second run reused 2,695 lowering entries and many preprocessing
expansions. It is not an empty-cache benchmark. Its compiler phase mixes preparation,
cache keys/I/O, parsing, lowering, linking, and publication. Do not attribute all
80.840 seconds to codegen CPU or claim every declaration/resource edit costs 104 s.
The publication observation revisited an existing generation; newly created
generations in the concurrent run cost about 0.33-0.35 s.

Current fallbacks are implementation boundaries: incremental.rs checks a global
declaration ABI and patchable bodies; dm-compiled scopes baseline families by
maps/resource context. This architecture replaces those guards with specific
dependencies and link deltas. Whole-output re-encoding remains a legitimate path.

## 3. Non-negotiable architecture rules

1. Language objects contain portable semantic identities, never BYOND table offsets.
2. Source content, source occurrence, declaration identity, and output ID are distinct.
3. Queries are pure over an immutable revision. Filesystem reads become captured
   inputs before queries; publication and cache writes are driver effects.
4. Every reuse key covers its stage version, target-sensitive rules, options, and
   actual dependencies, including negative lookup results.
5. Body, signature, metadata, documentation, source mapping, and runtime initialization
   have separate equality boundaries.
6. Worktrees share immutable values and computation; mutable inputs and output
   ownership remain scoped to worktree/configuration.
7. No full source concatenation, all-procedure comparison, or monolithic checkpoint
   serialization on the ordinary body-edit critical path.
8. All retained state, live jobs, mapped pages, and cache staging share a process-wide
   memory budget. One-shot execution has the same limits.
9. Binary mutation requires a checked plan and transactional pair publication.
10. Correctness fallback identifies the affected stage and reason. A fallback writer
    does not authorize unrelated lowering.

## 4. Crates and module boundaries

All names below are target architecture, including proposed new crates.

| Crate | Ownership and modules |
| --- | --- |
| dm-source (new) | ids, bytes, revisions, paths, anchors, span maps, expansion origins, persistent sequences; no Salsa/filesystem/BYOND |
| dm-syntax | lexer checkpoints, green syntax, declaration parser, typed body parser, comments/trivia, error recovery; no Salsa |
| dm-preprocess | DME order, directive summaries, include occurrences, persistent macro environments, expansion/effect summaries |
| dm-semantics | declaration contributions/buckets, parent graph, lookup, constants, signatures, metadata, ordered initialization |
| dm-ir | resolved HIR, effects, reference/dependency summaries, optional verified MIR |
| dm-codegen-byond | target schema, opcode selection, symbolic procedure artifacts, stack/control-flow verification |
| dm-link (new) | stable wire ledgers, allocation planning, relocation/reverse-use indexes, metadata/map record deltas |
| dm-resources | resource names/resolution keys, streaming fingerprints/imports, RSC entry/free-slot plans |
| dm-map (new, extract current maps.rs) | DMM/DMF syntax, map dictionaries, chunks, placement streams; DMF may remain a sibling module |
| byond-dmb | target wire structures, lossless codec, format-level validation; retained existing library |
| dm-store (new) | immutable object interning, binary packs, portable memo records, manifests, leases, GC, durability |
| dm-host | filesystem identities, NTFS journal frontier, exact fallback, OS budgets, output leases |
| dm-compiler | Salsa database, query adapters, revision coordinator, build planner, delta propagation, metrics/cancellation |
| dm-analysis (new) | stable read-only tooling facade, lint registry, docs model, references, paginated export/protocol |
| dm-output | record layout tree, patch planner, validated artifacts, DMB/RSC pair transactions, generation HEAD |
| dm-compiled | transport, project/session registry, watcher service, global task scheduler, cache service |
| dm-compile | CLI build/check/patch/docs/lint/explain-rebuild/cache; one-shot and daemon clients |

Dependency direction: source/syntax/preprocess/semantics/IR are reusable libraries.
dm-compiler orchestrates their queries. dm-analysis consumes that query interface.
dm-link consumes target code and semantic metadata. dm-output consumes checked
record plans. No analysis tool imports a daemon, serializes DMB to recover language
facts, or invokes the compiler backend merely to obtain documentation.

Prefer modules within existing crates until a boundary has clear ownership. Extract
dm-source/dm-store/dm-link when their interfaces stabilize. Avoid a large simultaneous
crate shuffle; move current implementations behind adapters.

~~~mermaid
flowchart TD
  V[Captured source and namespace inputs] --> P[Include and expansion graph]
  P --> S[Syntax fragments and declaration contributions]
  S --> Q[Salsa semantic queries]
  Q --> A[Analysis snapshots: docs, lint, navigation]
  Q --> H[Resolved HIR and symbolic code]
  M[Map and asset queries] --> L[Table plan and link deltas]
  H --> L
  L --> O[Record layout, validation and patch plan]
  O --> T[Transactional DMB/RSC publication]
  C[Shared immutable store and disk packs] --- P
  C --- S
  C --- Q
  C --- H
  C --- L
~~~

## 5. Identities and fundamental structures

These Rust sketches describe interfaces; they are not drop-in compilable source.

~~~rust
struct ContentId([u8; 32]);                 // Framed digest of exact canonical bytes.
struct StageVersion(ContentId);
struct RevisionId(ContentId);              // Project snapshot root.
struct FileKey { project_path: LosslessPath }
struct SourceRevision {
    file: FileKey,
    raw_content: ContentId,
    decoded_content: ContentId,
    decoder: StageVersion,
    encoding_map: EncodingMapRef,
}
struct AnchorId(u128);                     // Persisted syntax anchor, not byte offset.
struct IncludeOccurrenceKey { parent: OccurrenceKey, directive: AnchorId }
struct DeclKey { occurrence: OccurrenceKey, anchor: AnchorId }
struct SymbolKey { owner: PathKey, name: NameKey, kind: SymbolKind }
// SymbolKey identifies a lookup bucket; LinkSymbolKey identifies an exact target.
enum LinkSymbolKey {
    Declaration(DeclKey),
    EffectiveMember(SymbolKey),
    Storage { owner: DeclKey, local_anchor: AnchorId },
    Helper { owner: DeclKey, role: HelperRole, anchor: AnchorId },
    ModifiedInstance { base: PathKey, overrides: ContentId },
    Literal(LiteralKey),
    Resource(ResourceKey),
}
struct ProcArtifactKey {
    semantic_context: ContentId,
    body: ContentId,
    dependencies: ContentId,
}
struct WireId { table: TableKind, index: u32 }

struct SourceSpan {
    source: SourceRevision,
    range: Range<u32>,
}
struct ExpansionSpan {
    fragment: ContentId,
    range: Range<u32>,
    origin: OriginRef,
}
struct BuildDelta {
    changed_files: SmallVec<FileKey>,
    changed_fragments: SmallVec<FragmentKey>,
    changed_declarations: SmallVec<DeclKey>,
    changed_queries: SmallVec<PortableQueryKey>,
    changed_procedures: SmallVec<DeclKey>,
    changed_map_chunks: SmallVec<MapChunkKey>,
    changed_resources: SmallVec<ResourceKey>,
    changed_records: SmallVec<RecordKey>,
}
struct ProjectRevision {
    sources: PersistentMap<FileKey, SourceRevision>,
    expansion_root: ExpansionTreeRef,
    declarations_root: DeclarationTreeRef,
    semantic_memos_root: MemoTreeRef,
    assets_root: AssetManifestRef,
    maps_root: MapManifestRef,
    link_root: Option<LinkRevisionRef>,
    proof_root: InputProofRef,
}
~~~

SmallVec is illustrative: use a small inline collection only where profiling proves
the common small cardinality. IDs held inside arenas may be u32; persistent keys
and serialized records use portable dictionaries. Salsa handles are reacquired in
each revision and never written to disk.

### Stable anchors and ordering

Preserve anchors by matching declaration/directive headers and unaffected syntax
nodes within an edited file. Match stable unique candidates first, then use bounded
sequence matching in the changed region. Avoid unbounded quadratic LCS. A difficult
duplicate/reorder allocates new occurrence identities and invalidates that bucket.

Anchors are lineage identities. Two worktrees may assign different anchors to the
same new text; pure artifact keys use canonical content/dependency identities so
they still share computation. Canonical output does not depend on anchor allocation.

Keep source order separately in an order-statistic B-tree. Order is observable for
includes, override contributions, initializers, and target enumeration. Insertion
updates a tree path; it does not renumber every declaration. Fingerprints frame
child count, order, kind, and digest. A Merkle root is not a concatenated-file SHA;
version the fingerprint scheme rather than substituting it under an existing key.

## 6. Captured filesystem and namespace inputs

A FileKey is a lexical source identity; a FileProof is a physical file identity.
Keep lossless Windows paths and authored resource names; do not lowercase every
path, conflate symlink aliases, or discard spelling used by diagnostics/resources.

The host maintains one journal frontier per supported volume, routing events to
interested sessions through a file-ID and namespace-edge index. Each session
receives dirty files, missing-candidate changes, directory moves/reparse changes,
and resource shadows. Watchers are hints. Supported proof barriers/journal coverage
or an exact reread establish correctness; retain DM_BUILD_EXACT_INPUTS behavior.

Resolution is a query over captured ordered search candidates. A missing higher
precedence candidate is an explicit dependency. FILE_DIR order, includes outside
the root, generated icons, skin selection, and junction targets are tracked inputs.
A unrelated child in a directory must not invalidate all resource resolutions.

Capture inputs before work, retain that snapshot, and validate the changed/journal
interval again before commit. A concurrent edit may produce reusable old artifacts,
but it cannot publish the old result as current. External disk edits require reading
and hashing the changed file, even if only one procedure in it changed. Editor
range updates can avoid discovery work only when tied to a verified source revision.

Do not put OS open/stat calls directly inside semantic queries. Expose immutable
FileRevisionInput and ResolutionInput fields updated only when their values change.

## 7. Preprocessing: expansion graph and macro convergence

### Representations

~~~rust
struct MacroEnvRef(PersistentMapRef<NameKey, MacroDefinitionRef>);
struct MacroObservation { name: NameKey, value: Option<ContentId> }
struct ExpansionFragment {
    bytes: SharedBytesRef,
    token_tree: TokenTreeRef,
    origins: OriginMapRef,
    entry_state: LexDirectiveState,
    exit_state: LexDirectiveState,
}
struct IncludeResult {
    fragments: ExpansionTreeRef,
    macro_reads: Arc<[MacroObservation]>,
    macro_effects: MacroDeltaRef,
    ordered_effects: IncludeEffectsRef,
    nested_occurrences: OccurrenceTreeRef,
}
struct IncludeEffects {
    file_dirs: OrderedContributions<PathKey>,
    maps: OrderedContributions<MapKey>,
    skins: OrderedContributions<SkinKey>,
    diagnostics: DiagnosticSetRef,
    deferred_manifest_items: ExpansionTreeRef,
}
~~~

Use a structurally shared HAMT for macro environments and small sorted deltas for
definitions/undefines. Hash macro definitions once when they change. Query expansion
against relevant positive/negative macro observations. Dynamic directives, token
paste, or uncertain dependencies use the complete relevant environment as an
explicit conservative dependency, with a recorded reason.

Maintain each include occurrence separately: the same file may expand differently
under different macro states or at different positions. Preserve existing DME
deferred-manifest behavior and source/include effect order.

### Update algorithm

1. Identify dirty source/directive fragments and include edges.
2. Derive the current entry state from the current predecessor and ordered effects;
   reuse the previous state only when it is proven equivalent. Simultaneous edits
   can change both the source and its incoming macro environment.
3. Compare expanded fragment contents, macro delta, and ordered effects separately.
4. Propagate macro/effect changes to subsequent occurrences only while needed.
5. Reuse a suffix when its observed inputs, macro/effect state, include resolution,
   and lexical context converge. Identical expanded text alone is insufficient.
6. Replace changed leaves in an expansion B-tree; unchanged leaves and source maps
   remain shared. Downstream parsing traverses fragments without flattening them.

Pure macro propagation is inherently ordered. Cold source reads, directive lexing,
macro-independent regions, and parsing of completed safe fragments can run in
parallel. Do not expand all includes concurrently under one guessed environment.

A body edit with unchanged preprocessor effects costs changed-file/fragment work
plus tree updates; it must not append all 40+ MiB of expanded text again. Origin
maps remain fragment-local; absolute project offsets are computed by prefix sums
only for presentation/compatibility adapters.

## 8. Syntax: lossless tree plus typed procedure bodies

Keep raw source, decoded text, comments, trivia, and macro provenance for
documentation/refactoring. Legacy mixed Windows/UTF-8 decoding is versioned; raw
and decoded content have separate identities. An encoding map translates editable
decoded ranges to exact raw byte ranges. Reject ambiguous/synthesized fix ranges
instead of editing macro definitions or arguments accidentally.
Use immutable green nodes and compact typed AST arenas; token ranges point to shared
source fragments. Keep a declaration skeleton separate from body content so a body
edit does not change every declaration descriptor.

Lexer checkpoints include indentation, delimiter nesting, comment/string/interpolation
state, and source continuation mode. Re-lex from the preceding safe checkpoint
until tokens and state converge; reparse the smallest enclosing grammar production.
Preserve whole-fragment fallback for malformed/cross-boundary states. An edit
opening a multi-line string/comment can legitimately affect the remaining file.

Expose one FrontendRevision per build. Resource literal inventory, declaration
contributions, docs attachment, procedure AST, and source maps come from it.
Do not run a second outline assembly for resource scanning.

Typed procedure ASTs include expressions, lvalues, statements, control flow,
arguments/defaults, local/statics declarations, and set metadata. Parse a procedure
once and cache that typed result; the backend must not rediscover typed statements
from strings on every lowering miss.

Split projections:
- SemanticBody: semantic tokens/AST and local declaration structure.
- ProcedureHeader: names, restrictions, argument/default structure.
- ProcedureMetadata: set/verb/source attributes.
- Documentation: comments and documented declarations.
- Presentation: spans and original spelling.

A comment/format edit may execute syntax work, but equal SemanticBody and Header
results stop codegen invalidation. Syntax fragments are keyed by contents plus
entry lexical context and parser schema, not by the whole compiler implementation.

## 9. Semantics and the Salsa graph

### Declaration store

Each expansion fragment contributes declarations to buckets keyed by
(owner, member name, kind). Buckets contain ordered DeclKeys with independently
versioned header/body/default/docs/metadata fields. Maintain reverse contributions
fragment -> buckets; update only touched buckets. Effective definitions and override
chains are derived from those buckets and parent edges.

An absent bucket is queryable. Do not return an untracked None from a global
HashMap read. Scope lookup records every unsuccessful local/inherited lookup and
every parent edge actually traversed. New declarations therefore invalidate names
they shadow. Dynamic member dispatch remains dynamic; static type information must
not silently change dispatch semantics.

Cold bucket construction appends contributions in source order: expected linear
index construction. If producers finish out of order, merge their ordered streams
or sort contribution keys once. Use persistent hash lookup plus ordered small
vectors/B-trees within a bucket; avoid copying all inherited fields into every proc.

### Query families

| Query | Dependencies/result boundary |
| --- | --- |
| directive_summary(file/fragment) | Source revision and directive lexer rules |
| expand_occurrence(occurrence, context) | Macro observations, include resolution, ordered effects |
| syntax_fragment(fragment) | Tokens/entry lexical state and syntax schema |
| declaration_contributions(fragment) | Declaration skeleton, order, semantic headers |
| member_bucket(owner,name,kind) | Contributions for that exact bucket, including emptiness |
| parent_type(type) | Effective parent declaration and target builtins |
| resolve_member(owner,name,kind) | Bucket and traversed parent edges |
| overridden_definition(decl) | Ordered local chain and applicable inherited lookup |
| declared_type(decl) | Type expression and resolved referenced declarations |
| procedure_signature(decl) | Formal names/types/restrictions/calling rules |
| procedure_metadata(decl) | set/verb/source flags and related expressions |
| constant_value(decl) | Expression and constants/types it reads |
| default_value(decl) | Declared default expression and required compile-time facts |
| contextual_value(occurrence/decl,name) | Observed __FILE__, __LINE__, __PROC__, __TYPE__ and target context |
| initializer_artifact(decl) | Runtime expression, resolved scope, ordering contribution |
| resolved_body(proc) | Semantic body, local scope, and exact lookup dependencies |
| procedure_hir(proc) | Resolution results and language semantics schema |
| symbolic_proc(proc,target) | HIR and target opcode-selection rules |
| resource_resolution(name,scope) | Ordered namespace candidates and FILE_DIR state |
| asset_descriptor(resource) | Payload digest, kind, BYOND content CRC, authored name |
| map_dictionary(map,key) | Parsed definition and referenced type/default/asset facts |
| map_chunk(map,chunk) | Placement runs, dictionary definitions, dimensions |
| allocate/link/encode(record) | Required symbolic IDs, target widths, layout context |

Query keys must remain stable across revisions. Do not pass the changing whole
ProjectRevisionId, whole project text, or complete macro-environment digest to every
procedure query. Those values would create new keys or broad dependencies on every
edit. The revision token belongs in the driver/tool envelope; a tracked procedure
query reads its declaration/body/signature fields and narrow dependencies.

Macro context is a stable occurrence identity with derived state. A tracked
macro_value(context, name) or persistent-map bucket projection reads the requested
binding and returns an independently comparable value, including None. Environment
changes can revalidate cheap projections while equal bindings keep expansions
reusable. Cached observation sets additionally avoid expanding unaffected includes.
Use the same pattern for member buckets, target options, and resource resolutions:
lookup tables are indexed storage, not one monolithic dependency value consumed by
all bodies.

Query results are compact immutable artifact references or small owned semantic
records with meaningful equality. Separate changed source locations from code
semantics. Avoid one global ABI hash as the body-change eligibility oracle.

### Dependency details and cycles

Calls depend on the callee's signature/dispatch facts, not its body. Signature
changes affect callers only where lowering uses the changed calling facts. Defaults
and argument-source helpers are separate artifacts. Procedure-static storage and
startup programs are separate from the ordinary body.

Typed receiver lookup narrows member dependencies to the traversed classes/buckets,
rather than all classes with a member of that spelling. Reflection operations record
the inventories they actually expose. Dynamic runtime lookup remains conservative.

Context builtins are semantic observations. Expansion/resolution records file/line,
current procedure/type, and target context only where those values are read. Split
presentation-only origin changes from observed contextual values: a newline/comment
insertion can change code using __LINE__, and include movement/rename can change
__FILE__ or other context. Semantic equality cutoffs apply only after those expanded
values agree. Debug/source metadata has its own dependency regardless of whether
the body reads a contextual builtin.

Validate the cold parent graph with DFS coloring/Tarjan in O(types + edges);
constant graphs use cycle diagnostics and SCCs where required. Never fabricate
null/zero to hide a compile-time cycle. Recursive procedure calls are legal because
signature queries do not recursively demand body queries. A structural edit can
use a local affected graph walk or a full linear validation when cheaper.

Initializer execution preserves DM-defined/source ordering and effects. Dependency
analysis does not license topologically sorting observable startup side effects.
An initializer edit changes its fragment and ordered program composition.

Salsa owns live dependency tracking; compiler-owned portable query manifests
support disk reuse and explain-rebuild. Reverse use/dependency indexes update from
changed summaries. Graph mutation and writes happen at revision boundaries.

### Discovering affected work without a whole-project scan

Persist a reverse witness index alongside each project revision:

~~~rust
struct ReverseWitnessIndex {
    consumers: PersistentMap<PortableRead, MemoIdSetRef>,
    demanded_roots: DemandIndexRef,
}
~~~

The index covers every recorded input-field read and query-output projection,
including absent member buckets, namespace misses, contextual builtins, target
options, and ordering observations. HIR call/reference summaries alone are not a
complete invalidation graph. Instrumented adapters record immediate reads in each
query's own recorder frame; projection reads pass through tracked adapters too.
Salsa remains authoritative for live query validation and execution; the compiler
index schedules demands and explains affected work, rather than replacing Salsa's
dependency checks or importing its private graph.

1. Source/namespace journals and immutable-tree comparisons identify changed
   input fields, range roots, configuration fields, and stage versions. Update only
   those stable Salsa inputs at a revision boundary.
2. Seed a deduplicated worklist from the reverse index of those fields. Restore
   only the corresponding index pages on an edited restart. Intersect candidates
   with the current build/tool demand set; stale unused memo records are not work.
3. Demand an affected query through Salsa. Compare its independently observable
   result projections with the previous values. Equal projections stop propagation;
   changed projections enqueue their indexed consumers. Cold/missing nodes compute
   normally. Salsa detects recursion/cancellation; the planner does not impose an
   arbitrary evaluation order that changes language semantics.
4. Reconcile old/new immediate read sets even if the result is equal. This catches
   branches that exchange dependencies without changing today's output. Commit memo,
   forward witnesses, reverse edges, and revision roots in one durable revision.
   Readers use an immutable revision; cancelled work never publishes mixed edges.
5. Declaration/map/resource inventory deltas introduce newly demanded nodes and
   remove obsolete ones. Preserve untouched output/analysis subtrees and update
   only changed leaves and their composition paths. Do not implement a top-level
   build query that requests every procedure on every edit.

Dependencies on inventories or ordered programs use partition/range projections
where their consumers permit it. Global semantic consumers still observe their
actual full set. An index coverage/schema mismatch triggers conservative rebuilding
of the affected index and records a fallback reason. It must never silently omit a
consumer. Persisted reverse witnesses enable small edited restarts; merely storing
procedure artifacts would still require finding and validating them all.

Count dirty-enumeration visits, memo validations, and executions separately. A
zero-codegen edit that validates every procedure has not met the iteration goal.
Sparse changes should visit the affected witness closure plus changed composition
paths, while global edits may correctly visit a large closure.

### Session lifecycle

Each worktree/build configuration owns its mutable Salsa roots. Keep them stable
across edits; update only changed fields, with higher durability reserved for
versioned immutable target/builtin data. Do not recreate the database every build.

Return immutable values/ContentIds to the shared store. LRU alone is not a process
memory budget: it evicts memo values while keys/dependency metadata remain. Track
metadata too; reclaim idle sessions or perform a quiescent database replacement
from a persistent project root when necessary. This is explicit cache eviction,
not normal edit flow. See [Salsa tuning](https://salsa-rs.github.io/salsa/tuning.html).

The measured invalidation contract applies to retained or compatible disk records.
Eviction may make a logically unchanged query execute; distinguish that from
semantic invalidation in metrics and user reports.

## 10. HIR, procedure artifacts, and reusable facts

~~~rust
struct ResolvedProcedure {
    declaration: DeclKey,
    signature: SignatureRef,
    body: HirBodyRef,
    lookups: Arc<[DependencyWitness]>,
    references: ReferenceSummaryRef,
    effects: EffectSummaryRef,
    origin_templates: RelativeOriginTemplatesRef,
}
struct HirBody {
    expressions: Arena<HirExpr>,
    statements: Arena<HirStmt>,
    locals: Arena<LocalDef>,
    entry: StmtId,
}
struct ProcedureArtifact {
    instructions: SymbolicCodeRef,
    relocations: Arc<[SymbolRelocation]>,
    literals: LiteralSummaryRef,
    locals: LocalMetadataRef,
    argument_helpers: Arc<[ArtifactRef]>,
    stack_summary: StackVerificationRef,
    semantic_dependencies: DependencySetRef,
}
struct SymbolRelocation {
    instruction: InstructionId,
    operand: OperandSlot,
    target: DependencySlot,
    encoding: RelocationEncoding,
}
~~~

HIR explicitly models DM number/null/list/string semantics, evaluation order,
lvalue capture, dynamic/static dispatch, src/usr/args, iterator/exception cleanup,
and suspend effects. Use numeric interned identifiers and local arena indices.
Separate portable artifact dictionaries from session interner IDs.

HIR origin templates refer to stable token/anchor identities and relative ranges.
A separate presentation query binds them to the requested revision's OriginMapRef.
Current source spans and diagnostic fixes are never part of a reused semantic memo
without current location witnesses; moving source must not leave tooling with old
locations or force unrelated symbolic code to execute.

Shared procedure artifacts use canonical dependency slots and portable lookup/
contract descriptors. Each resolved procedure supplies a checked binding from
those slots to its exact LinkSymbolKeys. Lineage-specific DeclKeys/AnchorIds do not
enter the shared symbolic artifact key. The semantic-context fingerprint still
covers observed owner/current-procedure facts, private/static types, dispatch role,
and target rules. Reuse requires equivalent resolution contracts, not merely equal
body text. Rebinding exact symbols preserves cross-worktree sharing while keeping
duplicate definitions, proc statics, and generated helpers distinct.

The initial migration uses typed AST -> resolved HIR -> the proven current symbolic
code backend. MIR is optional initially. Add a control-flow MIR when it simplifies
effect/stack validation or tooling; preserve all language behavior through fixtures.

Reference/effect summaries are produced once with HIR. Reverse references, call
graphs, lint rules, documentation links, initializer dependencies, and relocation
uses reuse those summaries. Unknown dynamic targets are represented explicitly,
not reported as a complete call graph.

Replace the accumulated initializer search in bootstrap.rs with each procedure's
own initializer range/contribution. Maintain hash indexes for string interning,
class/proc identity, and owner scopes; avoid scanning complete DMB tables to
reconstruct them for an edit.

## 11. Incremental linking and allocation

### Separate semantic code from numeric placement

~~~rust
struct LinkRevision {
    policy: LinkPolicy,
    target: TargetSchemaRef,
    allocation: PersistentMap<LinkSymbolKey, WireId>,
    records: PersistentMap<RecordKey, LinkedRecordRef>,
    symbol_uses: PersistentMap<LinkSymbolKey, UseSetRef>,
    observable_orders: ObservableOrderRoots,
    widths: WidthPlan,
}
struct LinkedRecord {
    content: DecodedRecordRef,
    references: ReferenceSummaryRef,
    relocation_inputs: RelocationWitnessRef,
}
struct LinkDelta {
    allocations: AllocationDelta,
    updated_records: SmallVec<RecordKey>,
    removed_records: SmallVec<RecordKey>,
    changed_observable_orders: SmallVec<OrderKey>,
    width_change: Option<WidthTransition>,
}
~~~

Allocate declaration-backed symbols and startup storage from ordered metadata
before procedure lowering where possible. Generated helpers/literals contribute
compact summaries. Once the allocation plan is frozen, relocate/encode independent
procedure records concurrently.

An effective member bucket is not an exact wire symbol. Multiple legal definitions
in one bucket, a previous definition called by ..(), proc-static storage, and
argument/initializer helpers need distinct LinkSymbolKeys. Resolve effective aliases
to exact declarations before allocation/relocation. Reverse-use entries track the
resolved target and any alias/override-chain query needed to select it.

For development, preserve existing valid IDs and append new entries where legal.
A record depends only on IDs it references and encoding widths; adding an unrelated
string does not relink every procedure. For canonical allocation, diff the ledger
and use symbol_uses to relink records referencing changed IDs. If most IDs move,
a bulk parallel relocation pass is cheaper than a sparse update. Reuse symbolic
artifacts in both cases.

ResourceKey is the authored resource identity. Wire resource-index identity is
separate from the content-derived RSC CRC. An asset replacement with retained index
updates its DMB resource descriptor and RSC record; it does not lower bodies that
refer to that unchanged index.

Class/default/verb inventories and modified map-instance records have their own
queries/record identities. Defaults invalidate actual consumers, including map
instances that inherit them. Their change is not a project-wide lowering key.

Deletion/reordering has observable consequences. Maintain target-specific table
policies and sentinel handling. Tombstone only proven inert records. Otherwise
replan affected tables, update reflection inventories and relocate dependent
records. The wider-table threshold/reserved IDs have explicit transitions; a
transition may require complete encoding but no new semantic lowering.

## 12. Maps and assets

### Maps

Parse DMM into immutable dictionary definitions and placement runs. Key each
dictionary contribution and bounded placement chunk separately. A dictionary edit
invalidates chunks using that key through a reverse-use index. Placement edits
update affected chunks; type-default changes update instances using those defaults.

Chunk IDs include file/map occurrence and position identity; composition order
and z-offsets remain explicit. DMB grid output uses composable RLE summaries:
merge boundary runs when equal rather than rebuilding the entire map grid. A
dimension/offset change can affect much of placement output; reuse dictionary and
semantic results. Recompute runs per affected chunk and update sequence prefix sums.

Skin content/import metadata is an asset query. DME selection and effective
client script dependencies are distinct from the raw file bytes.

### Assets

Maintain an ordered persistent literal/import inventory from syntax and maps.
Resolution depends on candidate namespace observations. Import each changed asset
once: stream bytes into an immutable payload object while computing strong digest,
BYOND CRC, length, and kind. RSC writing consumes that payload reference. Do not
fingerprint all bytes, then reread all bytes into another complete ResourceSet.

Payload-only edits preserve resource-index identities where legal. Kind/name/order
changes update descriptors and actual users. Store a strong digest alongside the
32-bit wire CRC; never use BYOND CRC alone as a cache identity. Detect incompatible
collisions that make wire pair resolution ambiguous.

Retain unknown/opaque RSC wrappers in format inspection/roundtrip paths. Newly
generated archives use known target encodings and explicit capacity policies.

## 13. Indexed output and binary patching

### Persistent layout

~~~rust
struct ImageRevision {
    target: TargetSchemaRef,
    records: RecordSequenceRef,
    decoded_root: LinkedRecordsRoot,
    layout_root: LayoutTreeRef,
    validation_root: ValidationRoot,
}
struct LayoutNode {
    encoded_len: u64,
    logical_digest: ContentId,
    children: NodeChildren,
}
struct EncodedRecord {
    key: RecordKey,
    bytes: BlobRef,
    placement: PlacementRule,
    references: ReferenceSummaryRef,
}
enum PlacementRule {
    Independent,
    StringCipher { origin: CipherOrigin },
    TargetDependent(TargetPlacementRule),
}
enum PublishPlan {
    NoChange,
    FixedSpans(PairPatch),
    NewGeneration(StreamingImagePlan),
}
~~~

Use an order-statistic B-tree with cached encoded lengths/digests. A changed record
updates O(log records) nodes; offsets are prefix sums. Length changes do not
require rewriting every stored offset in a Vec. Relocation dependencies and
placement dependencies are separate.

The image tree's logical digest is incremental and versioned. Flat SHA-256 of an
entire DMB/RSC is not composable from child SHA digests. Compute flat digests during
materialization when required for compatibility/export; use the authenticated
record-tree root for new internal manifests and receipts. Do not silently reinterpret
the existing generation-ID/hash protocol.

### DMB patch decision table

| Change | Reused work | Required physical action |
| --- | --- | --- |
| Same-length list/code replacement, same tables/width | All other records and validation certificates | Changed spans in private stopped output, or stream a new generation |
| Code-list growth/shrink after strings | Other encoded records, prefix/layout summaries | Stream splice/new generation; copy suffix, no string re-encryption |
| New locals/string/proc metadata | Semantic/symbolic bodies without changed dependencies | Update touched tables; placement-dependent string closure; stream generation |
| String bytes changed at same serialized length | Other string encodings if offsets are unchanged | Replace string span, byte-count/checksum fields as needed |
| String length changed or earlier tables shift | Semantic code and position-independent records | Re-encode strings whose cipher origin-relative offsets changed |
| Table ID remapping | All source/HIR/symbolic code | Relocate referenced records through reverse-use index |
| Object width transition/header/schema change | Compatible semantic artifacts | Complete affected wire encoding; full writer if target contract requires |

String lengths XOR the origin-relative position; string payload cipher seeds depend
on that position. Classes/mobs before strings can therefore invalidate every
encrypted string even when the string contents are unchanged. List growth after
the string table does not. The exact codec remains the authority.

The NQCRC of concatenated plaintext strings plus terminators can use a composable
CRC summary. The current update is linear over GF(2); represent each fragment's
state transition as advance-by-length plus CRC-from-zero, compose tree nodes, and
apply the root transform to the required initial state. Validate against the
existing bytewise implementation before using it. Bound matrix/summary memory;
chunked summaries and precomputed shift powers avoid one large matrix per string.
This updates the checksum without rescanning every unchanged plaintext string.
It does not avoid re-encryption when positions change.

### RSC replacement and free capacity

RSC uses variable-length outer entries and observed validity-zero free slots.
Keep an indexed free-slot structure keyed by capacity (B-tree best fit) and ordered
live entry metadata keyed by ResourceKey. Reuse a sufficient slot when target
fixtures prove valid splitting/trailing-capacity handling. Update validity,
content CRC, kind, declared size, name, and payload consistently.

A payload growth can consume another free slot or append a new entry and invalidate
the old slot, preserving other entry bytes. The DMB resource descriptor must change
with the CRC/kind. A shrinking slot may retain capacity. Unreferenced live resources
are not automatically equivalent to absent ones for every policy; canonical output
compacts the archive and enforces the intended live inventory.

Implement archive compaction separately from semantic compilation. Use byte/fragmentation
thresholds chosen from measurements; don't run compaction on every edit. Unchanged
RSC is one shared immutable archive object across all generations/worktrees.

### Validation and transactions

A private ValidatedImage capability is constructed only by full validation of a
baseline, or by a checked delta whose unchanged records remain valid. It carries
target/schema, baseline lineage, record roots, resource-pair compatibility, and
changed-record reference/stack checks. Public arbitrary-byte APIs fully validate.
Do not replace checks with a caller-provided boolean.

Track incoming uses of changed/deleted table IDs, class/global metadata, resources,
and local/argument records. Delta validation checks the changed closure and target
limits. A target invariant without a local proof demands that invariant's full pass,
not unrelated recompilation. Publication consumes this capability and verifies
actual written spans/file identity; it does not decode the entire image again.

Two publication modes:
1. Immutable generation: stream reused/changed records to private files, flush,
   publish the complete directory and pair manifest, then atomically advance HEAD.
   Existing readers retain the prior generation.
2. Exclusive stopped-output patch: acquire actual exclusive DMB/RSC ownership and
   pair lease; verify baseline proof, persist/flush undo spans and old/new manifest
   IDs, apply changed spans, flush both files, validate changed bytes, then publish
   a commit marker/manifest. Recovery rolls back an uncommitted transaction before
   readers/writers may use the pair.

Two ordinary filenames cannot be atomically overwritten as a pair for arbitrary
live readers. In-place patching requires exclusive ownership. Never mutate a file
hardlinked to an immutable generation or shared cache; copy/detach it first.
Variable-length shifts use a new generation, unless a separately proven target
free-slot scheme applies. Disk copying can remain O(output bytes) even when
compilation is O(changed semantic work). Do not pad executable code with guessed
NOPs or use unsupported indirection to make a patch fit.

## 14. Persistent store and restart behavior

Default root: the Git common directory / dm-compiled-cache, shared by worktrees.
Standalone root: project-local .dm-cache. Keep user-selected cache roots supported.

~~~text
dm-compiled-cache/v2/
  schema/                         stage/target compatibility descriptors
  packs/<stage>/<pack-id>.pack     immutable typed records and checksum index
  indexes/<stage>/...              lookup roots for content/dependency keys
  projects/<context>/HEAD          atomic revision manifest pointer
  projects/<context>/revisions/    small immutable manifest records
  leases/                         active root/pack/output pins
  outputs/                        optional immutable image/archive objects
  gc/                             compaction and resumable maintenance state
~~~

Project contexts include lossless project/worktree identity, target/options/defines,
and output policy. Pure objects are content/context keyed and shared independently
of path; path-sensitive diagnostics/origins/resolution include the needed context.

### Pack format

Use framed binary records with magic/schema, record kind, content ID, dependency
manifest ID, length, and checksum. A compact immutable index maps IDs to ranges.
Validate bounds, lengths, kind/version, and checksum before exposing records.
Use bounded read windows first; memory mapping is optional and requires a pin
against compaction/deletion plus mapped/resident-page accounting.

Store typed arrays, local dictionaries, offsets, and compact tags. Retain decoded
Arc objects in memory; don't deserialize JSON on an in-memory cache hit. Keep JSON
for reports/debug exports. Avoid memory-heavy compression on the critical path;
compression/GC can run as bounded maintenance if benchmarks justify it.

Writers stage per-producer packs and atomically publish immutable completed packs;
no globally locked append file on every procedure. Seal by byte budget or revision.
Readers never see unfinished indexes. Concurrent identical computations use a
single-flight registry by complete artifact key. Cancellation of one waiter does
not cancel shared work still demanded elsewhere.

A durable revision root points only to durable pack records. Flush records/packs
and their published indexes before the root commit. Replace the root atomically
with recovery rules appropriate to the host. Immutable historical revision objects
may be stored before final proof validation; advancing a current-project HEAD or
output HEAD requires that validation. Include the analysis revision in the output
pair manifest. The driver recovers mismatched project/output heads from the last
committed pair record; it never treats two independent renames as one atomic event. Optional speculative cache objects
can publish later and fail without failing an already committed build.

### Portable memo restoration

~~~rust
struct PortableMemo {
    query: PortableQueryKey,
    implementation: StageVersion,
    dependencies: Arc<[DependencyWitness]>,
    result: ArtifactRef,
    diagnostics: RelativeDiagnosticTemplatesRef,
}
enum PortableRead {
    InputField { input: PortableInputKey, field: FieldKey },
    QueryOutput { query: PortableQueryKey, projection: ProjectionKey },
}
struct DependencyWitness {
    source: PortableRead,
    value: SemanticFingerprint,
}
~~~

Salsa is not the persistent database. Do not serialize its handles/internal memo
pages or assume an undocumented memo import API. On cold demand, read the portable
memo, reissue its input-field and query-output reads through current tracked adapters, and
accept its result only when stage and dependency witnesses match. This both checks
disk reuse and records the live Salsa dependencies. A failed witness computes the
query normally and captures its current reads/results.

Compiler-owned read wrappers capture portable witnesses for direct fields, target/
stage/options, and other queries; do not assume Salsa exports a stable serialized
read graph. Optional debug instrumentation compares these witnesses to live query
behavior. Memoized diagnostics retain relative token/anchor locations and provenance
templates; render them through the current revision's origin/source map. A cache hit
must not return stale revision-qualified diagnostic spans after an insertion.

Root manifests and unchanged subtree identities prune restoration/validation.
Avoid loading every memo or walking every procedure to start a body edit. Restore
source/expansion/bucket/resource/link and reverse-witness roots; demand only the
changed closure described in section 9. Indexed dependency edges share the durable
revision transaction with their memo read sets, so a restarted planner cannot see
new results paired with obsolete reverse dependencies.
Input proofs authenticate the original path-to-content bindings; don't apply a
proof for one old content revision to an arbitrary cached expansion from another
worktree.

Use separate stage fingerprints for source decoding, directives/preprocessing,
syntax schema, semantic rules, HIR, opcode selection, target encoding, host proof
protocol, and output/manifest schema. Include relevant implementation dependencies
and transitive rule versions. A host scheduler or test-profile edit should not
invalidate unchanged parser/lowering semantics through one whole-workspace hash.
Cache compatibility is explicit and tested, not inferred from an unchanged crate name.

### GC and retention

Active tool/build snapshots and output generations pin their roots and reachable
packs. Mark reachable records, compact selected packs, publish replacement indexes,
then delete old packs only after readers release leases. On Windows use actual
OS file/lease ownership so an abandoned PID file cannot pin data forever; stale
leases require identity/liveness validation. Cross-process GC cannot delete files
held by another reader or rename a mapped pack beneath a live index.

Bound disk bytes, number of revisions, and dead-record fraction. Keep recent revision
roots; consolidate delta chains so restart never replays unlimited history.
Checkpoint compaction is maintenance, not mandatory 44 MB serialization per edit.

## 15. Scheduling, sessions, worktrees, and cancellation

### Shared memory model

A process-wide immutable object store interns source chunks, syntax/HIR, semantic
values, code artifacts, and linked record pages. Worktrees own lightweight revision
roots and mutable input overlays. Shared base objects are keyed by complete context;
identical source bytes alone do not imply identical macro expansion or resolution.

Use persistent maps and chunked arrays instead of whole DMB/checkpoint clones.
Metadata/proof/output ownership remains session-specific. Multiple projects/configs
in a worktree can share objects without overwriting each other's revision roots.

One-shot processes use the same driver/store/manifest logic and read common packs.
A daemon supplies shared live objects and scheduling. Separate processes share
disk artifacts/leases and can mmap read-only packs; they do not share mutable
Salsa handles. A future broker is an optimization of this interface.

### Global scheduler

Use one bounded executor for all projects/stages, not daemon workers multiplied
by independent per-stage thread pools. Task priority: interactive dirty queries,
build-ready link/encode work, cold compilation, then maintenance. Weight fairness
by project and age; prevent a large cold build from starving small edits.

Tasks reserve estimated bytes for source/AST/HIR/result/staging. Admission respects
one aggregate budget, currently preserving the 2 GiB hard Windows guard. Keep
headroom for metadata and unexpectedly large procedures. Spill immutable completed
artifacts and evict eligible cold values before admitting more jobs. A single huge
job receives a bounded explicit failure/limit override rather than exhausting memory.

CPU worker count is configurable and can use more cores after measurement.
Concurrency is constrained by memory and ready dependencies, not a fixed pair.
Cold file reads, safe expansion fragments, body parsing/resolution/lowering,
relocation, record encoding, and asset imports overlap. Source effect/order barriers
remain narrow and explicit. Bound out-of-order results by bytes and sequence window.

Salsa 0.28.5 storage clones share query storage with per-handle thread-local state
(the locked source was inspected). Use supported database clones for parallel
reads within one session and return owned artifact refs. Drain/cancel those handles
before mutable input updates. Do not hold a Salsa read borrow/clone for an arbitrary
long-lived documentation client: export a detached immutable artifact snapshot.
Use pure owned jobs where that reduces lock/retention overhead. A detached
snapshot carries immutable root/artifact references and revision-tagged query
tickets. Queries for the current root borrow the session database briefly; queries
for an older root use persisted facts or a bounded historical database reconstructed
from that root. They must not keep the mutable current database locked indefinitely.
Limit historical queries/snapshot leases and report expired unpinned roots explicitly.

Each worktree has a revision actor handling input changes and publication ordering.
A newer revision cancels stale demanded work cooperatively, discards its commit,
and may retain valid content artifacts. Check cancellation in long lexer/lowering/
encoding loops. A cancelled waiter must release job leases and database handles.
Other worktrees continue. Shared work survives while another waiter needs it.

Transport admission is separate from compilation and uses bounded per-client reads
and queues. Requests carry revision/context tokens and operation IDs. Output leases
serialize publishers of the same destination even across processes. No conflicting
patch is allowed merely because requests came from different worktree paths.

## 16. Public tooling API

Expose language results independently of binary output or daemon availability.

~~~rust
trait AnalysisHost {
    fn load(&mut self, project: ProjectSpec) -> Result<ProjectHandle>;
    fn apply(&mut self, edits: InputChangeSet) -> Result<RevisionId>;
    fn snapshot(&self, project: ProjectHandle) -> AnalysisSnapshot;
}
trait AnalysisView {
    fn revision(&self) -> RevisionId;
    fn definitions(&self, scope: Scope, page: Page) -> DefinitionPage;
    fn definition(&self, key: DeclKey) -> QueryResult<DefinitionView>;
    fn resolve_at(&self, position: SourceSpan) -> QueryResult<ResolutionView>;
    fn references(&self, key: SymbolKey, page: Page) -> ReferencePage;
    fn inheritance(&self, key: SymbolKey) -> QueryResult<InheritanceView>;
    fn documentation(&self, key: DeclKey) -> QueryResult<DocumentationView>;
    fn procedure_hir(&self, key: DeclKey) -> QueryResult<HirView>;
    fn diagnostics(&self, scope: Scope, page: Page) -> DiagnosticPage;
    fn changes_since(&self, previous: RevisionId) -> Result<AnalysisDelta>;
}
~~~

Types are owned or snapshot-borrowed views over immutable records; no public Salsa
handles or DMB IDs. Every result carries revision, completeness, source provenance,
and diagnostics. Old results remain valid for their old pinned source revision.
Partial/incomplete projects still provide syntax/declarations and explain missing
resolution; fatal compiler errors prevent publication, not all analysis.

Documentation attachment has explicit rules for comments, reopened types, proc
overrides, macro-generated declarations, and inherited members. Expose both authored
contributions and effective definitions; don't silently merge duplicate comments.

Lint plugins declare a scope and required facts (syntax, resolved body, references,
effects, declaration buckets). Rules have versioned identities and return diagnostics
plus revision-checked source edits. Lint queries depend on the facts read and rule
configuration. A changed body reruns its rules and relevant aggregate checks; an
unrelated docs comment does not rerun semantic lints.

Aggregate tooling uses per-definition summaries and composable indexes. Updating
one reference summary removes/adds its edges to persistent reverse-reference/call
indexes. Paginated exports and per-symbol docs rendering update changed pages plus
affected cross-links, rather than generating one huge project JSON on every edit.
Unknown dynamic calls/effects remain explicit and limit completeness claims.

Offer Rust library APIs and a versioned local wire protocol with pagination,
subscription deltas, cancellation, and capabilities. Commands include check, lint,
docs, references, explain-rebuild, and export-analysis. A tool can stop at syntax/
semantics and never demand opcode selection, linking, assets, or DMB publication.

## 17. End-to-end flows

### Cold build, empty caches

1. Capture project inputs and namespace edges; read source/directive summaries.
2. Expand ordered macro/effect chain; publish safe fragments as ready.
3. Parse declarations and bodies concurrently; construct ordered bucket roots.
4. Resolve signatures/defaults/initializers and parent graph.
5. Resolve/lower demanded procedures continuously; seal bounded artifact packs.
6. Collect literal/helper summaries; freeze link allocation plan.
7. Relocate/encode independent records and stream maps/assets.
8. Validate image/pair, flush records/output, revalidate captured inputs, commit roots.
9. Return output paths, analysis revision, and stage metrics.

Empty caches require reading/parsing/compiling the project. The aim is linear work,
good data locality, high useful parallelism, and bounded memory.

### Restart with caches and one body edit

1. Load the small project manifest, proof, and output lineage.
2. Verify namespace/journal coverage; capture the changed source file.
3. Demand its directive/syntax fragments; reuse unchanged project subtrees.
4. Restore affected member/body dependency witnesses lazily.
5. Reuse equal signature/metadata; resolve/lower the changed semantic body.
6. Update its linked records/layout and persist small delta packs/root.
7. Validate changed closure, revalidate inputs, publish patch or new generation.

No eager 250 MiB heap restore, whole-source expansion replay, all-resource scan, or
all-procedure checkpoint decode is required.

### Warm daemon body edit

Dirty file -> fragment syntax -> changed body query -> equal header/metadata ->
one HIR/code artifact -> link delta -> output delta -> durable root/pair commit.
The unchanged RSC is reused by archive identity. Filesystem/proof events, code
growth, new literals/locals, and durability can add work; count them explicitly.

### Structural, initializer, map, and asset edits

| Edit | Expected semantic recomputation | Potential binary work |
| --- | --- | --- |
| Comment/format only | Changed syntax/docs/origins; equal expanded semantics stop codegen; observed context builtins can change | Debug/source metadata and contextual-value consumers |
| Body only | Changed body and its local dependents | Code/local/literal records |
| Signature/default | Header/default/helper queries and callers using changed facts | Proc/arg/helper and dependent code records |
| Type parent/member | Changed buckets/parent edges and transitive lookup consumers | Class inventories/defaults and affected records |
| Constant | Value query and expressions whose folded values depend on it | Dependent code/default/initializer records |
| Static initializer | That initializer and ordered startup composition | Initializer code/storage metadata |
| Macro | Observing expansion occurrences until state convergence | Actual changed semantic/output closure |
| Include order/removal | Changed contribution/order chains; affected definitions/lookups | Observable order/ID relocation or compaction |
| Asset payload | Asset descriptor and affected DMB/RSC records | Archive replacement and CRC/kind descriptor |
| Resource name/FILE_DIR shadow | Resolutions observing the changed candidates | New resource allocation and actual users |
| DMM dictionary | Dictionary entry and chunks using it | Instance/grid records |
| DMM placement | Changed placement chunks and sequence composition | Grid/instance/map-object records |
| Target/schema | Queries dependent on changed language/ABI/encoding rules | Potential broad codegen/link/encode |

A broad change can cross many rows. The dependency closure governs work. Algorithms
may switch from sparse updates to batch passes when measured cheaper; report the
choice as a bulk pass, not hidden semantic invalidation.

## 18. Algorithms and cost model

Let F be files, S expanded fragments, D declarations, P procedures, R output records,
E semantic edges, U changed nodes, and B bytes physically materialized.

| Stage | Cold algorithm | Incremental update goal |
| --- | --- | --- |
| Source capture | Sequential/bounded concurrent reads and hashing | Read changed files; journal/namespace events and exact fallback |
| Macro environments | Persistent HAMT plus cached definition fingerprints | Changed observations and effects; O(log names) map paths |
| Expansion order/origins | B-tree/rope of immutable fragments | Changed leaves + O(log S) tree paths; actual propagation closure |
| Syntax | Lexer/parser over shared chunks, compact arenas | Changed region until lexical/grammar convergence |
| Declaration lookup | Hash index + ordered bucket streams | Touched bucket contributions; expected lookup O(1), ordered edits O(log D) |
| Inheritance | Linear DFS/SCC validation; memoized lookup | Actual changed parent/bucket consumers; depth-cost uncached lookup |
| Semantic invalidation | Salsa reads/backdating and portable witnesses | Demanded changed closure; validation work is separately counted |
| Body lowering | Typed AST/HIR, interned names, arena traversal | Affected bodies, no caller-body dependency |
| Initializer composition | Ordered fragment sequence | Changed fragment/range; no proc-by-all-initializers scan |
| Relocation | Frozen ledger + per-artifact relocation arrays | Changed IDs through reverse-use index |
| Layout/offsets | Record sequence with length/digest summaries | Changed leaves/tree paths, placement-dependent closure |
| NQCRC | Composable length/CRC summaries | Changed payload/tree paths and bounded GF(2) shift work |
| RSC free slots | Capacity B-tree + ordered live-entry index | O(log slots) best-fit selection + changed entry bytes |
| Persistence | Indexed binary packs and immutable manifests | Changed records, bounded lookup/index pages |
| Tool aggregates | Per-definition summaries + persistent indexes | Changed summary contributions and affected output pages |
| Publication | Streaming checked record plan | Patch bytes or O(B) required materialization |

These are structural complexity goals, not measured guarantees. Macro propagation,
grammar recovery, reflection, schema changes, or namespace proof loss can legitimately
make U large. Hashing changed bytes is linear in those bytes. A complete exported
DMB/RSC cannot be emitted without processing/writing the required output bytes.
Use current optimized SHA-256 initially; benchmark hashing alternatives only if
strong-digest cost remains material after redundant hashing is removed.

## 19. Performance instrumentation and acceptance

Use the existing measurement harness, not ad hoc runtime profiling worlds. Separate:
- Empty-cache build, cold OS cache where feasible, and warm OS cache.
- Compiler stage-version rebuild with partial cache compatibility.
- Restart unchanged; restart with one edit; warm unchanged; warm body edit.
- New local/string, signature, default, initializer, type parent, macro, map, asset.
- One/two/many worktrees with divergent changes; separate compiler processes.
- Patch planning versus encoding, materialization, durability, and publication.

Record wall and CPU time, bytes read/copied/hashed/serialized/written, file opens,
stage cache hits/misses, dirty-enumeration visits, query validations/executions/backdates, affected IDs,
relocation counts, dirty namespace edges, retained/peak private and mapped memory,
queue waits, cancellation, and compaction. Split the current 80.840-second compiler
phase into preparation, typed parse, resolution, cache reads/keying, lowering,
linking, encoding, and cache writes before choosing cold-build optimizations.

Initial engineering targets, to verify on the same frozen project:
- Warm ordinary body edit: first <1 s, then 0.2-0.5 s for the common retained path.
- Fresh-process edit with compatible caches: 0.5-2 s.
- Unchanged: preserve/improve current 32 ms daemon / 152 ms CLI observations.
- Cold: reduce time through measured algorithm/pipeline changes; set an absolute
  target after a true empty-cache baseline, not the 104-second mixed-cache run.
- Concurrent: speed improvements with the aggregate hard limit retained; no new
  assumption that every additional worker can retain a complete compiler world.

Targets exclude DreamDaemon execution and do not guarantee fixed latency for
arbitrary changed file size, output rewrite volume, filesystem, or semantic fanout.

### Correctness and incrementality tests

Each dependency family gets edit/revert/insert/delete/reorder tests with execution
counters. Compare fresh and incremental semantic results; compare bytes under
canonical policy and semantics/observable inventories under development policy.
Test positive/negative lookup, shadowing, duplicate overrides, parent changes,
constant cycles, proc-static order, caller signature dependence, resource shadows,
map defaults, same-size restored-timestamp writes, atomic replacement/junctions,
corrupt packs, cache eviction, crash recovery, and concurrent worktree isolation.
Include line/comment insertion and include rename/reorder with contextual builtins,
simultaneous predecessor-macro/body edits, direct input-field witness changes, and
cached diagnostic/source-fix rebasing to the current source revision.

Query counters prove unaffected proc HIR/lowering executes zero times for body,
asset, and placement edits when contracts permit. Assert bounded dirty-enumeration
visits and memo validations against the changed closure as well, including edited
restarts; zero executions alone cannot detect an all-procedure validation sweep.
Test equal-result dependency-set changes, negative lookup consumers, new/removed
demanded roots, and crash-safe forward/reverse witness consistency.
Backdating tests prove semantic
equivalence cuts off consumers. Durability/recovery tests crash between pack/root
flush, each pair patch phase, generation publication, and HEAD update. Check patch
plans against the full codec and verify changed-reference closures.

Keep focused Rust fixtures small during implementation. Run the full Rust gate
at integration and DM runtime comparison only at the agreed final gate; don't
launch crashing DreamDaemon processes to profile compiler architecture. No new
heavy tests are part of this planning change.

## 20. Implementation stages and review gates

| Stage | Deliverables | Exit gate |
| --- | --- | --- |
| A: Observability and immediate algorithms | Split timing; initializer ranges; retained string/class/proc indexes; one FrontendRevision | Explain current costs; zero duplicate frontend assembly; same existing semantic fixture results |
| B: Identity and shared objects | dm-source keys/anchors; shared bytes/green AST; BuildDelta; persistent order/bucket roots | Body/insert/revert retains unaffected identities; ambiguous duplicates fail conservatively |
| C: Durable project revision | dm-store packs, manifests/proofs, lazy original sources/maps/resource inventory; stage versions | Restart one-edit restores changed closure; corruption/eviction fallback; bounded disk/memory |
| D: Precise semantics and analysis | Stable Salsa roots; member/signature/default/init queries; instrumented witnesses/reverse index; analysis API | Structural edits affect actual consumers; bounded enumeration/validation after restart; docs/lints use same snapshot without backend |
| E: Typed bodies and HIR | Complete typed AST projection; migrate resolution; reference/effect summaries; adapter to current codegen | No redundant body parsing; language fixtures preserved; unaffected codegen counters zero |
| F: Incremental link/checkpoints | dm-link ledger/use indexes; record deltas; small durable root commits | New locals/literals/defaults/resources/maps avoid unrelated lowering and monolithic checkpoint |
| G: Continuous parallel execution | Global executor, byte admission, session actors, single-flight, cancellation; cold two-pass plan | Useful multi-core throughput under memory budget; no pair barriers or cross-worktree contamination |
| H: Indexed patch publication | Layout tree, delta validation capability, string CRC summaries, RSC capacity plans, transaction modes | Full-codec equivalence; interruption recovery; no mutation of immutable/shared files |
| I: Integration and targets | Benchmark matrix, docs/lint examples, canonical export, multi-process/GC gates | Verified timings/results on frozen source; full final tests and appropriate runtime gate |

Some work can overlap: store/packs, typed syntax, semantic buckets/tool facade, and
output planner. Identity and record contracts must be reviewed together first.
Integrate one vertical slice early (body edit from source through durable output),
then extend to signature/default, initializer, type, asset, and map changes.
Don't wait for every new crate or MIR before obtaining a faster functioning path.

Current codegen and byond-dmb remain the behavior/format reference throughout.
Adapters are removed only when their replacements pass focused fixtures. A format
full writer stays available as a checked encode fallback; broad semantic fallback
shrinks as dependency families gain coverage.

## 21. Decisions and evidence to retain

- Existing syntax parsing happens again inside codegen on a lowering miss.
- Current production procedure scheduling has a strict two-job barrier.
- Body emission still compares all procs and reconstructs shared symbol context.
- The 44.1 MB checkpoint and full-image publication are separate incremental gaps.
- RSC CRC identity is different from a stable resource index and a strong cache hash.
- DMB string encoding depends on placement; fixed-span patch eligibility requires
  actual encoded layout proof.
- Absolute minimal invalidation cannot be promised by using Salsa. The enforceable
  contract is complete dependencies, compatible reuse, equality cutoffs, and
  observable tests/explanations for every demanded stage.

### Reference material

- PERFORMANCE.md: measured costs and current proof/cache boundaries.
- FORMAT.md and src/dmb.rs: string position cipher, table widths, resource descriptors.
- FORMAT.md and src/rsc.rs: observed RSC trailing/free capacity and wire CRC.
- crates/dm-compiler/src/frontend.rs, incremental.rs, bootstrap.rs: current fast path.
- crates/dm-output: existing recovery journal and immutable generation publication.
- [Salsa 0.28.5 API](https://docs.rs/salsa/0.28.5/salsa/):
  input/derived identity, field tracking, equality, and lifetimes.
- [Salsa algorithm](https://salsa-rs.github.io/salsa/reference/algorithm.html):
  revision validation and equality cutoffs.
- [Salsa tuning](https://salsa-rs.github.io/salsa/tuning.html):
  memo-value retention and cancellation.
