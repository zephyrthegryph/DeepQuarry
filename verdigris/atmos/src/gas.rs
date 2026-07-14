#[allow(dead_code)]
pub mod constants;
pub mod mixture;
pub mod types;

use byondapi::prelude::*;
use eyre::Result;
pub use mixture::Mixture;
use parking_lot::{const_rwlock, RwLock};
use rustc_hash::FxHashMap;
use std::sync::atomic::{AtomicU64, Ordering};
pub use types::*;

pub type GasIDX = usize;

/// A static container, with a bunch of helper functions for accessing global data. It's horrible, I know, but video games.
pub struct GasArena {}

/*
	This is where the gases live.
	This is just a big vector, acting as a gas mixture pool.
	As you can see, it can be accessed by any thread at any time;
	of course, it has a RwLock preventing this, and you can't access the
	vector directly. Seriously, please don't. I have the wrapper functions for a reason.
*/
static GAS_MIXTURES: RwLock<Option<Vec<RwLock<Mixture>>>> = const_rwlock(None);

static NEXT_GAS_IDS: RwLock<Option<Vec<usize>>> = const_rwlock(None);
static GAS_REVISIONS: RwLock<Option<Vec<AtomicU64>>> = const_rwlock(None);
static GAS_PUBLICATION: RwLock<()> = const_rwlock(());
static DIRTY_GAS_MIXTURES: RwLock<Option<FxHashMap<usize, u8>>> = const_rwlock(None);
static DIRTY_GAS_BASELINES: RwLock<Option<FxHashMap<usize, GasChangeSignature>>> =
	const_rwlock(None);
const PRESSURE_DIRTY_EPSILON: f32 = 0.1;
const TEMPERATURE_DIRTY_EPSILON: f32 = 0.1;
const COMPOSITION_DIRTY_EPSILON: f32 = 0.001;
pub const GAS_CHANGE_PRESSURE: u8 = 1;
pub const GAS_CHANGE_TEMPERATURE: u8 = 2;
pub const GAS_CHANGE_COMPOSITION: u8 = 4;

#[derive(Clone)]
pub(crate) struct GasChangeSignature {
	pressure: f32,
	temperature: f32,
	composition: Vec<f32>,
}

#[byondapi::init]
pub fn initialize_gases() {
	*GAS_MIXTURES.write() = Some(Vec::with_capacity(240_000));
	*NEXT_GAS_IDS.write() = Some(Vec::with_capacity(2000));
	*GAS_REVISIONS.write() = Some(Vec::with_capacity(240_000));
	*DIRTY_GAS_MIXTURES.write() = Some(FxHashMap::default());
	*DIRTY_GAS_BASELINES.write() = Some(FxHashMap::default());
}

pub fn shut_down_gases() {
	crate::turfs::wait_for_tasks();
	GAS_MIXTURES.write().as_mut().unwrap().clear();
	NEXT_GAS_IDS.write().as_mut().unwrap().clear();
	GAS_REVISIONS.write().as_mut().unwrap().clear();
	DIRTY_GAS_MIXTURES.write().as_mut().unwrap().clear();
	DIRTY_GAS_BASELINES.write().as_mut().unwrap().clear();
}

impl GasArena {
	pub fn snapshot_mixtures_into(
		ids: &[usize],
		snapshot: &mut Vec<RwLock<Mixture>>,
		revisions: &mut Vec<u64>,
	) {
		let _publication = GAS_PUBLICATION.read();
		let gases = GAS_MIXTURES.read();
		let gases = gases.as_ref().unwrap();
		snapshot.resize_with(gases.len(), Default::default);
		revisions.resize(gases.len(), 0);
		for &id in ids {
			if let (Some(source), Some(target)) = (gases.get(id), snapshot.get(id)) {
				loop {
					let revision_before = Self::revision(id);
					let copied = source.read().clone();
					let revision_after = Self::revision(id);
					if revision_before == revision_after {
						*target.write() = copied;
						revisions[id] = revision_after;
						break;
					}
				}
			}
		}
	}

