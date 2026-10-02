# Canonical incremental compiler: accepted architecture

This supersedes the output, persistence and rollout policies in ARCHITECTURE.md.
That document retains useful long-term syntax and semantic API designs; its
lineage allocator, in-place publication and custom pack/lease/GC design are deferred.

## Correctness gates come first

The reference is the same source snapshot, configuration and BYOND version.
Fewer failing game tests do not establish better compiler behavior. Gates record:

1. Test outcomes and per-test runtime identities, including failures in passing tests.
2. Procedure instruction differences with table references resolved to semantic names.
3. Actual commit replay: canonical incremental DMB **and** RSC bytes equal an
   independently compiled revision with isolated caches.
4. Accepted/rejected source and diagnostic differences against DreamMaker.
5. Identical bytes across repeat, restart and independent compiler processes.

An incomplete runtime capture cannot pass attribution parity. The frozen translated
run has millions of unlocated list errors; that does not establish the absence of
the native run's power_bridge error. Numeric-list operand parity has an offline
fixture. Source attribution and a matched runtime replay are separate requirements.

## Data and crate boundaries

| Crate | Responsibility |
| --- | --- |
| dm-syntax | Source spans, lexical and structural syntax, recovering diagnostics |
| dm-preprocess | Include and macro expansion, source origins, filesystem dependencies |
| dm-semantics | Canonical declaration paths, signatures, inheritance and resolution facts |
| dm-compiler | Salsa inputs/queries, structural front end and frozen lowering contexts |
| dm-codegen-byond | Symbolic instructions and the single binding-read recorder |
| dm-resources | Asset identity, payload loading and compact resource catalogs |
| dm-store | Bounded transactional records, checksums, conflict witnesses and batch access |
| dm-output | Pair validation, immutable generations and conventional-path installation |
| dm-analysis | Versioned JSON-lines facts with explicit coverage |
| dm-compiled | Persistent worktree sessions, discovery and build coordination |
| dm-compile | CLI, native/BYOND/shadow integration and analysis export |

Syntax and semantic structures remain usable without a running daemon. Salsa IDs,
absolute worktree paths and edit lineage are excluded from symbolic output identity.
Declaration occurrence and include order remain observable and must be preserved.

## Build flow

1. Validate configuration, target schema and source snapshot.
2. Update includes, preprocessing and content-addressed syntax chunks.
3. Derive the declaration skeleton before lowering bodies. Freeze the resolved
   context for each lowering job; workers cannot mutate tables.
4. Look up a symbolic memo by semantic body and invocation frame. Replay its
   recorded positive and negative binding facts against the current skeleton.
5. Reuse a matching memo, or lower while recording facts. The same fact witnesses
   become Salsa reads and portable cache dependencies. No second dependency walk
   approximates what lowering read.
6. Link in a fixed source order. A bounded worker window overlaps lowering without
   making table allocation depend on scheduling or worker count.
7. Materialize canonical DMB bytes. Assembly and encoding are measured separately;
   semantic cache hits do not hide the cost of building the complete binary.
8. Reuse the verified immutable archive when asset identity is unchanged. Compact
   catalogs carry resource IDs/names/content identities without asset payloads.
9. Validate freshness immediately before publishing a new generation. Install
   detached conventional DMB/RSC paths through a recovery journal.

Canonical assembly is the default. Explicit legacy patch experiments are excluded
from the integrated test path. Asset changes rebuild the canonical archive; append
layout depending on edit history cannot satisfy fresh-build byte equality.

## Persistence and concurrency

Git worktrees share the cache beneath the Git common directory; standalone
projects use `.dm-cache`. `DM_COMPILER_CACHE_ROOT` overrides **all** native cache
stages for isolated reference builds. Cache corruption or absence permits recompute.

Transactional metadata uses redb. Large DMB/RSC payloads remain immutable files,
addressed by SHA-256. Database access is batched at stage boundaries; a lowering
workers consume bounded requested-key cache views and keep bounded local overlays
and Salsa graphs. Bulk requested reads share one short database ownership window;
locks are released before decoding and compiler work. A missing or evicted record
is a cache miss, never evidence for a cache hit. Symbolic lowering no longer scans
its entire namespace. Source fallback can still make an addressed read after parsing;
procedure graph and output-fragment hits bypass it.

Separate compiler processes coordinate short database operations through an OS
lock. Pure artifact publication uses read witnesses and a conditional transaction;
conflicting bytes for the same dependency key are an error. Worktree source and
output publication stay independent. Six-worktree acceptance exercises requests,
edits, restart and fresh comparison under a sampled aggregate memory budget.

## Tooling and integration

`DQ_COMPILER=byond|native|shadow` selects the pipeline. Shadow keeps BYOND as the
producing compiler, records native differences and compares cached native bytes
against a separate fresh native process. A fallback names its reason and producing
compiler; it never counts as a passing native gate. Strict runs forbid fallback.
Only explicitly classified infrastructure failures permit automatic fallback.
Unclassified errors, unsupported semantics and source errors remain visible failures.

The JSON-lines export includes schema/input identity, declaration occurrences,
authored signatures, inheritance, source origins and diagnostics. Resolved references
require a verified producer and otherwise advertise unavailable coverage. Consumers
must inspect coverage instead of treating absent records as proof of no references.

Native target support starts with the verified 516.1687 schema. New BYOND builds
require schema/header/opcode fixtures and correctness gates before acceptance.

## Performance decisions

The structural-edit target is three seconds with the daemon on the real project.
It is an acceptance target, not a current measurement. Report new proc, new var,
changed default, body edit, unchanged run, restart and cold build independently,
alongside DreamMaker timings and memory. Full cached assembly measurement decides
whether incremental linking is justified. Macro history and lexical fanout are
measured before adding a complex propagation engine.
