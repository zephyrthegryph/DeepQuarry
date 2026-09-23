//! The `GasMix` component (`doc/rewrite/rust_architecture.md` §5, §6): the
//! legacy `/datum/gas_mixture` API (~60 binds DM calls directly today, on
//! `Mixture` in `gas/mixture.rs`) expressed as a component, `owner = main`
//! -- a tank or a lung is read and written synchronously, with no frame
//! lag, unlike a pipe region or a turf cell.
//!
//! Modeled on [`super::pump`], the reference component: same `KindStore`
//! (R4's `MainPort`, generalized off gas), same entity-table binding, same
//! `Shared`/`DomainRegistry` wiring so `vg_entity_unbind`/
//! `vg_entity_tick_all`/reset act on this store too. Where it differs from
//! `Pump` is the two things this file exists to demonstrate:
//! - an **array config field** (`moles`, one entry per gas), the
//!   fixed-size enum-keyed shape `auxmacros::component` gained for this
//!   (`rust_bindings.md` §2);
//! - the **mixture law**: `refresh` is a pure function over the component's
//!   own config, not a copy of the ideal-gas math - it builds a transient
//!   [`PipeGas`] and reads `PipeGas::pressure`/`PipeGas::total`, the one
//!   implementation `device::Flow` already uses, instead of a third copy.
//!
//! `owner = main` isn't yet a distinct code path from `Pump`'s (implicitly
//! frame-driven) one: `KindStore::submit` already applies synchronously
//! (read-your-writes, no frame boundary - see `pump.rs`'s own test), so
//! today's store already behaves the way `owner = main` needs. The
//! distinction becomes real once a `owner = worker` law (the device flow
//! law, once it drives a real store) needs the overlay-over-pinned-frame
//! behaviour `owner = worker` promises and `main` doesn't. Adapt this file
//! when that lands, per the coordinator's note that the generated-store
//! part of `#[vg::component]` may still change under Core B.
//!
//! `dm =` names `/obj/item/gas_mix_holder`, a DM type that exists only to
//! carry this component: binding it to `/obj/item/tank` would make the
//! generated `get_temperature()` shadow every tank's own
//! `/atom/proc/get_temperature()`. Tanks, canisters and lungs (a lung is
//! an organ, not an atom) move onto GasMix with the DM-side work that
//! comes later; nothing in this file's Rust declaration or its laws
//! depends on which DM type ends up bound.

use byondapi::prelude::*;
use eyre::{Result, eyre};
use vg_core::vg;

use super::pump::DOMAIN;

use crate::cell::N;
use crate::gas::constants::T20C;
use crate::pipes::PipeGas;

/// This component's kind index within the gas domain (`super::pump::DOMAIN`
/// - `Pump` is kind 1, so `GasMix` is 2).
pub const KIND: u16 = GasMix::KIND;

#[vg::component(domain = gas, kind = 2, dm = "/obj/item/gas_mix_holder")]
pub struct GasMix {
	/// Moles of each gas, by gas ID (`gas::ids`). A generous upper bound
	/// (a ruptured supermatter-adjacent tank, not a realistic operating
	/// range) - the point is rejecting NaN/negative from a bad DM call,
	/// not modelling a physical tank limit here.
	#[vg(config, unit = "mol", range = 0.0..=1000000.0, default = [0.0; N], on_invalid = clamp)]
	moles: [f32; N],
	// 2.7 is `TCMB`: the binding generator reads ranges as literal numbers.
	#[vg(config, unit = "K", range = 2.7..=10000.0, default = T20C, on_invalid = clamp)]
	temperature: f32,
	#[vg(config, unit = "L", range = 0.0..=100000.0, default = 70.0, on_invalid = clamp)]
	volume: f32,
}

#[vg::query(GasMix, ui = [temperature, volume])]
#[allow(dead_code)]
struct GasMixQuery;

/// `pressure`/`total` are deliberately *not* component fields: a `state`
/// field has no command variant (only `config`/`input` fields do - see
/// `auxmacros::component`), so nothing could ever write one, and there is
/// no separate "internal law write" path onto a `KindStore` row yet
/// (`Pump`'s own `flow_rate` is in the same position - declared, never
/// actually written, until a real device-law driver exists). Rather than
/// declare state this file can't produce, `refresh` is exposed as a live
/// computed read instead: exactly as correct, and honest about what's
/// wired today. Restore them as `state` fields once a driver can write
/// them once per step instead of once per read.
pub struct Derived {
	pub pressure: f32,
	pub total: f32,
}

#[vg::events(GasMix)]
pub enum GasMixEvent {
	/// Pressure has risen past a threshold a caller (a tank's integrity
	/// law, once one exists) checks for - not raised by this file.
	Overpressure,
	/// `total` has fallen to (near) zero.
	Depleted,
}

