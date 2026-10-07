# Phase 1 map, resource and output integration

Status: read-only extraction plan, 6 October 2026. This document does not claim a
complete cold compiler, a measured speedup, or resolved DreamMaker order parity.
The frozen reference compiler remains unchanged. The current source now delegates its three scalar map syntax helpers to the extracted implementation; map emission/lowering remains legacy. Profiling with samply/xperf/Procmon is
**deferred at the user's request**; existing built-in stage tracing and independently
recorded command wall time remain the timing evidence path. No profiler job is
needed to implement these boundaries.

## Existing entry points and their actual limits

| Component | Reusable implementation | Required extraction/change |
|---|---|---|
| Frontend | `dm-tree/src/frontend.rs`: `build(project, provider, defines, workers)`, `ColdFrontend.body`, `maps`, `skins`, occurrence/source locations and explicit `emission_order` | Consume its captured directive ledger. Its resource resolver support is explicitly absent (`SemanticTree::supports(Resource)` is false); the captured `dm-resources::native_resolver::NativeResourceResolver` can now compose tree queries with explicit qualified resource outcomes; discovery and driver wiring remain pending. |
| Maps | `dm-compiler/src/maps.rs:397` `map_blocks`, `:448` `map_templates`, `:509` `split_top_level` | `dm-syntax::map` now owns these helpers plus `parse_map`: one lexical pass, ordered symbolic template/block sections and joint occurrence records, borrowed text and exact key/payload/cell spans. Legacy compiler signatures/error wording remain delegates. Semantic map resolution is still pending. |
| Map resolution/encoding | `maps.rs:147` `emit_maps_inner`, `:545` `lower_complex_map_initializer`, `:664` `map_instance_kind` | Replace scanning `Dmb` class/resource/mob tables and appending initializer procs/lists with tree resolver queries and symbolic outputs. |
| Resource payloads | `dm-resources/src/lib.rs`: `ResourceRequest`, `ResourceSet::load`, `rsc_bytes`; existing archive-name safety and `NamedResource::from_data` NQCRC | Move source/skin resource request discovery out of bootstrap. Preserve alias/phase order, source search domain and first-content-kind behavior. |
| Resource discovery | `dm-compiler/src/bootstrap.rs:788` `resource_requests_with_optional_literals`, `:1015` `resolve_resource_path`, `:1033` `skin_archive_name` | Accept ordered frontend/lowering/map references and a captured resource namespace. Do not rescan directives or use verified-cache hints in the no-cache path. |
| DMB encoding | `byond-dmb/src/dmb.rs:1883` `Dmb::to_bytes` | Feed a fully linked image with freshly assigned dense IDs; retain checked format limits and string obfuscation. No addressed payloads or receipt layer required. |
| Pair publication | `dm-output/src/generation.rs:139` `publish_generation`, `:273` verification, existing temporary directory/rename and HEAD lock | Reuse validation/write primitives, but implement the actual per-drive PairStore acquisition/eviction/manifest contract below. Current Generation is not that complete contract. |

Avoid `maps::load_map_set`: it rescans literal `#include` lines recursively and
cannot determine active conditional includes. Use the frontend's active non-text
ledger. `load_map_set_from_paths` can temporarily provide ordered reads, but its
canonical disk-path deduplication is a baseline behavior, not proof that repeated
include occurrences are universally disposable. Never replace the occurrence
ledger with a set without the applicable order contract.

## Proposed cold-driver sequence

1. Capture one provider/snapshot and defines; call `dm_tree::frontend::build`.
   Keep semantic tree, occurrence table and source provenance alive through all
   diagnostics. Capture active maps, skins and FILE_DIR domain from that plan.
2. Resolve declarations/constants/settings and produce explicit observable link
   order. Lower bodies/initializers to `SymbolicCode` through `dm_ir::Resolver`;
   worker results occupy preassigned occurrence slots, not completion order.
