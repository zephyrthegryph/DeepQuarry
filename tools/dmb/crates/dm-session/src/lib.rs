//! Reusable resident artifacts, without daemon activation or disk authority.
//! Exact keys and issuer-domain answers authorize reuse; hashes only select buckets.
mod artifacts;
mod publication;
mod reads;
pub use artifacts::{
    AcceptedArtifact, ArtifactStorageView, ArtifactStore, ObservedArtifact, ObservedArtifactLease,
    ObservedArtifactStorageView, ObservedArtifactStore, UnchangedCandidate, DEFAULT_RESIDENT_BYTES,
};
pub use publication::{ArtifactAttempt, ArtifactGeneration, ArtifactPublication};
pub use reads::{matching_domains, RecordingResolver, ResolverRead};

pub mod observations;
pub use observations::{
    CertificateDelta, CertificateState, DependencyCoverage, InputDelta, Observation,
    ObservationHost, ObservationLedger, Receipt, ReceiptAdmission, ReceiptGroupPool,
    ReceiptStorageView,
};