	/// Publishes a transaction only when none of its input mixtures changed while
	/// the worker was computing. The publication lock makes the set visible to DM
	/// readers as one generation.
	pub fn publish_snapshot(
		ids: &[usize],
		base_revisions: &[u64],
		snapshot: &[RwLock<Mixture>],
	) -> Option<Vec<usize>> {
		let _publication = GAS_PUBLICATION.write();
		if ids
			.iter()
			.any(|&id| base_revisions.get(id).copied().unwrap_or_default() != Self::revision(id))
		{
			for &id in ids {
				crate::turfs::mark_mix_active(id);
			}
			return None;
		}
		let gases = GAS_MIXTURES.read();
		let gases = gases.as_ref().unwrap();
		let mut changed = Vec::new();
		for &id in ids {
			if let (Some(source), Some(target)) = (snapshot.get(id), gases.get(id)) {
				let source = source.read();
				let mut target = target.write();
				let before = Self::change_signature(&target);
				if source.compare(&target) > crate::constants::GAS_MIN_MOLES
					|| source.temperature_compare(&target)
				{
					*target = source.clone();
					changed.push(id);
					Self::bump_revision(id);
					Self::mark_dirty_if_changed(id, before, Self::change_signature(&target));
				}
			}
		}
		Some(changed)
	}

	pub fn revision(id: usize) -> u64 {
		GAS_REVISIONS
			.read()
			.as_ref()
			.and_then(|revisions| revisions.get(id))
			.map_or(0, |revision| revision.load(Ordering::Acquire))
	}

	pub fn bump_revision(id: usize) {
		if let Some(revision) = GAS_REVISIONS
			.read()
			.as_ref()
			.and_then(|revisions| revisions.get(id))
		{
			revision.fetch_add(1, Ordering::AcqRel);
		}
		crate::turfs::mark_mix_active(id);
	}

	pub(crate) fn change_signature(mixture: &Mixture) -> GasChangeSignature {
		GasChangeSignature {
			pressure: mixture.return_pressure(),
			temperature: mixture.get_temperature(),
			composition: mixture.composition_moles(),
		}
	}

	pub(crate) fn mark_dirty_if_changed(
		id: usize,
		before: GasChangeSignature,
		after: GasChangeSignature,
	) {
		let mut baselines = DIRTY_GAS_BASELINES.write();
		let baseline = baselines
			.as_mut()
			.expect("dirty gas baselines are not initialized")
			.entry(id)
			.or_insert(before);
		let mut mask = 0;
		if (baseline.pressure - after.pressure).abs() >= PRESSURE_DIRTY_EPSILON {
			mask |= GAS_CHANGE_PRESSURE;
		}
		if (baseline.temperature - after.temperature).abs() >= TEMPERATURE_DIRTY_EPSILON {
			mask |= GAS_CHANGE_TEMPERATURE;
		}
		let composition_changed = baseline
			.composition
			.iter()
			.zip(after.composition.iter())
			.any(|(old, new)| (old - new).abs() >= COMPOSITION_DIRTY_EPSILON)
			|| baseline.composition.len() != after.composition.len()
				&& baseline
					.composition
					.iter()
					.skip(after.composition.len())
					.chain(after.composition.iter().skip(baseline.composition.len()))
					.any(|moles| moles.abs() >= COMPOSITION_DIRTY_EPSILON);
		if composition_changed {
			mask |= GAS_CHANGE_COMPOSITION;
		}
		if mask == 0 {
			return;
		}
		if mask & GAS_CHANGE_PRESSURE != 0 {
			baseline.pressure = after.pressure;
		}
		if mask & GAS_CHANGE_TEMPERATURE != 0 {
			baseline.temperature = after.temperature;
		}
		if mask & GAS_CHANGE_COMPOSITION != 0 {
			baseline.composition = after.composition;
		}
		drop(baselines);
		Self::mark_dirty(id, mask);
	}

	fn mark_dirty(id: usize, mask: u8) {
		if let Some(dirty) = DIRTY_GAS_MIXTURES.write().as_mut() {
			*dirty.entry(id).or_default() |= mask;
		}
	}

	pub fn take_dirty_mixtures() -> Vec<(usize, u8)> {
		DIRTY_GAS_MIXTURES
			.write()
			.as_mut()
			.map(|dirty| std::mem::take(dirty).into_iter().collect())
			.unwrap_or_default()
	}
	/// Locks the gas arena and and runs the given closure with it locked.
	/// # Panics
	/// if `GAS_MIXTURES` hasn't been initialized, somehow.
	pub fn with_all_mixtures<T, F>(f: F) -> T
	where
		F: FnOnce(&[RwLock<Mixture>]) -> T,
	{
		let _publication = GAS_PUBLICATION.read();
		f(GAS_MIXTURES.read().as_ref().unwrap())
	}

