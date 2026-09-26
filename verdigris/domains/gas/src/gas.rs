//! The gas registry and mixture maths.

// Physical/tuning constants mirrored from DM (`SPECIFIC_HEATS`, fire/reaction
// thresholds, ...); many are read from DM or by other gas submodules rather
// than from within `constants` itself, so per-constant dead_code is noise.
#[allow(dead_code)]
pub mod constants;
pub mod ids;
pub mod mixture;
pub mod types;

pub use ids::*;
pub use mixture::Mixture;
pub use types::*;

pub type GasIDX = usize;
