use super::GasIDX;
use crate::reaction::{Reaction, ReactionPriority};
use auxcallback::byond_callback_sender;
use byondapi::prelude::*;
use eyre::{Context, Result};
use parking_lot::{const_rwlock, RwLock};
use std::{
	collections::BTreeMap,
	sync::atomic::{AtomicUsize, Ordering},
};

static TOTAL_NUM_GASES: AtomicUsize = AtomicUsize::new(0);
static REACTION_INFO: RwLock<Option<BTreeMap<ReactionPriority, Reaction>>> = const_rwlock(None);

/// The temperature at which this gas can oxidize and how much fuel it can oxidize when it can.
#[derive(Clone, Copy)]
pub struct OxidationInfo {
	temperature: f32,
	power: f32,
}

impl OxidationInfo {
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
	// This absolute monster is what you want to override to add or remove certain gas properties, based on what a gas datum has.
	fn new(gas: &ByondValue, idx: GasIDX) -> Result<Self> {
		Ok(Self {
			idx,
			id: gas.read_string_id(byond_string!("id"))?.into_boxed_str(),
			name: gas.read_string_id(byond_string!("name"))?.into_boxed_str(),
			flags: gas
				.read_number_id(byond_string!("flags"))
				.unwrap_or_default() as u32,
			specific_heat: gas.read_number_id(byond_string!("specific_heat"))?,
			fusion_power: gas
				.read_number_id(byond_string!("fusion_power"))
				.unwrap_or_default(),
			moles_visible: gas.read_number_id(byond_string!("moles_visible")).ok(),
			fire_info: {
				if let Ok(temperature) = gas.read_number_id(byond_string!("oxidation_temperature"))
				{
					FireInfo::Oxidation(OxidationInfo {
						temperature,
						power: gas.read_number_id(byond_string!("oxidation_rate"))?,
					})
				} else if let Ok(temperature) =
					gas.read_number_id(byond_string!("fire_temperature"))
				{
					FireInfo::Fuel(FuelInfo {
						temperature,
						burn_rate: gas.read_number_id(byond_string!("fire_burn_rate"))?,
					})
				} else {
					FireInfo::None
				}
			},
			fire_products: gas
				.read_var_id(byond_string!("fire_products"))
				.ok()
				.and_then(|product_info| {
					if product_info.is_list() {
						Some(FireProductInfo::Generic(
							product_info
								.iter()
								.unwrap()
								.filter_map(|(k, v)| {
									k.get_string().ok().and_then(|s_str| {
										v.get_number()
											.ok()
											.map(|amt| (GasRef::Deferred(s_str), amt))
									})
								})
								.collect(),
						))
					} else if product_info.is_num() {
						Some(FireProductInfo::Plasma) // if we add another snowflake later, add it, but for now we hack this in
					} else {
						None
					}
				}),
			enthalpy: gas
				.read_number_id(byond_string!("enthalpy"))
				.unwrap_or_default(),
			fire_radiation_released: gas
				.read_number_id(byond_string!("fire_radiation_released"))
				.unwrap_or_default(),
		})
	}
}

static GAS_INFO_BY_IDX: RwLock<Option<Vec<GasType>>> = const_rwlock(None);

static GAS_SPECIFIC_HEATS: RwLock<Option<Vec<f32>>> = const_rwlock(None);

#[byondapi::init]
pub fn initialize_gas_info_structs() {
	*GAS_INFO_BY_IDX.write() = Some(Vec::new());
	*GAS_SPECIFIC_HEATS.write() = Some(Vec::new());
}

pub fn destroy_gas_info_structs() {
	crate::turfs::wait_for_tasks();
	GAS_INFO_BY_IDX.write().as_mut().unwrap().clear();
	GAS_SPECIFIC_HEATS.write().as_mut().unwrap().clear();
	TOTAL_NUM_GASES.store(0, Ordering::Release);
}

/// Installs the gas roster. Each gas lands at the fixed ID of its type path
/// (`ids.rs`), so DM's generated `GAS_ID_*` numbers and the arena agree without
/// any lookup at call time.
fn install_gases(mut gases: Vec<GasType>) -> Result<()> {
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
	*GAS_SPECIFIC_HEATS.write() = Some(gases.iter().map(|g| g.specific_heat).collect());
	*GAS_INFO_BY_IDX.write() = Some(gases);
	TOTAL_NUM_GASES.store(super::ids::GAS_COUNT, Ordering::Release);
	Ok(())
}

