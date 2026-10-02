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

Immutable disk stages use the coordinator/frontend cache root consistently and remain shared. Successful check summaries are shared; diagnostic summaries are scoped to the current revision. When memory is constrained, lexical frames
and prepared source/expansion frames are dropped first, then encoded startup
snapshots, then whole idle entries in least-recently-used order. A trimmed discovery
component retains small resource proof records and can restore its prepared pack
from the common CAS. Pressure may therefore replace a retained preparation hit
with a disk restoration; six-session retention is conditional on the byte budget.

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
| Current prepared payload startup snapshot | 128 MiB |
| Current graph manifest startup read | 64 MiB |
| Graph pending write batch | 32 MiB |
| Individual persisted header / envelope | 4 MiB / 32 MiB |

Equal canonical skeletons share immutable allocations across worktrees through
`dm-store::SharedArtifacts`. Its weak index retains no payload. The pool divides
the skeleton's conservative serialized-size charge among its live Arc owners.
The graph charge includes decoded artifacts, semantic metadata, encoded startup
payloads and pending writes. Input counts include handles ever allocated in the
session: deletion cannot silently bypass the bounds.

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
and six-worktree timings remain to be measured.
