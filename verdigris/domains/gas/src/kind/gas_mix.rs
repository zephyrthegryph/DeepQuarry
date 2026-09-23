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
//! `dm =` names one representative DM type (a gas tank); a lung is a
//! different DM type entirely (an organ, not an atom), so binding both to
//! one generated DM surface needs either a second `dm =` target or a
//! shared interface on the DM side - that wiring is explicitly later work
//! ("DM-side work (canisters, alarms, firedoors) comes later"). Nothing in
//! this file's Rust declaration or its laws depends on which DM type ends
//! up bound.

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use byondapi::prelude::*;
use eyre::{Result, eyre};
use vg_core::component::QueryValue;
use vg_core::entity::ComponentRef;
use vg_core::store::KindStore;
use vg_core::vg;
use vg_ffi::entity;
use vg_ffi::registry::{self, DomainRegistry};

use crate::cell::N;
use crate::gas::constants::{T20C, TCMB};
use crate::pipes::PipeGas;

/// This component's kind index within the gas domain (`super::pump::DOMAIN`
/// - `Pump` is kind 1, so `GasMix` is 2).
pub const KIND: u16 = GasMix::KIND;

#[vg::component(domain = gas, kind = 2, dm = "/obj/item/tank")]
pub struct GasMix {
	/// Moles of each gas, by gas ID (`gas::ids`). A generous upper bound
	/// (a ruptured supermatter-adjacent tank, not a realistic operating
	/// range) - the point is rejecting NaN/negative from a bad DM call,
	/// not modelling a physical tank limit here.
	#[vg(config, unit = "mol", range = 0.0..=1.0e6, default = [0.0; N], on_invalid = clamp)]
	moles: [f32; N],
	#[vg(config, unit = "K", range = TCMB..=1.0e4, default = T20C, on_invalid = clamp)]
	temperature: f32,
	#[vg(config, unit = "L", range = 0.0..=1.0e5, default = 70.0, on_invalid = clamp)]
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

struct Shared(Rc<RefCell<KindStore<GasMixKind>>>);

impl DomainRegistry for Shared {
	fn detach(&mut self, comp: ComponentRef) {
		if comp.kind != KIND {
			return;
		}
		self.0.borrow_mut().detach(comp.cell);
	}
	fn describe(&self, comp: ComponentRef) -> Vec<(String, String)> {
		if comp.kind != KIND {
			return Vec::new();
		}
		let Some(m) = self.0.borrow().read(comp.cell) else {
			return Vec::new();
		};
		let d = m.refreshed();
		vec![
			("temperature".into(), format!("{} K", m.temperature)),
			("volume".into(), format!("{} L", m.volume)),
			("pressure".into(), format!("{} kPa", d.pressure)),
			("total".into(), format!("{} mol", d.total)),
		]
	}
	fn tick(&mut self) {
		self.0.borrow_mut().tick();
	}
	fn reset(&mut self) {
		*self.0.borrow_mut() = KindStore::new();
	}
	fn drain_events(&mut self, out: &mut Vec<(u16, f32, u8)>) {
		let mut raw = Vec::new();
		self.0.borrow_mut().drain_events(&mut raw);
		out.extend(raw.into_iter().map(|(entity, id)| (KIND, entity, id)));
	}
}

thread_local! {
	static STORE: Rc<RefCell<KindStore<GasMixKind>>> = Rc::new(RefCell::new(KindStore::new()));
	static REGISTERED: Cell<bool> = const { Cell::new(false) };
}

fn with<T>(f: impl FnOnce(&mut KindStore<GasMixKind>) -> Result<T>) -> Result<T> {
	REGISTERED.with(|done| {
		if !done.get() {
			#[allow(clippy::cast_possible_truncation)]
			STORE.with(|s| registry::register_domain(super::pump::DOMAIN as u32, Box::new(Shared(Rc::clone(s)))));
			done.set(true);
		}
	});
	STORE.with(|s| f(&mut s.borrow_mut()))
}

fn num(v: &ByondValue) -> Result<f32> {
	Ok(v.get_number()?)
}

fn cell_of(entity: &ByondValue) -> Result<u32> {
	let comp = entity::resolve(num(entity)?, super::pump::DOMAIN, KIND)?;
	Ok(comp.cell)
}

fn read(cell: u32) -> Result<GasMix> {
	with(|w| w.read(cell).ok_or_else(|| eyre!("gas mix row {cell} out of range")))
}

// --- Lifecycle -------------------------------------------------------------

/// Creates or reuses the entity and attaches a `GasMix` seeded from the
/// `init_*` values (see `pump_bind`).
#[auxmacros::bind("/proc/gas_mix_bind")]
fn gas_mix_bind(entity: ByondValue, init_temperature: ByondValue, init_volume: ByondValue) -> Result<ByondValue> {
	let temperature =
		GasMix::validate_temperature(num(&init_temperature)?).map_err(|e| eyre!("field `temperature`: {e}"))?;
	let volume = GasMix::validate_volume(num(&init_volume)?).map_err(|e| eyre!("field `volume`: {e}"))?;
	let value = GasMix {
		moles: [0.0; N],
		temperature,
		volume,
	};
	let id = entity::bind_or_reuse(num(&entity)?)?;
	let entity_v = entity::entity_value(id);
	let cell = with(|w| w.bind(entity_v, value).map_err(|e| eyre!("gas mix bind: {e}")))?;
	entity::attach(id, super::pump::DOMAIN, ComponentRef::new(KIND, cell)).map_err(|e| eyre!("{e}"))?;
	Ok(ByondValue::from(entity_v))
}

// --- Config: get/set ---------------------------------------------------------

#[auxmacros::bind("/obj/item/tank/proc/get_moles")]
fn gas_mix_get_moles(entity: ByondValue, gas: ByondValue) -> Result<ByondValue> {
	let idx = gas.get_number()? as usize;
	let m = read(cell_of(&entity)?)?;
	Ok(ByondValue::from(m.moles.get(idx).copied().unwrap_or(0.0)))
}

#[auxmacros::bind("/obj/item/tank/proc/set_moles")]
fn gas_mix_set_moles(entity: ByondValue, gas: ByondValue, value: ByondValue) -> Result<ByondValue> {
	let cell = cell_of(&entity)?;
	let idx = gas.get_number()? as usize;
	let v = GasMix::validate_moles_at(num(&value)?).map_err(|e| eyre!("field `moles`: {e}"))?;
	with(|w| w.submit(cell, GasMixCommand::MolesAt(idx, v)).map_err(|e| eyre!("{e}")))?;
	Ok(ByondValue::from(v))
}

#[auxmacros::bind("/obj/item/tank/proc/get_temperature")]
fn gas_mix_get_temperature(entity: ByondValue) -> Result<ByondValue> {
	Ok(ByondValue::from(read(cell_of(&entity)?)?.temperature))
}

#[auxmacros::bind("/obj/item/tank/proc/set_temperature")]
fn gas_mix_set_temperature(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
	let cell = cell_of(&entity)?;
	let v = GasMix::validate_temperature(num(&value)?).map_err(|e| eyre!("field `temperature`: {e}"))?;
	with(|w| w.submit(cell, GasMixCommand::Temperature(v)).map_err(|e| eyre!("{e}")))?;
	Ok(ByondValue::from(v))
}

#[auxmacros::bind("/obj/item/tank/proc/get_volume")]
fn gas_mix_get_volume(entity: ByondValue) -> Result<ByondValue> {
	Ok(ByondValue::from(read(cell_of(&entity)?)?.volume))
}

#[auxmacros::bind("/obj/item/tank/proc/set_volume")]
fn gas_mix_set_volume(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
	let cell = cell_of(&entity)?;
	let v = GasMix::validate_volume(num(&value)?).map_err(|e| eyre!("field `volume`: {e}"))?;
	with(|w| w.submit(cell, GasMixCommand::Volume(v)).map_err(|e| eyre!("{e}")))?;
	Ok(ByondValue::from(v))
}

// --- Derived: read-only, live-computed by the mixture law -------------------

#[auxmacros::bind("/obj/item/tank/proc/get_pressure")]
fn gas_mix_get_pressure(entity: ByondValue) -> Result<ByondValue> {
	Ok(ByondValue::from(read(cell_of(&entity)?)?.refreshed().pressure))
}

#[auxmacros::bind("/obj/item/tank/proc/get_total")]
fn gas_mix_get_total(entity: ByondValue) -> Result<ByondValue> {
	Ok(ByondValue::from(read(cell_of(&entity)?)?.refreshed().total))
}

// --- Query group -------------------------------------------------------------

/// The macro-generated config fields (`temperature`, `volume`) plus the two
/// derived values, in one call - `GasMixQuery`'s own group can't include
/// them (they aren't component fields; see [`Derived`]'s doc), so they're
/// appended by hand instead of a second round trip.
#[auxmacros::bind("/obj/item/tank/proc/gas_mix_query_ui")]
fn gas_mix_query_ui(entity: ByondValue) -> Result<ByondValue> {
	let m = read(cell_of(&entity)?)?;
	let d = m.refreshed();
	let values: Vec<ByondValue> = m
		.query_ui()
		.into_iter()
		.map(|v| match v {
			QueryValue::F32(f) => ByondValue::from(f),
			QueryValue::F64(f) => ByondValue::from(f as f32),
			QueryValue::Bool(b) => ByondValue::from(if b { 1.0f32 } else { 0.0f32 }),
		})
		.collect();
	let mut list = ByondValue::new_list()?;
	for (name, value) in GasMix::QUERY_UI_FIELDS.iter().zip(values) {
		list.write_list_index(*name, value)?;
	}
	list.write_list_index("pressure", ByondValue::from(d.pressure))?;
	list.write_list_index("total", ByondValue::from(d.total))?;
	Ok(list)
}

#[cfg(test)]
mod tests {
	use super::*;
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
