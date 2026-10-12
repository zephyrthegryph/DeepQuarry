# Shared input closure integration audit

Source-only audit, 12 October 2026. No compiler, runtime or benchmark was run for
this audit. This documents an open integration gate, not a completed migration.

## Existing producers and consumers

- `src/frozen_inputs.rs`: `Inputs::Recording` records verified bytes, negative
  path probes and exact folder memberships through the same `SnapshotProvider`
  used by compilation. `JournalAccessView` borrows that roster and verifies one
  payload at a time. `Inputs::Replay` rejects uncaptured requests and never reads
  live files. These are native observations, not DreamMaker access completeness.
- `src/frozen_inputs/physical_paths.rs`: held Windows handles produce capture-time
  no-reparse ancestor identities. `physical_root_identity` checks their recorded
  containment without probing the replay filesystem. Old journals can lack these
  proofs and must decline physical admission.
- `src/resource_journal_coverage.rs`: the existing resource capture producer checks
  the recorded demand, physical paths, search-folder facts and encoding receipts.
  Its receipt explicitly sets `shared_input_closure_complete=false`.
- `src/publication_proof.rs` exports native publication and optional resource
  evidence. Build integration now retains that evidence rather than dropping it;
  transport validation does not create new producer authority.
- `src/daemon/query/` already exposes bounded source occurrence, body-context and
  resolved semantic pages from the retained model. Tooling has an existing model
  consumer; it does not need another physical-tree materializer for these queries.
- Benchmark source-snapshot and input-closure records authenticate captured
  benchmark inputs and revisions. Their harness checks are not a production
  compiler-issued shared-closure protocol.

## Why the recorded native tree cannot be substituted for a shared closure

Folder observations can name files whose bytes were never read. Copying only
recorded payloads changes directory membership; adding placeholders invents
content. The journal also cannot prove that DreamMaker will not request a
BYOND-specific input or search location. DreamMaker currently cannot consume the
native replay provider, so native rejection of uncaptured reads does not constrain
the reference compiler. A file roster or matching output hash does not fix this.

The uncommitted `closed_snapshot.rs` is untouched. It is explicitly unhooked and
restricted to 256 files / 32 MiB, literal dependencies and no nested include
resolution. It is not the DeepQuarry closure producer.

## Required producer contract before shared parity admission

1. A single current core producer owns captured bytes, exact folder memberships,
   negative probes and physical namespace facts. It binds the relative manifest,
   ordered defines, compiler identities, target profile and resource search roots.
2. Both compiler consumers execute against the same owned captured namespace.
   The producer must establish supported namespace/search restrictions using the
   existing frontend, or enforce and record all reference reads. An observed
   native roster alone cannot establish this contract.
3. Namespace materialization preserves all admitted membership and byte facts,
   rejects outside-root paths and collisions, and copies bytes without mutable
   worktree hardlinks. Unsupported configurations decline before either output
   can be accepted as shared parity.
4. The existing target receipt currently says
   `implicit_predefines_complete=false`. Its complete engine/predefined-macro
   profile must be issued and matched to prepared DreamMaker configuration.
5. The result binds both actual output generations to that capture and profile;
   the integration consumer validates scope and current invocation rather than
   accepting a caller assertion or arbitrary JSON cast.

No unused partial materializer, second DM dependency parser, new cache, or new
claim of shared authority was added. Shadow admission remains fail-closed until
the producer and both consumers satisfy this contract.
