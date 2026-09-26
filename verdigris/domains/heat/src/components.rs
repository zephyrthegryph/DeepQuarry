//! Heat's component declarations (`rust_architecture.md` §6, §8.5):
//! `#[vg::component]` structs, worker-owned (the driver's frame pool steps
//! them, like the solid field) -- plain numeric fields only, so the macro
//! generates the whole FFI/watch surface and every field is watchable by
//! DM the same way an APC's channels are.
//!
//! [`HeatBody`] stores its energy (the additive, conserved quantity) and an
//! optional phase plateau; its temperature is a computed read-only field
//! (`energy` divided through [`vg_core::thermo::phase_temperature`]), never
//! itself a stored number, so it can never drift out of sync with the
//! energy the conservation ledger tracks. A body's exchange targets are not
//! fields of the body at all (`rust_architecture.md` step 4, decision (a)):
//! each is its own small entity, [`SolidCoupling`], [`BodyCoupling`] or
//! [`GasCoupling`], naming the body it belongs to through [`LinksTo`] and
//! (for [`BodyCoupling`]) the body it exchanges with through
//! [`vg_core::query::LinksTo2`] -- exactly the many-to-one shape
//! `crate::components::HeatBody`'s doc borrows from step 3's
//! `SmesInputTerminal`, just with two links instead of one.
//!
//! [`MobHeat`] is [`crate::mob`]'s existing flux-integrator body, ported
//! onto the component macro unchanged in shape (its `step`/`MobHeatFlux`
//! law already matched this file's target, `rust_architecture.md` §8.5).
//! [`Regulator`] is [`vg_core::thermo::Regulator`]'s settings, flattened.

use vg_core::query::{LinksTo, LinksTo2};
use vg_core::thermo::RegulatorMode;
use vg_core::vg;

/// A coupling's target kind, packed as `u8` in [`GasCoupling`].
pub mod gas_kind {
    /// The turf air at a grid cell (the coupling's `target` is a `CellId`).
    pub const TURF: u8 = 0;
    /// A gas mixture by arena id (a pipe network, a tank, a canister).
    pub const MIXTURE: u8 = 1;
}

/// A heat body: an object, machine or container's node
/// (`temperature.md` §2.2). Its exchange targets are separate
/// [`SolidCoupling`]/[`BodyCoupling`]/[`GasCoupling`] entities naming it.
#[vg::component(domain = heat, kind = 1, dm = "/atom/movable/vg_heat_body", owner = worker, computed = [temperature])]
pub struct HeatBody {
    /// J/K.
    #[vg(config, unit = "J/K", range = 0.0001..=1000000000000.0, default = 1.0, on_invalid = clamp)]
    pub capacity: f64,
    /// J, the conserved quantity (`rust_architecture.md` §4.9): shares the
    /// `heat_energy` total with [`crate::solid::SolidHeat`]'s own cells, so
    /// one `World::conserve("heat_energy", ..)` check covers both.
    #[vg(state, unit = "J", conserve = "heat_energy")]
    pub energy: f64,
    /// W in effect; negative is a sink.
    #[vg(config, unit = "W", range = -1000000000.0..=1000000000.0, default = 0.0, on_invalid = clamp)]
    pub power: f64,
    /// The phase plateau's temperature, K (0: no phase -- an ordinary
    /// sensible-heat body).
    #[vg(config, unit = "K", range = 0.0..=1000000.0, default = 0.0, on_invalid = clamp)]
    pub phase_temperature: f64,
    /// Latent heat of the phase plateau, J (ignored when
    /// `phase_temperature` is 0).
    #[vg(config, unit = "J", range = 0.0..=1000000000000.0, default = 0.0, on_invalid = clamp)]
    pub phase_latent: f64,
    /// Never released at equilibrium (a machine's interior); DM's own
    /// authority, read by the release bind, not by a law.
    #[vg(config, default = false)]
    pub keep: bool,
    /// Energy that left through the coupling marked `slot == 0` in the last
    /// step, J (positive: out of the body) -- for thermoelectric
    /// conversion, `body.rs::Body::flow` ported verbatim.
    #[vg(state, unit = "J", default = 0.0)]
    pub flow: f64,
    /// Following the exact analytic relaxation solution against slot 0's
    /// environment (`body.rs`'s `state::RELAX`) instead of being stepped
    /// every frame: `energy` holds the anchor value from `since`, not the
    /// current one -- read it through `crate::laws`'s relax model (or the
    /// `heat_body_temperature` bind), not this computed `temperature`
    /// field directly, while this is set.
    #[vg(state, default = false)]
    pub relax: bool,
    /// Anchor time of the analytic model, s.
    #[vg(state, default = 0.0)]
    pub since: f64,
    /// Environment temperature at the anchor, K.
    #[vg(state, unit = "K", default = 0.0)]
    pub ambient: f64,
}