	/// Locks the gas arena and and runs the given closure with it locked, fails if it can't acquire a lock in 30ms.
	/// # Panics
	/// if `GAS_MIXTURES` hasn't been initialized, somehow.
	pub fn with_all_mixtures_fallible<T, F>(f: F) -> T
	where
		F: FnOnce(Option<&[RwLock<Mixture>]>) -> T,
	{
		let _publication = GAS_PUBLICATION.read();
		let gases = GAS_MIXTURES.try_read_for(std::time::Duration::from_millis(30));
		f(gases.as_ref().unwrap().as_ref().map(|vec| vec.as_slice()))
	}
	/// Read locks the given gas mixture and runs the given closure on it.
	/// # Errors
	/// If no such gas mixture exists or the closure itself errors.
	/// # Panics
	/// if `GAS_MIXTURES` hasn't been initialized, somehow.
	pub fn with_gas_mixture<T, F>(id: usize, f: F) -> Result<T>
	where
		F: FnOnce(&Mixture) -> Result<T>,
	{
		let _publication = GAS_PUBLICATION.read();
		let lock = GAS_MIXTURES.read();
		let gas_mixtures = lock.as_ref().unwrap();
		let mix = gas_mixtures
			.get(id)
			.ok_or_else(|| eyre::eyre!("No gas mixture with ID {id} exists!"))?
			.read();
		f(&mix)
	}
	/// Write locks the given gas mixture and runs the given closure on it.
	/// # Errors
	/// If no such gas mixture exists or the closure itself errors.
	/// # Panics
	/// if `GAS_MIXTURES` hasn't been initialized, somehow.
	pub fn with_gas_mixture_mut<T, F>(id: usize, f: F) -> Result<T>
	where
		F: FnOnce(&mut Mixture) -> Result<T>,
	{
		let _publication = GAS_PUBLICATION.read();
		Self::bump_revision(id);
		let lock = GAS_MIXTURES.read();
		let gas_mixtures = lock.as_ref().unwrap();
		let mut mix = gas_mixtures
			.get(id)
			.ok_or_else(|| eyre::eyre!("No gas mixture with ID {id} exists!"))?
			.write();
		let before = Self::change_signature(&mix);
		let result = f(&mut mix);
		let after = Self::change_signature(&mix);
		drop(mix);
		Self::bump_revision(id);
		Self::mark_dirty_if_changed(id, before, after);
		result
	}
	/// Read locks the given gas mixtures and runs the given closure on them.
	/// # Errors
	/// If no such gas mixture exists or the closure itself errors.
	/// # Panics
	/// if `GAS_MIXTURES` hasn't been initialized, somehow.
	pub fn with_gas_mixtures<T, F>(src: usize, arg: usize, f: F) -> Result<T>
	where
		F: FnOnce(&Mixture, &Mixture) -> Result<T>,
	{
		let _publication = GAS_PUBLICATION.read();
		let lock = GAS_MIXTURES.read();
		let gas_mixtures = lock.as_ref().unwrap();
		let src_gas = gas_mixtures
			.get(src)
			.ok_or_else(|| eyre::eyre!("No gas mixture with ID {src} exists!"))?
			.read();
		let arg_gas = gas_mixtures
			.get(arg)
			.ok_or_else(|| eyre::eyre!("No gas mixture with ID {arg} exists!"))?
			.read();
		f(&src_gas, &arg_gas)
	}
	/// Locks the given gas mixtures and runs the given closure on them.
	/// # Errors
	/// If no such gas mixture exists or the closure itself errors.
	/// # Panics
	/// if `GAS_MIXTURES` hasn't been initialized, somehow.
	pub fn with_gas_mixtures_mut<T, F>(src: usize, arg: usize, f: F) -> Result<T>
	where
		F: FnOnce(&mut Mixture, &mut Mixture) -> Result<T>,
	{
		let _publication = GAS_PUBLICATION.read();
		Self::bump_revision(src);
		if src != arg {
			Self::bump_revision(arg);
		}
		let lock = GAS_MIXTURES.read();
		let gas_mixtures = lock.as_ref().unwrap();
		let src_before = Self::change_signature(
			&gas_mixtures
				.get(src)
				.ok_or_else(|| eyre::eyre!("No gas mixture with ID {src} exists!"))?
				.read(),
		);
		let arg_before = Self::change_signature(
			&gas_mixtures
				.get(arg)
				.ok_or_else(|| eyre::eyre!("No gas mixture with ID {arg} exists!"))?
				.read(),
		);
		let result = if src == arg {
			let mut entry = gas_mixtures
				.get(src)
				.ok_or_else(|| eyre::eyre!("No gas mixture with ID {src} exists!"))?
				.write();
			let mix = &mut entry;
			let mut copied = mix.clone();
			f(mix, &mut copied)
		} else {
			f(
				&mut gas_mixtures
					.get(src)
					.ok_or_else(|| eyre::eyre!("No gas mixture with ID {src} exists!"))?
					.write(),
				&mut gas_mixtures
					.get(arg)
					.ok_or_else(|| eyre::eyre!("No gas mixture with ID {arg} exists!"))?
					.write(),
			)
		};
		Self::bump_revision(src);
		let src_after = Self::change_signature(&gas_mixtures.get(src).unwrap().read());
		Self::mark_dirty_if_changed(src, src_before, src_after);
		if src != arg {
			Self::bump_revision(arg);
			let arg_after = Self::change_signature(&gas_mixtures.get(arg).unwrap().read());
			Self::mark_dirty_if_changed(arg, arg_before, arg_after);
		}
		result
	}
	/// Runs the given closure on the gas mixture *locks* rather than an already-locked version.
	/// # Errors
	/// If no such gas mixture exists or the closure itself errors.
	/// # Panics
	/// if `GAS_MIXTURES` hasn't been initialized, somehow.
	fn with_gas_mixtures_custom<T, F>(src: usize, arg: usize, f: F) -> Result<T>
	where
		F: FnOnce(&RwLock<Mixture>, &RwLock<Mixture>) -> Result<T>,
	{
		let _publication = GAS_PUBLICATION.read();
		Self::bump_revision(src);
		if src != arg {
			Self::bump_revision(arg);
		}
		let lock = GAS_MIXTURES.read();
		let gas_mixtures = lock.as_ref().unwrap();
		let src_before = Self::change_signature(
			&gas_mixtures
				.get(src)
				.ok_or_else(|| eyre::eyre!("No gas mixture with ID {src} exists!"))?
				.read(),
		);
		let arg_before = Self::change_signature(
			&gas_mixtures
				.get(arg)
				.ok_or_else(|| eyre::eyre!("No gas mixture with ID {arg} exists!"))?
				.read(),
		);
		let result = if src == arg {
			let entry = gas_mixtures
				.get(src)
				.ok_or_else(|| eyre::eyre!("No gas mixture with ID {src} exists!"))?;
			let gas_copy = entry.read().clone();
			f(entry, &RwLock::new(gas_copy))
		} else {
			f(
				gas_mixtures
					.get(src)
					.ok_or_else(|| eyre::eyre!("No gas mixture with ID {src} exists!"))?,
				gas_mixtures
					.get(arg)
					.ok_or_else(|| eyre::eyre!("No gas mixture with ID {arg} exists!"))?,
			)
		};
		Self::bump_revision(src);
		let src_after = Self::change_signature(&gas_mixtures.get(src).unwrap().read());
		Self::mark_dirty_if_changed(src, src_before, src_after);
		if src != arg {
			Self::bump_revision(arg);
			let arg_after = Self::change_signature(&gas_mixtures.get(arg).unwrap().read());
			Self::mark_dirty_if_changed(arg, arg_before, arg_after);
		}
		result
	}
	/// Fills in the first unused slot in the gas mixtures vector, or adds another one, then sets the argument ByondValue to point to it.
	/// # Errors
	/// If `initial_volume` is incorrect or `_extools_pointer_gasmixture` doesn't exist, somehow.
	/// # Panics
	/// If not called from the main thread
	/// If `NEXT_GAS_IDS` is not initialized, somehow.
	pub fn register_mix(mut mix: ByondValue) -> Result<ByondValue> {
		let init_volume = mix.read_number_id(byond_string!("initial_volume"))?;
		if NEXT_GAS_IDS.read().as_ref().unwrap().is_empty() {
			let mut gas_lock = GAS_MIXTURES.write();
			let gas_mixtures = gas_lock.as_mut().unwrap();
			let next_idx = gas_mixtures.len();
			gas_mixtures.push(RwLock::new(Mixture::from_vol(init_volume)));
			GAS_REVISIONS
				.write()
				.as_mut()
				.unwrap()
				.push(AtomicU64::new(1));

			mix.write_var_id(
				byond_string!("_extools_pointer_gasmixture"),
				&(next_idx as f32).into(),
			)
			.unwrap();

			let mut ids_lock = NEXT_GAS_IDS.write();
			let cur_last = gas_mixtures.len();
			let next_gas_ids = ids_lock.as_mut().unwrap();
			let cap = {
				let to_cap = gas_mixtures.capacity() - cur_last;
				if to_cap == 0 {
					next_gas_ids.capacity() - 100
				} else {
					(next_gas_ids.capacity() - 100).min(to_cap)
				}
			};
			next_gas_ids.extend(cur_last..(cur_last + cap));
			gas_mixtures.resize_with(cur_last + cap, Default::default);
			GAS_REVISIONS
				.write()
				.as_mut()
				.unwrap()
				.resize_with(cur_last + cap, || AtomicU64::new(0));
		} else {
			let idx = {
				let mut next_gas_ids = NEXT_GAS_IDS.write();
				next_gas_ids.as_mut().unwrap().pop().unwrap()
			};
			GAS_MIXTURES
				.read()
				.as_ref()
				.unwrap()
				.get(idx)
				.unwrap()
				.write()
				.clear_with_vol(init_volume);
			DIRTY_GAS_BASELINES.write().as_mut().unwrap().remove(&idx);
			Self::bump_revision(idx);
			Self::mark_dirty(
				idx,
				GAS_CHANGE_PRESSURE | GAS_CHANGE_TEMPERATURE | GAS_CHANGE_COMPOSITION,
			);
			mix.write_var_id(
				byond_string!("_extools_pointer_gasmixture"),
				&(idx as f32).into(),
			)
			.unwrap();
		}
		Ok(ByondValue::null())
	}
	/// Marks the ByondValue's gas mixture as unused, allowing it to be reallocated to another.
	/// # Panics
	/// If not called from the main thread
	/// If `NEXT_GAS_IDS` hasn't been initialized, somehow.
	pub fn unregister_mix(mix: &ByondValue) {
		if let Ok(idx) = mix.read_number_id(byond_string!("_extools_pointer_gasmixture")) {
			DIRTY_GAS_BASELINES
				.write()
				.as_mut()
				.unwrap()
				.remove(&(idx as usize));
			Self::bump_revision(idx as usize);
			Self::mark_dirty(
				idx as usize,
				GAS_CHANGE_PRESSURE | GAS_CHANGE_TEMPERATURE | GAS_CHANGE_COMPOSITION,
			);
			let mut next_gas_ids = NEXT_GAS_IDS.write();
			next_gas_ids.as_mut().unwrap().push(idx as usize);
		} else {
			panic!("Tried to unregister uninitialized mix")
		}
	}
}

