//! `vg-heat`: the heat domain (`simulation.md` §7, `temperature.md`, roadmap
//! M4). Host-buildable: it depends on `vg-core` only, so every model here is
//! tested on the host. The DLL side (binds, the gas adapter) lives in vg-gas
//! (`domains/gas/src/heat.rs`), because the gas couplings need the gas arena.
//!
//! - [`solid`]: the turf solid heat field, a [`FieldKind`](vg_core::field::FieldKind)
//!   on R6's framework. Per-cell conductivity and heat capacity come from DM
//!   materials; space and planets are reservoirs; faces exposed to space
//!   radiate (Stefan–Boltzmann).
//! - [`body`]: heat bodies (nodes) for objects, machines and containers,
//!   created on first divergence and released at equilibrium. Coupled to a
//!   large reservoir, a body follows the exact relaxation solution and is
//!   not stepped until conditions change.
//! - [`couple`]: the gas interface ([`couple::GasExchange`]) and the frame
//!   tasks that move energy between the stores (solid ↔ gas in the same
//!   cell, body ↔ cell / gas / body), each writing both sides with one
//!   number so energy is conserved exactly.
//! - the thermal regulator, phase plateau and exchange math live in
//!   `vg_core::thermo` (the only exchange math in the workspace).
//! - [`world`]: [`world::HeatWorld`], the main-thread host that owns the
//!   [`Sim`](vg_core::sim::Sim), its ports and watches, and the API the DM
//!   binds call.

pub mod body;
pub mod consts;
pub mod couple;
pub mod laws;
pub mod mob;
pub mod solid;
pub mod world;

pub use body::{Bodies, Body, BodyCmd, Coupling, Target};
pub use couple::{GasExchange, GasProbe, GasRef};
pub use mob::{MobHandle, MobHeatBody, MobHeatCmd, MobHeatConfig, MobHeatFlux, MobHeatWorld, slot_of};
pub use solid::{SolidCell, SolidCmd, SolidHeat};
pub use world::{BodyHandle, CellKind, CellSpec, HeatConfig, HeatWorld, WatchTarget};
