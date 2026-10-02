# Incremental compiler pipeline

The default native compiler builds a canonical DMB and publishes an immutable
DMB/RSC generation. Procedure caches retain semantic results and relocatable
code, rather than depending on a previously linked world's table IDs. The older
history-based incremental image path remains a compatibility path; it does not
define canonical output identity.

## Components and data

| Component | Responsibility |
|---|---|
| `dm-preprocess`, `dm-syntax` | Expanded source, source origins, structural items and procedure bodies. `Item`, `ItemKind` and `Span` have persistent DTO codecs. |
| `dm-semantics`, `dm-ir` | Declaration and semantic data independent of output table allocation. |
| `dm-compiler::frontend` | Bounded content-addressed outline/declaration chunks and resource literal inventory. |
| `dm-compiler::project_graph` | `ProcKey` (path plus override occurrence), body/frame `ProcDescriptor`, tracked semantic witnesses and reusable `ProcedureArtifact` results. |
| `dm-compiler::maps::MapInitializerSession` | Separate persistent graph for exact map assignment sources and derived field overlays, with current-ID relocation. |
| `dm-codegen-byond` | Native lowering, shared `OwnerLowerBindings`, prepared procedure sections and current-source debug relocation. |
| `dm-work` | One generic bounded scheduler used by procedure, map and input/resource preparation adapters. |
| `dm-store` | Transactional redb records, checksummed payloads, namespace snapshots and batched writes. Independent processes use short serialized database access. |
| `dm-resources`, `dm-output` | Resource catalog/archive reuse, reference validation, encoding and durable generation publication. |
| `dm-compiled`, `dm-host` | Retained sessions, filesystem proofs, disk receipts, daemon worktree routing and process limits. |
| `dm-analysis` | JSONL export of available compiler facts and explicit coverage information. |

## Stages

1. Establish a consistent source/resource input proof. Expand dirty inputs and
   reuse verified preprocessing and frontend chunks.
2. Prepare or restore the frozen declaration skeleton. Procedure identity is
   independent of source offsets and final table IDs. Owner field/type frames
   are shared through `Arc`; local statics hide owner fields without copying
   the inherited inventory.
3. Update procedure descriptors and replay observed semantic facts, including
   failed name resolutions. Reuse valid graph results. Authored misses send raw
   procedure slices to persistent workers that parse, rewrite modified types,
   extract settings/statics and lower the body together. Workers return the
   current body anchor and retain local caches across job windows. Their parser
   snapshot is shared and initializes only when a source job needs it.
4. Reserve and mutate output tables in deterministic source order. A
   `PreparedProc` already has resolved local branches and typed relocations.
   Materialization copies flat words and applies current table IDs. Debug file
   and line instructions are inserted from current origins, with branch targets
   shifted to enter those instructions.
5. Validate and encode the canonical world, reuse the verified resource archive
   when applicable, and durably publish the output pair. Binary patch requests
   retain their explicit ownership/exclusive-output policy.

`PreparedProcedureEnvelope` stores flat code plus ordered string/resource/local
and formal metadata, body-relative statement anchors and the relative body
base, plus typed reference-origin sidecars for cached diagnostics. It does not
store a symbolic instruction tree or absolute debug filename
bindings. Its versioned codec is separate from the validated DMB wire format.
The frozen skeleton uses a persistent model DTO; it is not an unchecked DMB
writer and may contain unresolved values until final linking.

## Scheduling and budgets

`WorkLimits::configured()` reads `DM_COMPILER_WORKERS`, then `DM_WORKERS`:
default two workers, bounded to one through four. `DM_WORK_ACTIVE_MIB` defaults
to 64 MiB and is bounded to 16–256 MiB. This budget charges estimated queued
and running inputs. Completed results are separately bounded by each stage's
window; it is not a claim that all retained results fit the active-input budget.
Procedure lowering uses a four-job window. Ordered reception preserves typed
panic payloads as infrastructure failures. Map reads and template/grid parsing
are independent; map table allocation remains ordered. Oversized maps fall back
to serial preparation rather than becoming new source errors.

