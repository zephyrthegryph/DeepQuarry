# Shared semantic artifact ownership

This crate owns the generic resident artifact store and the resolver-read recorder.
The compiler's procedure memo uses this core; other semantic consumers should use
the same recorder rather than maintain a second dependency ledger.

## Reuse contract

`ArtifactStore<T>` stores immutable `Arc<T>` values with exact key bytes, recorded
resolver answers, and optional dependency-domain version receipts. The key hash
selects a bucket only. A lookup compares the exact key and, for each domain without
a matching receipt, checks every recorded answer against the current resolver.
Negative answers are dependencies too. A matching version is authoritative only
when the resolver issues it for the complete dependency domain.

`RecordingResolver` records positive and negative answers through the existing
`dm_ir::Resolver` interface. Callers must record mandatory occurrence dependencies
with `record_occurrence` even when a body contains no inherited-name lookup.

## Lifetime and budgets

Readers hold their own `Arc`. Evicting a store entry cannot invalidate a reader;
the last owner releases the result. Admission evicts resident entries before
constructing a replacement. Oversized entries are rejected without invoking the
construction closure. Up to four insertion-ordered variants of an exact key can
coexist; a different exact key in the same hash bucket cannot authorize reuse.

The supplied weight is a caller-issued accounting value, not an allocator memory
measurement. Callers must include owned payload and dependency storage in their
weight. Values still held by readers can outlive resident eviction, so the store's
admitted-byte count is not a process-wide memory cap.

## Current scope

The compiler keeps procedure-specific disk encoding, policy identity, diagnostics,
and source rebasing in its procedure memo. This crate neither publishes files nor
starts a daemon. Extracting this owner does not itself retain a frontend revision
between requests or provide incremental linking. Those remain later migration
work under `tools/dmb/DESIGN.md`.