/// Gets the mix for the given value, and calls the provided closure with a reference to that mix as an argument.
/// # Errors
/// If a gasmixture ID is not a number or the callback returns an error.
pub fn with_mix<T, F>(mix: &ByondValue, f: F) -> Result<T>
where
	F: FnOnce(&Mixture) -> Result<T>,
{
	GasArena::with_gas_mixture(
		mix.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize,
		f,
	)
}

#[byondapi::bind("/datum/gas_mixture/proc/revision")]
#[auxmacros::panic_safe]
fn hook_mix_revision(src: ByondValue) -> Result<ByondValue> {
	let id = src.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize;
	Ok((GasArena::revision(id) as f32).into())
}

/// As `with_mix`, but mutable.
/// # Errors
/// If a gasmixture ID is not a number or the callback returns an error.
pub fn with_mix_mut<T, F>(mix: &ByondValue, f: F) -> Result<T>
where
	F: FnOnce(&mut Mixture) -> Result<T>,
{
	GasArena::with_gas_mixture_mut(
		mix.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize,
		f,
	)
}

/// As `with_mix`, but with two mixes.
/// # Errors
/// If a gasmixture ID is not a number or the callback returns an error.
pub fn with_mixes<T, F>(src_mix: &ByondValue, arg_mix: &ByondValue, f: F) -> Result<T>
where
	F: FnOnce(&Mixture, &Mixture) -> Result<T>,
{
	GasArena::with_gas_mixtures(
		src_mix.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize,
		arg_mix.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize,
		f,
	)
}

