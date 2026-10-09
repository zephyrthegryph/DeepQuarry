//! Reusable resident artifacts, without daemon activation or disk authority.
//! Exact keys and issuer-domain answers authorize reuse; hashes only select buckets.
mod artifacts;
mod reads;
pub use artifacts::{ArtifactStore, DEFAULT_RESIDENT_BYTES};
pub use reads::{matching_domains, RecordingResolver, ResolverRead};
