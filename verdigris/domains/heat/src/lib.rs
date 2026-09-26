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
//! - [`couple`]: the gas interface, while gas is not yet a field
//!   (`rust_architecture.md` step 4 decision (b); deleted in step 6).
//! - [`consts`]: shared physical constants.

pub mod components;
pub mod consts;
pub mod couple;
pub mod laws;
pub mod mob;
pub mod solid;

pub use components::{BodyCoupling, GasCoupling, HeatBody, Regulator, SolidCoupling};
pub use couple::{GasExchange, GasHandle, GasProbe, GasRef, NoGas};
pub use mob::MobHeat;
pub use solid::{SolidCell, SolidCmd, SolidHeat};
