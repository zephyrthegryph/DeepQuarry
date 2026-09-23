//! `vg-power`: the power domain (`simulation.md` §6, roadmap M3).
//! Host-buildable: it depends on `vg-core` only; the binds are in `vg-ffi`
//! (`ffi/src/power.rs`).
//!
//! - [`kind`]: [`Cables`], the R7 network kind. A region's summary is its
//!   supply, demand per APC channel and storage capacity; its payload is
//!   pooled storage, split by capacity.
//! - [`geom`]: the cable connection rule (`get_connections()`), so the
//!   graph is derived from each piece's turf and directions.
//! - [`apc`]: the APC distributor (channels, cell charging, shedding).
//! - [`smes`]: SMES units.
//! - [`world`]: [`PowerWorld`], the ledger and the step DM calls once per
//!   machinery tick.

pub mod apc;
pub mod geom;
pub mod kind;
pub mod smes;
pub mod world;

pub use kind::{Cables, Load};
pub use world::{Books, PowerWorld, RegionInfo, ev};

#[cfg(test)]
mod tests;
