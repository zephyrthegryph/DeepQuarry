//! Propagation services over the [`Grid`](crate::grid::Grid)
//! (`simulation.md` §2): a costed [`wavefront`] flood and grid [`ray`]s,
//! and their users (§8): [`radiation`] shielding and [`emp`] falloff.
//!
//! Both read the grid and caller-supplied cost or attenuation through shared
//! references only, and both are deterministic (integer costs, fixed
//! tie-breaking, sequential float products). Their working memory lives in
//! reusable scratch, so a frame task can keep one scratch per worker and run
//! floods or rays without allocating once the scratch has warmed up.

pub mod emp;
pub mod radiation;
pub mod ray;
pub mod wavefront;

pub use radiation::RadiationField;
pub use ray::{Ray, RayHit, line_of_sight};
pub use wavefront::{FloodLimits, FloodStop, Wavefront};
