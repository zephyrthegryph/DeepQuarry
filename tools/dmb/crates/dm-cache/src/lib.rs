//! Immutable compiler cache. Stage-specific payloads require caller bytecheck;
//! no semantic meaning or cross-segment pointers are trusted by this crate.
mod segment;
mod store;
pub use segment::{CacheError, Limits, Record, RecordKey, RecordView, Segment, SymbolText};
pub use store::{Cache, CacheSnapshot, CompactResult, RejectedSegment};

#[cfg(test)]
mod tests;

mod variants;
pub use variants::{encode_variants,decode_variants};
