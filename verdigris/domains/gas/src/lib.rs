//! vg-gas: the gas domain (`rust_architecture.md` §6, §8.5). Declarations
//! and laws only: turf gas is the [`cell::TurfGas`] field, pipes the
//! [`pipes::Pipes`] network, device flow the [`device`] laws, mixtures the
//! [`gas::Mixture`] maths. `vg-ffi` registers them on the shared World and
//! owns every DM-facing handle and bind.

pub mod cell;
pub mod device;
pub mod gas;
pub mod gate;
pub mod kind;
pub mod laws;
pub mod pipes;
pub mod planet;
pub mod power_budget;
pub mod reaction_energy;

#[cfg(test)]
mod tests;
