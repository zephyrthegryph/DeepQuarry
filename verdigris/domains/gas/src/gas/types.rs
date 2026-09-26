//! The gas registry's data (`rust_architecture.md` §8.5 step 6, decision
//! 1): pure storage and lookups, split from the `byondapi` loading that
//! populates it. `ffi/src/gas.rs` reads DM's gas/reaction datums and calls
//! [`install_gases`]/[`install_reactions`]; everything else here (used by
//! `vg-gas`'s own tests too, `#[cfg(test)]` below) never touches a
//! `ByondValue`.

use super::GasIDX;
use crate::reaction::{Reaction, ReactionPriority};
use eyre::Result;
use parking_lot::{const_rwlock, RwLock};
use std::collections::BTreeMap;

static REACTION_INFO: RwLock<Option<BTreeMap<ReactionPriority, Reaction>>> = const_rwlock(None);

/// The temperature at which this gas can oxidize and how much fuel it can oxidize when it can.
#[derive(Clone, Copy)]
pub struct OxidationInfo {
	temperature: f32,
	power: f32,
}

impl OxidationInfo {
	#[must_use]
	pub fn new(temperature: f32, power: f32) -> Self {
		Self { temperature, power }
	}
	#[must_use]
	pub fn temperature(&self) -> f32 {
		self.temperature
	}
	#[must_use]
	pub fn power(&self) -> f32 {
		self.power
	}
}

/// The temperature at which this gas can burn and how much it burns when it does.
/// This may seem redundant with `OxidationInfo`, but `burn_rate` is actually the inverse, dimensions-wise, moles^-1 rather than moles.
#[derive(Clone, Copy)]
pub struct FuelInfo {
	temperature: f32,
	burn_rate: f32,
}

impl FuelInfo {
	#[must_use]
	pub fn new(temperature: f32, burn_rate: f32) -> Self {
		Self { temperature, burn_rate }
	}
	#[must_use]
	pub fn temperature(&self) -> f32 {
		self.temperature
	}
	#[must_use]
	pub fn burn_rate(&self) -> f32 {
		self.burn_rate
	}
}

/// Contains either oxidation info, fuel info or neither.
/// Just use it with match always, no helpers here.
#[derive(Clone, Copy)]
pub enum FireInfo {
	Oxidation(OxidationInfo),
	Fuel(FuelInfo),
	None,
}

/// We can't guarantee the order of loading gases, so any properties of gases that reference other gases
/// must have a reference like this that can get the proper index at runtime.
#[derive(Clone)]
pub enum GasRef {
	Deferred(String),
	Found(GasIDX),
}

impl GasRef {
	/// Gets the index of the gas.
	/// # Errors
	/// Propagates error from `gas_idx_from_string`.
	pub fn get(&self) -> Result<GasIDX> {
		match self {
			Self::Deferred(s) => gas_idx_from_string(s),
			Self::Found(id) => Ok(*id),
		}
	}
	/// Like `get`, but also caches the result if found.
	/// # Errors
	/// If the string is not a valid gas name.
	pub fn update(&mut self) -> Result<GasIDX> {
		match self {
			Self::Deferred(s) => {
				*self = Self::Found(gas_idx_from_string(s)?);
				self.get()
			}
			Self::Found(id) => Ok(*id),
		}
	}
}

#[derive(Clone)]
pub enum FireProductInfo {
	Generic(Vec<(GasRef, f32)>),
	Plasma, // yeah, just hardcoding the funny trit production
}

