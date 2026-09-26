//! The gas registry's fixed ids, the shared constants and the mixture maths.

pub mod constants;
pub mod ids;
pub mod mixture;

pub use crate::gate::{gas_idx_from_string, gas_idx_from_value};
pub use ids::*;
pub use mixture::Mixture;

pub type GasIDX = usize;
