//! Reusable resident artifacts, without daemon activation or disk authority.
//! Exact keys and issuer-domain answers authorize reuse; hashes only select buckets.
mod artifacts;
mod reads;
mod publication;
pub use publication::{ArtifactAttempt, ArtifactGeneration, ArtifactPublication};
pub use artifacts::{
    AcceptedArtifact, ArtifactStorageView, ArtifactStore, ObservedArtifact, ObservedArtifactLease,
    ObservedArtifactStorageView, ObservedArtifactStore, DEFAULT_RESIDENT_BYTES,
};
pub use reads::{matching_domains, RecordingResolver, ResolverRead};

pub mod observations;
pub use observations::{
    Observation, ObservationHost, ObservationLedger, Receipt, ReceiptAdmission, ReceiptGroupPool,
    ReceiptStorageView,
    DependencyCoverage, InputDelta,
    CertificateDelta, CertificateState,
};