3. Parse each active map into symbolic templates/blocks, resolve all operands
   through the same resolver, and retain ordered object lists. Load selected skin
   source and discover its dependent resources. Collect code/initializer/map/
   script/skin resource uses, including source-required dead tokens where the
   established archive contract requires them.
4. Produce one ordered resource plan, load each distinct physical input once,
   retain distinct authored aliases, and construct NQCRC/content-kind bindings.
   Do not intern a resource solely by its SHA before first-kind/alias policy is
   applied. SHA identity and runtime NQCRC identity serve different purposes.
5. Assign dense format IDs once in `dm-link`, relocate symbolic operands, emit
   class/proc metadata and reference tables, global/static initialization,
   map initializer procedures, grid/object records and header fields.
6. Encode complete DMB and RSC, validate the pair, then publish/acquire it through
   PairStore. Never expose a successful CLI result for a half-published pair.

There is no call to the old `bootstrap::compile_project`, CanonicalSession,
receipt/graph/cache APIs, or daemon in this intended driver. A transitional test
adapter may reuse pure parser/codec helpers; it must be explicitly identified and
cannot establish completion of Phase 1 while it drives legacy semantic lowering.

## Concrete API seams (proposed, not implemented here)

The type names below describe boundary ownership, not newly usable APIs.

```rust
// Map syntax owns captured bytes/spans; ordering is explicit.
fn parse_map(input: CapturedMap) -> Result<MapSyntax, Vec<Diagnostic>>;
fn resolve_map<R: Resolver>(
    syntax: &MapSyntax, resolver: &R, origin: &OccurrenceTable,
) -> Result<SymbolicMap, Vec<Diagnostic>>;

// Input search and ordered output naming are separate from physical payload IO.
fn plan_resources(
    uses: &[OrderedResourceUse], namespace: &CapturedResourceNamespace,
) -> Result<ResourcePlan, Vec<Diagnostic>>;
fn load_resources(plan: &ResourcePlan) -> io::Result<ResourceSet>;

fn link(
    tree: &SemanticTree, occurrences: &OccurrenceTable,
    code: &[SymbolicCode], maps: &[SymbolicMap], resources: &ResourcePlan,
    order: &LinkOrder, builtins: &BuiltinImage,
) -> Result<LinkedImage, Vec<Diagnostic>>;
fn encode(image: LinkedImage, resources: ResourceSet)
    -> Result<EncodedPair, Vec<Diagnostic>>;

impl PairStore {
    fn publish(&self, pair: &EncodedPair) -> io::Result<PairId>;
    fn acquire(&self, id: PairId, destination: &Path) -> io::Result<AcquiredPair>;
    fn materialize_conventional(&self, id: PairId, project: &Path) -> io::Result<()>;
}
```

`SymbolicMap` contains symbol/type references, ordered template declarations,
ordered assignments, cell coordinates, and ordered object instances; no global
DMB IDs. Map initializer code uses the same symbolic relocation contract as a
body. `OrderedResourceUse` includes authored alias, origin, phase and stable
within-phase ordinal; `ResourcePlan` separates aliases from loaded payloads and
provides resource bindings to the linker. It must preserve whether a literal is
an active selected source occurrence and the exact FILE_DIR/resource search
policy. Resource failures retain occurrence diagnostics rather than becoming
silent missing symbols.

The resource resolver must implement actual `ResolveQuery::Resource` semantics;
returning Unknown for every resource is not a usable cold driver. If maps need
class/mob category, typed field/default or constructor information beyond the
current Resolver trait, add explicit queries there instead of depending on
`dm-tree` internals from `dm-lower`. Symbol hash collision checks and full canonical
symbol spelling remain mandatory. Dense class/member IDs stay linker-local.

## Observable order dependencies

- Type creation and reflection, fields/vars, inherited verbs and proc override
  chains are separate orders; the semantic tree's lookup HashMaps cannot select
  their dense layout. Explicit `emission_order` is a projection, not semantic
  override priority.