/// An individual gas type. Contains a whole lot of info attained from Byond when the gas is first registered.
/// If you don't have any of these, just fork auxmos and remove them, many of these are not necessary--for example,
/// if you don't have fusion, you can just remove `fusion_power`.
/// Each individual member also has the byond /datum/gas equivalent listed.
#[derive(Clone)]
pub struct GasType {
	/// The index of this gas in the moles vector of a mixture. Usually the most common representation in Auxmos, for speed.
	/// No byond equivalent.
	pub idx: GasIDX,
	/// The ID on the byond end, as a boxed str. Most convenient way to reference it in code; use the function gas_idx_from_string to get idx from this.
	/// Byond: `id`, a string.
	pub id: Box<str>,
	/// The gas's name. Not used in auxmos as of yet.
	/// Byond: `name`, a string.
	pub name: Box<str>,
	/// Byond: `flags`, a number (bitflags).
	pub flags: u32,
	/// The specific heat of the gas. Duplicated in the GAS_SPECIFIC_HEATS vector for speed.
	/// Byond: `specific_heat`, a number.
	pub specific_heat: f32,
	/// kg/mol. Byond: `GLOB.gas_data.molar_mass[id]` (`xgm_compat.dm`'s
	/// canonical table, not a `/datum/gas` var) -- needed alongside
	/// `specific_heat` for the entropy-based power-budget math a filter or
	/// mixer device runs (`rust_architecture.md` §8.5 step 6).
	pub molar_mass: f32,
	/// Gas's fusion power. Used in fusion hooking, so this can be removed and ignored if you don't have fusion.
	/// Byond: `fusion_power`, a number.
	pub fusion_power: f32,
	/// The moles at which the gas's overlay or other appearance shows up. If None, gas is never visible.
	/// Byond: `moles_visible`, a number.
	pub moles_visible: Option<f32>,
	/// Standard enthalpy of formation.
	/// Byond: `fire_energy_released`, a number.
	pub enthalpy: f32,
	/// Amount of radiation released per mole burned.
	/// Byond: `fire_radiation_released`, a number.
	pub fire_radiation_released: f32,
	/// Either fuel info, oxidation info or neither. See the documentation on the respective types.
	/// Byond: `oxidation_temperature` and `oxidation_rate` XOR `fire_temperature` and `fire_burn_rate`
	pub fire_info: FireInfo,
	/// A vector of gas-amount pairs. GasRef is just which gas, the f32 is moles made/mole burned.
	/// Byond: `fire_products`, a list of gas IDs associated with amounts.
	pub fire_products: Option<FireProductInfo>,
}

impl GasType {
	/// Builds a gas's registry entry from already-parsed values (the
	/// `ByondValue` reading -- every `/datum/gas` var this used to read
	/// directly -- lives in `ffi/src/gas.rs` now).
	#[must_use]
	#[allow(clippy::too_many_arguments)]
	pub fn new(
		idx: GasIDX,
		id: Box<str>,
		name: Box<str>,
		flags: u32,
		specific_heat: f32,
		molar_mass: f32,
		fusion_power: f32,
		moles_visible: Option<f32>,
		enthalpy: f32,
		fire_radiation_released: f32,
		fire_info: FireInfo,
		fire_products: Option<FireProductInfo>,
	) -> Self {
		Self {
			idx,
			id,
			name,
			flags,
			specific_heat,
			molar_mass,
			fusion_power,
			moles_visible,
			enthalpy,
			fire_radiation_released,
			fire_info,
			fire_products,
		}
	}
}

static GAS_INFO_BY_IDX: RwLock<Option<Vec<GasType>>> = const_rwlock(None);

/// Prepares the registry for a fresh load (`ffi/src/gas.rs`'s own
/// `#[byondapi::init]`-attributed function calls this: that attribute needs
/// `byondapi` in scope, which this pure module no longer depends on).
pub fn initialize_gas_info_structs() {
	*GAS_INFO_BY_IDX.write() = Some(Vec::new());
}

pub fn destroy_gas_info_structs() {
	if let Some(gases) = GAS_INFO_BY_IDX.write().as_mut() {
		gases.clear();
	}
}

