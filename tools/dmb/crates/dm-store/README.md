# Compiler persistence

`dm-store` provides one namespace/key interface for compiler facts, metadata,
immutable blobs and negative read dependencies. Batch a complete compiler stage
with `read_many`; do CPU work after it returns; publish related records with one
`commit`. A witness records both present values and missing keys. Changed values,
deletions and newly created keys reject the entire commit without partial writes.

redb does not provide this crate's independent-process sharing. An OS file lock
serializes database ownership. Each batch opens the database under that lock and
closes it before releasing the lock. Six processes can use the same store safely;
their database operations serialize. Compilation and analysis run outside it.
No persistent process owns the database or brokers other clients.

The default redb cache is 16 MiB; `with_limits` allows 1–64 MiB. Acquisition has a
30-second default timeout and accepts an `AtomicBool` cancellation flag. Read/write batches are capped at 64,000 records and 128 MiB.
Namespace snapshots report incomplete coverage explicitly when either cap is hit. Schema checks use read transactions; initialization
alone writes the schema. Commits retain redb's durable defaults. A killed process
releases the OS lock, and the next database open uses redb's recovery mechanism.

All record payloads carry an internal SHA-256 envelope. Encoding and read
verification happen outside database ownership. The schema rejects older or
unknown envelope formats instead of guessing.

Keys in `blob-v1` must equal the SHA-256 of their bytes. `read_blobs` checks that
identity again. Other namespaces remain opaque to the store. All processes must
use this API and the same database path; bypassing its lock is unsupported.

Focused tests cover schema incompatibility, immutable blob identity, negative
dependencies, atomic conflict rejection, restart, timeout and cancellation. The
Windows six-process test executes 48 read/commit batches containing 3,072 writes;
its initial debug run took 5.49 seconds. This is correctness and bounded-contention
evidence, not a compiler performance claim.