- Global/static/local-static initialization and map/world startup have observed
  effects. `LINK.md` records preserved divergences and pending map probes; no
  alphabetical or source-only shortcut is certified yet.
- Current map emission appends files by manifest order with z offsets, reads
  block rows from top to bottom but computes descending y, emits final cells in
  z/y/x order, and preserves object order inside a cell. These are baseline code
  facts to verify against the pending map startup fixture, not universal rules.
  The current variable-length dictionary key search uses HashMap iteration;
  extraction must validate a single key width (or explicitly reject ambiguous
  prefixes), never carry nondeterministic `.keys().find()` into the new parser.
- Resource aliases and first kind for equal content are observable. Existing
  Phase 0 resources fixture records a preserved alias divergence. Maintain exact
  paired receipts; do not call content equality alias parity.
- Internal first-use IDs follow the proposed canonical policy in `LINK.md` only
  for tables certified unobservable. Mutable list instances must remain distinct.
- Preserve native reserved/sentinel IDs and field widths. Map instance limit,
  dimensions, grid-run/object-gap encodings and relocation overflow must report
  errors; no truncating casts or invented IDs.

## Immutable publisher: actual implementation and remaining contract

The frozen legacy `dm-output::generation` remains a SHA256/HEAD-based primitive.
Current Phase 1 `dmbc/src/publish.rs` now implements `PairStore::open`,
`publish(session, dmb, rsc)`, `publish_with_resource`, `acquire(id, slots)` and
`install(id, dmb, rsc, marker)`. It uses framed xxh3 content identity, a shared OS
store lock, temporary directories, immutable stored files, shared archive
content and session-last-three registration during publication. Acquisition
hashes/authenticates every time for now and materializes writable run-slot copies:
the Phase 0 engine probe rejected read-only hardlinks. This is a deliberate
runtime compatibility requirement, not a claimed hardlink speedup. Drive/store
selection remains explicit at the caller; no drive-root permissions are assumed.

Remaining verification includes complete BYOND pair validation in the new cold
driver, store-volume policy and crash/race/error-path gates, required durability
on the deployment filesystem, retention/eviction integration, conventional
marker repair and actual cold-driver wiring. Boot/stamp memoization is deferred;
current full verification is conservative. Do not substitute an old timestamp
receipt for a boot guarantee. The old in-place PairPlan patch/undo route is not
part of this intended driver.

`NativeResourceResolver::from_captured` now validates captured resource aliases,
declared payload/SHA/NQCRC/content-hash consistency, symbol collisions, exact
registered search-context identity and explicit lookup consistency. It forwards
tree queries, returns Missing only for recorded complete negatives, and returns
Unsupported for unknown or unqualified resource searches. Ordered aliases and
payloads remain available to linking. It performs no filesystem reads in resolve.
The discovery stage must still provide complete search-domain serialization and
ordered lookup outcomes; no FILE_DIR policy was inferred in this host.

## True remaining work and evidence gates

1. Map syntax/provenance extraction is present; finish its symbolic resolver boundary and support complex
   map assignments through real lowering, not the old simple-code shortcut.
2. Complete resource query semantics, active script/skin handling, search domain
   and ordered archive plan; preserve raw asset bytes (no newline normalization).
3. Finish metadata/default/initialization/body lowering and canonical linker ID
   assignment. The current frontend/tree foundation alone is not a full compiler.
4. Finish PairStore validation/lifecycle integration above and `--no-daemon` CLI wiring without
   deleting the preserved baseline before it supplies comparison evidence.
5. Capture new order probes, complete decoded metadata and pair crash/race tests;
   compare frozen baseline and DreamMaker separately. Preserve known divergences.
6. Validate deterministic bytes across worker counts/scheduling, diagnostics and
   source transitions, then measure cold stages and memory using allowed built-in
   traces. No performance target is claimed from this document.

No source/cache deletion, compiler build, test, benchmark, DreamDaemon or profiler
job was run for this slice. Focused map tests are authored but unexecuted. This is a concrete integration plan, not an exit-gate
receipt.