Map assignment helpers use a separate graph instance in the canonical session,
scoped to the worktree and configuration. It derives current field bindings from
exact assignment text and refreshes persisted semantic witnesses before probing.
Independent misses prepare flat sections through the same executor; output IDs
are relocated during ordered map emission. Map string/resource lookups are
indexed once per emission. Template/grid spans are retained by exact map content
digest, capped at 16 MiB and 512 entries, so unchanged maps skip structural
parsing. They also persist as current-content records in `dm-store`/redb, without
a historical namespace snapshot. `DMMAP001`, the emission fingerprint, record
checksums and exact-source/span validation guard cold restoration. Bounded reads
check the 512 KiB record and approximately 8 MiB batch allocation caps before
allocation. Cold misses, corruption and incompatible records parse normally;
writes remain optional and batched. Grid decoding uses exact indexed keys over distinct byte widths;
fixed-width maps take one lookup, while mixed widths choose the longest match
deterministically. Stage-specific graphs do not introduce additional
worker engines or independent cache-pack formats.

Caches have separate bounded retention. The standalone prepared-link helper has
a 128 MiB disk snapshot, 64 MiB decoded-section cap and 32 MiB pending writes.
Production procedure and map graphs use the graph limits documented in
`INCREMENTAL_CORE.md`; their charges include each distinct graph instance.
Symbolic/parser caches also enforce their own caps. Process-level memory limits
remain necessary because these stage
budgets are not a single aggregate memory allowance. Database locks are not held
during parsing, lowering or relocation. Namespace snapshots avoid a database
open per procedure; writes flush in batches. Stage fingerprints cover source,
codec and dependency changes, including `dm-work`.

Disk records and receipts live under the project's configured compiler cache
root, so non-daemon builds and restarted daemons can restore state. Multiple
worktrees can share content-addressed records while retaining distinct input
proofs and output contexts. The frontend pool retains discovery caches together
with outlines and canonical graphs for each session, rather than retaining only
the latest worktree's discovery state. Its default limit is six sessions and
512 MiB aggregate retained charge. Graph and lowering records use the same
coordinator/frontend cache root. Successful check summaries remain shareable;
diagnostic summaries are revision scoped.

The default cache lives under Git's common directory at `dm-compiled-cache`, so
worktrees and separate CLI processes share durable content. Standalone projects
use `.dm-cache` beside the DME. `DM_COMPILER_CACHE_ROOT` overrides that location.
Equal declaration skeletons also share an in-process immutable allocation through
a weak artifact index; it does not pin data after the owning sessions evict it.
Portable symbolic and parser startup snapshots initialize only when a miss needs
them. Prepared graph hits bypass both startup snapshots and the old worker-local
Salsa engine; the project graph owns production semantic invalidation.

## Prototype limits

Frontend reuse still has coarse unit/chunk boundaries. Structural edits can
refresh the skeleton and replay all previously known semantic facts; this is
not yet a guarantee that Salsa evaluates only the smallest possible dependency
set. Some input-pack/output publication work still operates on whole packs.
JSONL resolved-reference coverage remains explicitly unavailable where the
compiler has no complete resolved-reference index.

The integrated pipeline at `505f1f8e98` has real DeepQuarry measurements in
`INCREMENTAL_CORE.md`: unchanged receipts take about 0.21--0.23 seconds, but body
and structural edits still take 81--93 seconds despite procedure reuse. The
default 2 GiB process cap failed on the first empty-cache build; a bounded 3 GiB
retry with partially warm syntax succeeded. The bulk-refill follow-up measured
0.317 seconds unchanged, 116.099 seconds for a body edit and 131.661 seconds for
a new procedure under an explicit 3 GiB cap. The restore regression is fixed,
but these measurements do not establish an overall iteration improvement.
Six full-sized concurrent worktrees remain unmeasured. Use the supported
`dm-compile` `iteration_bench` example for production Coordinator measurements.