/// As `with_mix_mut`, but with two mixes.
/// # Errors
/// If a gasmixture ID is not a number or the callback returns an error.
pub fn with_mixes_mut<T, F>(src_mix: &ByondValue, arg_mix: &ByondValue, f: F) -> Result<T>
where
	F: FnOnce(&mut Mixture, &mut Mixture) -> Result<T>,
{
	GasArena::with_gas_mixtures_mut(
		src_mix.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize,
		arg_mix.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize,
		f,
	)
}

/// Allows different lock levels for each gas. Instead of relevant refs to the gases, returns the `RWLock` object.
/// # Errors
/// If a gasmixture ID is not a number or the callback returns an error.
pub fn with_mixes_custom<T, F>(src_mix: &ByondValue, arg_mix: &ByondValue, f: F) -> Result<T>
where
	F: FnMut(&RwLock<Mixture>, &RwLock<Mixture>) -> Result<T>,
{
	GasArena::with_gas_mixtures_custom(
		src_mix.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize,
		arg_mix.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize,
		f,
	)
}

/// Gets the amount of gases that are active in byond.
/// # Panics
/// if `GAS_MIXTURES` hasn't been initialized, somehow.
pub fn amt_gases() -> usize {
	GAS_MIXTURES.read().as_ref().unwrap().len() - NEXT_GAS_IDS.read().as_ref().unwrap().len()
}