impl HeatBody {
    /// The body's own [`vg_core::thermo::Phase`].
    #[must_use]
    pub fn phase(&self) -> vg_core::thermo::Phase {
        #[allow(clippy::cast_possible_truncation)]
        vg_core::thermo::Phase {
            temperature: self.phase_temperature as f32,
            latent: self.phase_latent as f32,
        }
    }

    /// The computed `temperature` readout DM watches and reads, K.
    #[must_use]
    #[allow(clippy::cast_possible_truncation)]
    pub fn temperature(&self) -> f64 {
        f64::from(vg_core::thermo::phase_temperature(
            self.energy as f32,
            self.capacity as f32,
            self.phase(),
        ))
    }
}

/// A body's coupling to a turf solid cell: its own entity, naming the body
/// through [`LinksTo`] and the target cell directly (a `CellId`, not
/// another entity -- read through `vg_core::query::Foreign<SolidCoupling,
/// vg_core::field::law::Cell<crate::solid::SolidHeat>>`).
#[vg::component(domain = heat, kind = 2, dm = "/atom/movable/vg_heat_solid_coupling", owner = worker)]
pub struct SolidCoupling {
    #[vg(config, default = 0)]
    pub body: u32,
    #[vg(config, default = 0)]
    pub cell: u32,
    #[vg(config, unit = "W/K", range = 0.0..=1000000000.0, default = 0.0, on_invalid = clamp)]
    pub conductance: f64,
    /// 0 or 1 (`crate::components::HeatBody::flow`'s slot, DM's
    /// `heat_body_couple` slot argument): only slot 0 updates the body's
    /// `flow` readout.
    #[vg(config, default = 0)]
    pub slot: u8,
}

impl LinksTo for SolidCoupling {
    fn linked_index(&self) -> Option<u32> {
        Some(self.body)
    }
}

/// [`SolidCoupling::cell`] doubles as the field-cell join key: `Foreign`
/// resolves through [`LinksTo::linked_index`], so the solid target reuses
/// the same trait as the body link would if it named another entity. A
/// coupling's *body* link is the primary [`LinksTo`]; the field cell is
/// reached from the same row through [`LinksTo2`] instead, so a law can
/// join both sides of the edge in one anchor.
impl LinksTo2 for SolidCoupling {
    fn linked_index2(&self) -> Option<u32> {
        Some(self.cell)
    }
}

/// A body's coupling to another body (a container's interior): its own
/// entity, naming the owning body through [`LinksTo`] and the other body
/// through [`LinksTo2`].
#[vg::component(domain = heat, kind = 3, dm = "/atom/movable/vg_heat_body_coupling", owner = worker)]
pub struct BodyCoupling {
    #[vg(config, default = 0)]
    pub body: u32,
    #[vg(config, default = 0)]
    pub other: u32,
    #[vg(config, unit = "W/K", range = 0.0..=1000000000.0, default = 0.0, on_invalid = clamp)]
    pub conductance: f64,
    #[vg(config, default = 0)]
    pub slot: u8,
}

impl LinksTo for BodyCoupling {
    fn linked_index(&self) -> Option<u32> {
        Some(self.body)
    }
}