/// Installs the gas roster. Each gas lands at the fixed ID of its type path
/// (`ids.rs`), so DM's generated `GAS_ID_*` numbers and the arena agree without
/// any lookup at call time.
///
/// # Errors
/// If the roster is missing an ID, has the wrong count, or a specific heat
/// disagrees with `cell.rs`'s `SPECIFIC_HEATS`.
pub fn install_gases(mut gases: Vec<GasType>) -> Result<()> {
	gases.sort_by_key(|gas| gas.idx);
	for (expected, gas) in gases.iter().enumerate() {
		if gas.idx != expected {
			return Err(eyre::eyre!(
				"gas registry is missing ID {expected} ({:?}); every entry of GAS_PATHS needs a /datum/gas",
				super::ids::gas_path(expected)
			));
		}
	}
	if gases.len() != super::ids::GAS_COUNT {
		return Err(eyre::eyre!(
			"gas registry has {} gases, GAS_PATHS has {}",
			gases.len(),
			super::ids::GAS_COUNT
		));
	}
	for gas in &gases {
		let expected = crate::cell::SPECIFIC_HEATS[gas.idx];
		if gas.specific_heat != expected {
			return Err(eyre::eyre!(
				"{} has specific_heat {} in DM but {expected} in verdigris cell.rs SPECIFIC_HEATS",
				gas.id,
				gas.specific_heat
			));
		}
	}
	*GAS_INFO_BY_IDX.write() = Some(gases);
	Ok(())
}

/// Publishes a freshly-read reaction table (`ffi/src/gas.rs` reads
/// `SSair.gas_reactions` and builds this; both `auxtools_atmos_init` and
/// `auxtools_update_reactions` call it there, replacing this module's own
/// former `hook_init`/`update_reactions` binds).
pub fn install_reactions(reactions: BTreeMap<ReactionPriority, Reaction>) {
	*REACTION_INFO.write() = Some(reactions);
	install_gate();
}

/// Publishes the reaction requirements and gas visibility the turf field
/// reads on frame threads (`gate.rs`).
pub fn install_gate() {
	let mut gate = crate::gate::Gate::default();
	if let Some(reactions) = REACTION_INFO.read().as_ref() {
		gate.reactions = reactions
			.values()
			.rev()
			.map(Reaction::requirement)
			.collect();
	}
	if let Some(gases) = GAS_INFO_BY_IDX.read().as_ref() {
		for gas in gases {
			if gas.idx >= super::ids::GAS_COUNT {
				continue;
			}
			gate.visible[gas.idx] = gas.moles_visible;
			gate.fire[gas.idx] = match gas.fire_info {
				FireInfo::Oxidation(o) => crate::gate::Fire::Oxidizer {
					temperature: o.temperature(),
					power: o.power(),
				},
				FireInfo::Fuel(f) => crate::gate::Fire::Fuel {
					temperature: f.temperature(),
					burn_rate: f.burn_rate(),
				},
				FireInfo::None => crate::gate::Fire::None,
			};
		}
	}
	crate::gate::install(gate);
}

/// Calls the given closure with all reaction info as an argument.
/// # Panics
/// If reactions aren't loaded yet.
pub fn with_reactions<T, F>(mut f: F) -> T
where
	F: FnMut(&BTreeMap<ReactionPriority, Reaction>) -> T,
{
	f(REACTION_INFO
		.read()
		.as_ref()
		.unwrap_or_else(|| panic!("Reactions not loaded yet! Uh oh!")))
}

/// Returns the total number of gases in use. Only used by gas mixtures; should probably stay that way.
pub fn total_num_gases() -> GasIDX {
	// Gas IDs are fixed at compile time (ids.rs).
	super::ids::GAS_COUNT
}

/// Gets the gas visibility threshold for the given gas ID.
/// # Panics
/// If gas info isn't loaded yet.
#[must_use]
pub fn gas_visibility(idx: usize) -> Option<f32> {
	GAS_INFO_BY_IDX
		.read()
		.as_ref()
		.unwrap_or_else(|| panic!("Gases not loaded yet! Uh oh!"))
		// `idx` comes from FFI callers (gas cell indices), so an out-of-range
		// value must fall through to "not visible" rather than panic.
		.get(idx)
		.and_then(|gas| gas.moles_visible)
}

/// The molar mass (kg/mol) of gas `idx`, or `0.0` if it isn't registered
/// (a filter/mixer's power-budget math then falls back to the same
/// specific-heat-derived estimate DM's own `specific_entropy_gas()` uses
/// for a gas with no molar mass on file).
#[must_use]
pub fn molar_mass(idx: usize) -> f32 {
	GAS_INFO_BY_IDX
		.read()
		.as_ref()
		.and_then(|gases| gases.get(idx))
		.map_or(0.0, |gas| gas.molar_mass)
}

