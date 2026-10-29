//! Reusable resident artifacts, without daemon activation or disk authority.
//! Exact keys and issuer-domain answers authorize reuse; hashes only select buckets.
mod artifacts;
mod publication;
mod reads;
pub use artifacts::{
    AcceptedArtifact, ArtifactStorageAccounting, ArtifactStorageCoverage,
    ArtifactStorageExclusion, ArtifactStorageView, ArtifactStore, ObservedArtifact,
    ObservedArtifactLease, ObservedArtifactStorageView, ObservedArtifactStore, PressureAllocation,
    PressurePrune, UnchangedCandidate, UnchangedCandidates, DEFAULT_RESIDENT_BYTES,
};
pub use publication::{
    release_replaced_in_background, ArtifactAttempt, ArtifactGeneration, ArtifactPublication,
};
pub use reads::{RecordingResolver, ResolverRead};

pub mod observations;
pub use observations::{
    DependencyCoverage, InputDelta, Observation,
    ObservationHost, ObservationLedger, Receipt, ReceiptAdmission, ReceiptGroupPool,
    ReceiptStorageView, AnswerOracle,
};