/// Gets the amount of gases that are allocated, but not necessarily active in byond.
/// # Panics
/// if `GAS_MIXTURES` hasn't been initialized, somehow.
pub fn tot_gases() -> usize {
	GAS_MIXTURES.read().as_ref().unwrap().len()
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::gas::types::{destroy_gas_statics, register_gas_manually, set_gas_statics_manually};

	#[test]
	fn snapshot_rejects_concurrent_mutation_and_publishes_stable_state() {
		set_gas_statics_manually();
		register_gas_manually("test", 20.0);
		register_gas_manually("test2", 20.0);
		initialize_gases();
		crate::turfs::initialize_turfs();
		let mut initial = Mixture::from_vol(2_500.0);
		initial.set_moles(0, 1.0);
		GAS_MIXTURES
			.write()
			.as_mut()
			.unwrap()
			.push(RwLock::new(initial));
		GAS_REVISIONS
			.write()
			.as_mut()
			.unwrap()
			.push(AtomicU64::new(0));

		let mut snapshot = Vec::new();
		let mut revisions = Vec::new();
		GasArena::snapshot_mixtures_into(&[0], &mut snapshot, &mut revisions);
		GasArena::with_gas_mixture_mut(0, |mixture| {
			mixture.set_moles(0, 10.0);
			Ok(())
		})
		.unwrap();
		assert_eq!(
			GasArena::take_dirty_mixtures(),
			vec![(0, GAS_CHANGE_COMPOSITION)]
		);
		assert!(GasArena::take_dirty_mixtures().is_empty());
		snapshot[0].write().set_moles(0, 5.0);
		assert!(GasArena::publish_snapshot(&[0], &revisions, &snapshot).is_none());
		assert_eq!(
			GasArena::with_gas_mixture(0, |mixture| Ok(mixture.get_moles(0))).unwrap(),
			10.0
		);

		GasArena::snapshot_mixtures_into(&[0], &mut snapshot, &mut revisions);
		snapshot[0].write().set_moles(0, 20.0);
		assert!(GasArena::publish_snapshot(&[0], &revisions, &snapshot).is_some());
		assert_eq!(
			GasArena::with_gas_mixture(0, |mixture| Ok(mixture.get_moles(0))).unwrap(),
			20.0
		);
		GasArena::take_dirty_mixtures();
		GasArena::with_gas_mixture_mut(0, |mixture| {
			mixture.set_moles(0, 0.0);
			mixture.set_moles(1, 20.0);
			Ok(())
		})
		.unwrap();
		assert_eq!(
			GasArena::take_dirty_mixtures(),
			vec![(0, GAS_CHANGE_COMPOSITION)]
		);
		for step in 1..=4 {
			GasArena::with_gas_mixture_mut(0, |mixture| {
				mixture.set_moles(1, 20.0 + step as f32 * 0.0002);
				Ok(())
			})
			.unwrap();
			assert!(GasArena::take_dirty_mixtures().is_empty());
		}
		GasArena::with_gas_mixture_mut(0, |mixture| {
			mixture.set_moles(1, 20.0012);
			Ok(())
		})
		.unwrap();
		assert_eq!(
			GasArena::take_dirty_mixtures(),
			vec![(0, GAS_CHANGE_COMPOSITION)]
		);
		destroy_gas_statics();
	}
}