/// The mixture law: recomputes `pressure`/`total` from `moles`,
/// `temperature` and `volume` - pure, and the same ideal-gas
/// implementation every other mixture (`PipeGas`, `GasCell`) uses, not a
/// third copy of `pV = nRT`.
#[must_use]
pub fn refresh(moles: &[f32; N], temperature: f32, volume: f32) -> Derived {
	let mut g = PipeGas::default();
	for (m, &v) in g.moles.iter_mut().zip(moles) {
		*m = f64::from(v);
	}
	g.temperature = temperature;
	g.energy = f64::from(crate::cell::heat_capacity(moles)) * f64::from(temperature);
	Derived {
		pressure: g.pressure(f64::from(volume)),
		total: g.total() as f32,
	}
}

impl GasMix {
	/// [`refresh`] over this row's own fields, for a caller that already
	/// has a `GasMix` value (a test, or a future law reading a `KindStore`
	/// row) rather than the three loose fields.
	#[must_use]
	pub fn refreshed(&self) -> Derived {
		refresh(&self.moles, self.temperature, self.volume)
	}
}

// --- Derived: read-only, live-computed by the mixture law -------------------

/// This row's [`refresh`], through the generated store (`__gas_mix_with`).
fn derived(entity: &ByondValue) -> Result<Derived> {
	let cell = __gas_mix_cell_of(entity)?;
	__gas_mix_with(|w| w.read(cell).map(|m| m.refreshed()).ok_or_else(|| eyre!("gas mix row {cell} out of range")))
}

#[auxmacros::bind("/obj/item/gas_mix_holder/proc/get_pressure")]
fn gas_mix_get_pressure(entity: ByondValue) -> Result<ByondValue> {
	Ok(ByondValue::from(derived(&entity)?.pressure))
}

#[auxmacros::bind("/obj/item/gas_mix_holder/proc/get_total")]
fn gas_mix_get_total(entity: ByondValue) -> Result<ByondValue> {
	Ok(ByondValue::from(derived(&entity)?.total))
}

#[cfg(test)]
mod tests {
	use super::*;
	use vg_core::store::KindStore;

	use crate::gas::constants::TCMB;
	use crate::gas::ids::{GAS_CARBON_DIOXIDE, GAS_OXYGEN};

	#[test]
	fn refresh_matches_pipegas_pressure_and_total() {
		let mut moles = [0.0; N];
		moles[GAS_OXYGEN] = 21.8;
		moles[GAS_CARBON_DIOXIDE] = 3.0;
		let d = refresh(&moles, T20C, 70.0);
		assert!((d.total - 24.8).abs() < 1e-3);
		assert!(d.pressure > 0.0);

		// Matches a hand-built PipeGas with the same composition exactly -
		// `refresh` must not be a second implementation of `pV = nRT`.
		let mut g = PipeGas::default();
		for (m, &v) in g.moles.iter_mut().zip(&moles) {
			*m = f64::from(v);
		}
		g.temperature = T20C;
		g.energy = f64::from(crate::cell::heat_capacity(&moles)) * f64::from(T20C);
		assert!((f64::from(d.pressure) - f64::from(g.pressure(70.0))).abs() < 1e-6);
		assert!((f64::from(d.total) - g.total()).abs() < 1e-6);
	}

	#[test]
	fn refresh_of_empty_mixture_is_zero_pressure() {
		let d = refresh(&[0.0; N], T20C, 70.0);
		assert_eq!(d.pressure, 0.0);
		assert_eq!(d.total, 0.0);
	}

	#[test]
	fn store_binds_writes_moles_and_the_law_derives_pressure_and_total() {
		let mut store = KindStore::<GasMixKind>::new();
		let seeded = GasMix {
			moles: [0.0; N],
			temperature: T20C,
			volume: 70.0,
		};
		let cell = store.bind(1.0, seeded).unwrap();

		let v = GasMix::validate_moles_at(21.8).unwrap();
		store.submit(cell, GasMixCommand::MolesAt(GAS_OXYGEN, v)).unwrap();
		let m = store.read(cell).unwrap();
		assert_eq!(m.moles[GAS_OXYGEN], 21.8);
		// Setting one gas leaves the others alone (the point of `*At`).
		assert_eq!(m.moles[GAS_CARBON_DIOXIDE], 0.0);

		let d = m.refreshed();
		assert!((d.total - 21.8).abs() < 1e-3);
		assert!(d.pressure > 0.0);

		store.detach(cell);
		assert_eq!(store.read(cell), Some(GasMix::default()), "detach resets the row to Value::default()");
	}

	#[test]
	fn validate_moles_clamps_negative_and_absurd_values() {
		assert_eq!(GasMix::validate_moles_at(-5.0).unwrap(), 0.0);
		assert_eq!(GasMix::validate_moles_at(1.0e9).unwrap(), 1.0e6);
		assert_eq!(GasMix::validate_moles_at(10.0).unwrap(), 10.0);
	}

	#[test]
	fn validate_temperature_clamps_below_cosmic_background() {
		assert_eq!(GasMix::validate_temperature(-100.0).unwrap(), TCMB);
	}
}
