//! The daemon-wide store of immutable values (lane `compiler/shared-store`).
//!
//! Sharing used to exist only on disk (the content-addressed dm-cache): every retained session, one per project root and
//! variant, decoded and owned a private copy of every record it read. This is the in-memory half. One `SharedStore` lives in
//! the daemon (`Shared`) and every `BuildHost` borrows it, so identical values (the same file in two worktrees, the game and
//! the test variant of one tree) are decoded and held once. A session owns only its inputs and its dirty query state.
//!
//! Rules every value kept here follows:
//! * Immutable and content-defined: equal content, one allocation. Nothing here is a session's answer about its own tree.
//! * Authority stays with the consumer: a shared candidate is validated against the asking session's own inputs exactly as a
//!   candidate read from the disk cache is, so sharing can change memory, never output.
//! * One global budget per owner, refcounted by handles; a session releasing its state clears an owner only when it is the
//!   last holder.
use crate::runner_host::SharedRecords;
use std::sync::Arc;

#[derive(Default)]
pub(crate) struct SharedStore {
    /// Decoded preprocessor memo records (expansion, directive plan, fragment).
    pub(crate) records: Arc<SharedRecords>,
}