impl LinksTo2 for BodyCoupling {
    fn linked_index2(&self) -> Option<u32> {
        Some(self.other)
    }
}

/// A body's coupling to a gas (turf air or a mixture by arena id): its own
/// entity, naming the owning body through [`LinksTo`]. Gas is not yet a
/// [`vg_core::field::FieldKind`] (`rust_architecture.md` step 6), so this
/// coupling's law reaches it through `crate::couple::GasExchange` (a
/// `Global` resource) instead of a `Foreign`/`Foreign2` join; it is deleted
/// in step 6 once `TurfGas` lands and the edge becomes field↔field.
#[vg::component(domain = heat, kind = 4, dm = "/atom/movable/vg_heat_gas_coupling", owner = worker)]
pub struct GasCoupling {
    #[vg(config, default = 0)]
    pub body: u32,
    /// `gas_kind::TURF` or `gas_kind::MIXTURE`.
    #[vg(config, default = 0)]
    pub kind: u8,
    /// A `CellId` (turf) or an arena mixture id.
    #[vg(config, default = 0)]
    pub target: u32,
    #[vg(config, unit = "W/K", range = 0.0..=1000000000.0, default = 0.0, on_invalid = clamp)]
    pub conductance: f64,
    #[vg(config, default = 0)]
    pub slot: u8,
}

impl LinksTo for GasCoupling {
    fn linked_index(&self) -> Option<u32> {
        Some(self.body)
    }
}

/// A thermal regulator (a heat pump/resistive heater): [`Regulator`]'s
/// settings, flattened onto plain numeric fields
/// (`vg_core::thermo::Regulator`, `rust_architecture.md` §6, §8.5). Couples
/// a controlled [`HeatBody`] to another one through the same [`LinksTo`]/
/// [`LinksTo2`] shape as [`BodyCoupling`].
#[vg::component(domain = heat, kind = 5, dm = "/atom/movable/vg_heat_regulator", owner = worker)]
pub struct Regulator {
    #[vg(config, default = 0)]
    pub controlled: u32,
    #[vg(config, default = 0)]
    pub other: u32,
    #[vg(config, unit = "K", range = 0.0..=1000000.0, default = 293.15, on_invalid = clamp)]
    pub target: f64,
    #[vg(config, unit = "W", range = 0.0..=1000000000.0, default = 0.0, on_invalid = clamp)]
    pub max_power: f64,
    /// `RegulatorMode` packed: 0 heat, 1 cool, 2 both.
    #[vg(config, default = 2)]
    pub mode: u8,
    #[vg(config, range = 0.0..=1.0, default = 0.5, on_invalid = clamp)]
    pub carnot_fraction: f64,
    #[vg(config, range = 1.0..=1000.0, default = 10.0, on_invalid = clamp)]
    pub max_cop: f64,
    #[vg(config, default = true)]
    pub resistive_heating: bool,
    #[vg(config, unit = "K", range = 0.0..=100.0, default = 0.05, on_invalid = clamp)]
    pub deadband: f64,
}

impl LinksTo for Regulator {
    fn linked_index(&self) -> Option<u32> {
        Some(self.controlled)
    }
}

impl LinksTo2 for Regulator {
    fn linked_index2(&self) -> Option<u32> {
        Some(self.other)
    }
}

impl Regulator {
    #[must_use]
    #[allow(clippy::cast_possible_truncation)]
    pub fn settings(&self) -> vg_core::thermo::Regulator {
        vg_core::thermo::Regulator {
            target: self.target as f32,
            max_power: self.max_power as f32,
            mode: match self.mode {
                0 => RegulatorMode::Heat,
                1 => RegulatorMode::Cool,
                _ => RegulatorMode::Both,
            },
            carnot_fraction: self.carnot_fraction as f32,
            max_cop: self.max_cop as f32,
            resistive_heating: self.resistive_heating,
            deadband: self.deadband as f32,
        }
    }
}