/// Gets a copy of all the gas visibilities.
/// # Panics
/// If gas info isn't loaded yet.
#[must_use]
pub fn visibility_copies() -> Box<[Option<f32>]> {
	GAS_INFO_BY_IDX
		.read()
		.as_ref()
		.unwrap_or_else(|| panic!("Gases not loaded yet! Uh oh!"))
		.iter()
		.map(|g| g.moles_visible)
		.collect::<Vec<_>>()
		.into_boxed_slice()
}

/// Allows one to run a closure with a lock on the global gas info vec.
/// # Panics
/// If gas info isn't loaded yet.
pub fn with_gas_info<T>(f: impl FnOnce(&[GasType]) -> T) -> T {
	f(GAS_INFO_BY_IDX
		.read()
		.as_ref()
		.unwrap_or_else(|| panic!("Gases not loaded yet! Uh oh!")))
}

/// Updates all the `GasRef`s in the global gas info vec with proper indices instead of strings.
///
/// # Errors
/// If a `GasRef::Deferred` doesn't resolve to a registered gas.
/// # Panics
/// If gas info is not loaded yet.
pub fn update_gas_refs() -> Result<()> {
	GAS_INFO_BY_IDX
		.write()
		.as_mut()
		.unwrap_or_else(|| panic!("Gases not loaded yet! Uh oh!"))
		.iter_mut()
		.try_for_each(|gas| {
			if let Some(FireProductInfo::Generic(products)) = gas.fire_products.as_mut() {
				for product in products.iter_mut() {
					product.0.update()?;
				}
			}
			Ok(())
		})
}
/// The ID for a gas string: its DM type path (`"/datum/gas/oxygen"`) or its
/// short gas-string ID (`"o2"`). Used only when parsing gas strings; the FFI
/// takes numeric IDs.
/// # Errors
/// If gases aren't loaded or the string names no gas.
pub fn gas_idx_from_string(id: &str) -> Result<GasIDX> {
	if let Some(idx) = super::ids::gas_id_for_path(id) {
		return Ok(idx);
	}
	GAS_INFO_BY_IDX
		.read()
		.as_ref()
		.ok_or_else(|| eyre::eyre!("Gases not loaded yet! Uh oh!"))?
		.iter()
		.find(|gas| &*gas.id == id)
		.map(|gas| gas.idx)
		.ok_or_else(|| eyre::eyre!("Invalid gas ID: {id}"))
}

/// The gas index for a numeric `GAS_ID_*` value passed from DM (already
/// read out of its `ByondValue` by the caller -- `ffi/src/gas.rs` -- since
/// this module doesn't depend on `byondapi`).
/// # Errors
/// If the value is not a registered gas ID.
#[allow(clippy::cast_sign_loss, clippy::cast_possible_truncation)]
pub fn gas_idx_from_value(raw: f32) -> Result<GasIDX> {
	let idx = raw as GasIDX;
	if raw < 0.0 || raw.fract() != 0.0 || idx >= total_num_gases() {
		return Err(eyre::eyre!("Invalid gas ID: {raw}"));
	}
	Ok(idx)
}

#[cfg(test)]
pub fn register_gas_manually(gas_id: &'static str, specific_heat: f32) {
	let gas_cache = GasType {
		idx: GAS_INFO_BY_IDX.read().as_ref().map_or(0, Vec::len),
		id: gas_id.into(),
		name: gas_id.into(),
		flags: 0,
		specific_heat,
		molar_mass: 0.0,
		fusion_power: 0.0,
		moles_visible: None,
		enthalpy: 0.0,
		fire_radiation_released: 0.0,
		fire_info: FireInfo::None,
		fire_products: None,
	};
	GAS_INFO_BY_IDX.write().as_mut().unwrap().push(gas_cache);
}

#[cfg(test)]
pub fn set_gas_statics_manually() {
	initialize_gas_info_structs();
}

#[cfg(test)]
pub fn destroy_gas_statics() {
	destroy_gas_info_structs();
}

#[cfg(test)]
pub(crate) static TEST_GAS_GLOBALS_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