/// Registers gases, and get reaction infos for auxmos, only call when ssair is initing.
#[auxmacros::bind("/proc/auxtools_atmos_init")]
fn hook_init(gas_data: ByondValue) -> Result<ByondValue> {
	let data = gas_data.read_var_id(byond_string!("datums"))?;
	let gases = data
		.iter()?
		.map(|(_, gas)| {
			let path = gas.read_string_id(byond_string!("id"))?;
			let idx = super::ids::gas_id_for_path(&path)
				.ok_or_else(|| eyre::eyre!("{path} has no ID in verdigris gas/ids.rs"))?;
			// DM sets /datum/gas/var/idx from the generated GAS_ID_* define.
			if let Ok(dm_idx) = gas.read_number_id(byond_string!("idx")) {
				if dm_idx as GasIDX != idx {
					return Err(eyre::eyre!(
						"{path}: DM idx {dm_idx} disagrees with GAS_PATHS ID {idx}"
					));
				}
			}
			GasType::new(&gas, idx)
		})
		.collect::<Result<Vec<_>>>()
		.wrap_err("auxtools_atmos_init failed to register gas")?;
	install_gases(gases)?;
	*REACTION_INFO.write() = Some(get_reaction_info());
	Ok(true.into())
}

fn get_reaction_info() -> BTreeMap<ReactionPriority, Reaction> {
	let gas_reactions = ByondValue::new_global_ref()
		.read_var_id(byond_string!("SSair"))
		.unwrap()
		.read_var_id(byond_string!("gas_reactions"))
		.unwrap();
	let mut reaction_cache: BTreeMap<ReactionPriority, Reaction> = Default::default();
	let sender = byond_callback_sender();
	for (reaction, _) in gas_reactions.iter().unwrap() {
		match Reaction::from_byond_reaction(reaction) {
			Ok(reaction) => {
				if let std::collections::btree_map::Entry::Vacant(e) =
					reaction_cache.entry(reaction.get_priority())
				{
					e.insert(reaction);
				} else {
					drop(sender.try_send(Box::new(move || {
						Err(eyre::eyre!(format!(
							"Duplicate reaction priority {}, this reaction will be ignored!",
							reaction.get_priority().0
						)))
					})));
				}
			}
			//maybe awful error handling
			Err(runtime) => {
				drop(sender.try_send(Box::new(move || Err(runtime))));
			}
		}
	}
	reaction_cache
}

/// For updating reaction informations for auxmos, only call this when it is changed.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxtools_update_reactions")]
fn update_reactions() -> Result<ByondValue> {
	*REACTION_INFO.write() = Some(get_reaction_info());
	Ok(true.into())
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

/// Runs the given closure with the global specific heats vector locked.
/// # Panics
/// If gas info isn't loaded yet.
pub fn with_specific_heats<T>(f: impl FnOnce(&[f32]) -> T) -> T {
	f(GAS_SPECIFIC_HEATS.read().as_ref().unwrap().as_slice())
}

/// Returns the total number of gases in use. Only used by gas mixtures; should probably stay that way.
pub fn total_num_gases() -> GasIDX {
	TOTAL_NUM_GASES.load(Ordering::Acquire)
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
		.get(idx)
		.unwrap()
		.moles_visible
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
/// # Panics
/// If gas info is not loaded yet.
pub fn update_gas_refs() {
	GAS_INFO_BY_IDX
		.write()
		.as_mut()
		.unwrap_or_else(|| panic!("Gases not loaded yet! Uh oh!"))
		.iter_mut()
		.for_each(|gas| {
			if let Some(FireProductInfo::Generic(products)) = gas.fire_products.as_mut() {
				for product in products.iter_mut() {
					product.0.update().unwrap();
				}
			}
		});
}
/// For updating reagent gas fire products, do not use for now.
#[auxmacros::bind("/proc/finalize_gas_refs")]
fn finalize_gas_refs() -> Result<ByondValue> {
	update_gas_refs();
	Ok(ByondValue::null())
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

/// The gas index for a numeric `GAS_ID_*` value passed from DM.
/// # Errors
/// If the value is not a number or not a registered gas ID.
pub fn gas_idx_from_value(value: &ByondValue) -> Result<GasIDX> {
	let raw = value
		.get_number()
		.map_err(|_| eyre::eyre!("gas IDs are numbers (GAS_ID_*), got {value:?}"))?;
	let idx = raw as GasIDX;
	if raw < 0.0 || raw.fract() != 0.0 || idx >= total_num_gases() {
		return Err(eyre::eyre!("Invalid gas ID: {raw}"));
	}
	Ok(idx)
}

#[cfg(test)]
pub fn register_gas_manually(gas_id: &'static str, specific_heat: f32) {
	let gas_cache = GasType {
		idx: total_num_gases(),
		id: gas_id.into(),
		name: gas_id.into(),
		flags: 0,
		specific_heat,
		fusion_power: 0.0,
		moles_visible: None,
		enthalpy: 0.0,
		fire_radiation_released: 0.0,
		fire_info: FireInfo::None,
		fire_products: None,
	};
	GAS_SPECIFIC_HEATS
		.write()
		.as_mut()
		.unwrap()
		.push(gas_cache.specific_heat);
	GAS_INFO_BY_IDX.write().as_mut().unwrap().push(gas_cache);
	TOTAL_NUM_GASES.fetch_add(1, Ordering::Release); // this is the only thing that stores it other than shutdown
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
