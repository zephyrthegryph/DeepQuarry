//! The `GasMix` component (`doc/rewrite/rust_architecture.md` §5, §6): the
//! legacy `/datum/gas_mixture` API (~60 binds DM calls directly today, on
//! `Mixture` in `gas/mixture.rs`) expressed as a component, `owner = main`
//! -- a tank or a lung is read and written synchronously, with no frame
//! lag, unlike a pipe region or a turf cell.
//!
//! Where it differs from [`super::pump`] is what this file demonstrates:
//! - `owner = main`: rows live on the main thread, so DM's writes and reads
//!   are synchronous with no frame lag;
//! - an **array config field** (`moles`, one entry per gas);
//! - **computed readouts** (`pressure`, `total`): read-only fields the
//!   generic FFI read serves by calling the mixture law, [`refresh`], which
//!   reuses `PipeGas`'s ideal-gas implementation instead of a third copy.
//!   They are watchable channels like any stored field.
//!
//! `dm =` names `/obj/item/gas_mix_holder`, a DM type that exists only to
//! carry this component: binding it to `/obj/item/tank` would make the
//! generated `get_temperature()` shadow every tank's own
//! `/atom/proc/get_temperature()`. Tanks, canisters and lungs (a lung is
//! an organ, not an atom) move onto GasMix with the DM-side work that
//! comes later; nothing in this file's Rust declaration or its laws
//! depends on which DM type ends up bound.

use vg_core::vg;

use crate::cell::N;
use crate::gas::constants::T20C;
use crate::pipes::PipeGas;

#[vg::component(domain = gas, kind = 2, dm = "/obj/item/gas_mix_holder", owner = main, computed = [pressure, total])]
pub struct GasMix {
	/// Moles of each gas, by gas ID (`gas::ids`). A generous upper bound
	/// (a ruptured supermatter-adjacent tank, not a realistic operating
	/// range) - the point is rejecting NaN/negative from a bad DM call,
	/// not modelling a physical tank limit here.
	#[vg(config, unit = "mol", range = 0.0..=1000000.0, default = [0.0; N], on_invalid = clamp, conserve = "gas_moles")]
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

/// The mixture law's derived values.
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
	/// [`refresh`] over this row's own fields.
	#[must_use]
	pub fn refreshed(&self) -> Derived {
		refresh(&self.moles, self.temperature, self.volume)
	}

	/// Computed readout: pressure, kPa.
	#[must_use]
	pub fn pressure(&self) -> f32 {
		self.refreshed().pressure
	}

	/// Computed readout: total moles.
	#[must_use]
	pub fn total(&self) -> f32 {
		self.refreshed().total
	}
}

#[cfg(test)]
mod tests {
	use super::*;

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
	fn generic_writes_set_one_gas_and_the_readouts_follow() {
		use vg_core::component::Component;
		use vg_core::owner::Domain;
		let mut m = GasMix::default();
		let moles = GasMix::field_id("moles").unwrap();
		let cmd = GasMix::set_command(moles, Some(GAS_OXYGEN), 21.8).unwrap();
		GasMixKind::apply(&mut m, &cmd);
		assert_eq!(m.moles[GAS_OXYGEN], 21.8);
		assert_eq!(m.moles[GAS_CARBON_DIOXIDE], 0.0, "setting one gas leaves the others alone");
		let total = GasMix::field_id("total").unwrap();
		assert!((m.get_field(total, 0).unwrap() - 21.8).abs() < 1e-3);
		assert!(GasMix::set_command(total, None, 1.0).is_err(), "computed readouts are read-only");
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
