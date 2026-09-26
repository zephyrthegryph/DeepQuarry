//! `vg-heat`: the heat domain (`rust_architecture.md` §6, §8.5). Host-
//! buildable: it depends on `vg-core` only.
//!
//! - [`solid`]: the turf solid heat field, a
//!   [`FieldKind`](vg_core::field::FieldKind) registered with
//!   [`vg_core::world::WorldBuilder::add_field`].
//! - [`components`]: [`components::HeatBody`] (items, machines,
//!   containers), [`components::SolidCoupling`]/[`components::BodyCoupling`]/
//!   [`components::GasCoupling`] (a body's exchange targets, each its own
//!   entity), [`components::Regulator`] (a heat pump) -- `#[vg::component]`
//!   declarations.
//! - [`laws`]: the [`vg_core::law::Law`]s that run those couplings over
//!   [`vg_core::world::World`].
//! - [`mob`]: [`mob::MobHeat`], DQ Medical's flux-integrator body.
//! - [`consts`]: shared physical constants.

pub mod components;
pub mod consts;
pub mod laws;
pub mod mob;
pub mod solid;

pub use components::{BodyCoupling, GasCoupling, HeatBody, Regulator, SolidCoupling};
pub use mob::MobHeat;
pub use solid::{SolidCell, SolidCmd, SolidHeat};
