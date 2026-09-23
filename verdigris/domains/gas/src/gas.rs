#[allow(dead_code)]
pub mod constants;
pub mod ids;
pub mod mixture;
pub mod types;

use crate::GAS_MIN_MOLES;
use byondapi::prelude::*;
use eyre::Result;
pub use ids::*;
pub use mixture::Mixture;
use parking_lot::{const_mutex, const_rwlock, Mutex, MutexGuard, RwLock};
use rustc_hash::FxHashMap;
use std::sync::atomic::{AtomicU64, Ordering};
pub use types::*;

pub type GasIDX = usize;

/// A static container, with a bunch of helper functions for accessing global data. It's horrible, I know, but video games.
pub struct GasArena {}

pub(crate) trait MixtureLookup {
	fn mixture(&self, id: usize) -> Option<&RwLock<Mixture>>;
}

impl MixtureLookup for [RwLock<Mixture>] {
	fn mixture(&self, id: usize) -> Option<&RwLock<Mixture>> {
		self.get(id)
	}
}

#[derive(Default)]
pub(crate) struct MixtureSnapshot {
	mixtures: Vec<RwLock<Mixture>>,
	slots: Vec<usize>,
	ids: Vec<usize>,
	revisions: Vec<u64>,
}

pub(crate) struct SnapshotPublication {
	pub changed: Vec<usize>,
	pub published: rustc_hash::FxHashSet<usize>,
	pub rejected: rustc_hash::FxHashSet<usize>,
}

impl MixtureSnapshot {
	fn prepare(&mut self, arena_len: usize, ids: &[usize]) {
		for &id in &self.ids {
			if let Some(slot) = self.slots.get_mut(id) {
				*slot = usize::MAX;
			}
		}
		self.mixtures.clear();
		self.ids.clear();
		self.revisions.clear();
		self.slots.resize(arena_len, usize::MAX);
		self.mixtures.reserve(ids.len());
		self.ids.reserve(ids.len());
		self.revisions.reserve(ids.len());
		for &id in ids {
			if id >= arena_len || self.slots[id] != usize::MAX {
				continue;
			}
			self.slots[id] = self.mixtures.len();
			self.mixtures.push(Default::default());
			self.ids.push(id);
			self.revisions.push(0);
		}
	}

	fn slot(&self, id: usize) -> Option<usize> {
		self.slots
			.get(id)
			.copied()
			.filter(|&slot| slot != usize::MAX)
	}

	pub(crate) fn get(&self, id: usize) -> Option<&RwLock<Mixture>> {
		self.slot(id).and_then(|slot| self.mixtures.get(slot))
	}

	fn revision(&self, id: usize) -> Option<u64> {
		self.slot(id)
			.and_then(|slot| self.revisions.get(slot).copied())
	}

	fn set_revision(&mut self, id: usize, revision: u64) {
		if let Some(slot) = self.slot(id) {
			self.revisions[slot] = revision;
		}
	}

	pub(crate) fn release_values(&mut self) {
		self.mixtures.clear();
		self.revisions.clear();
	}
}

impl MixtureLookup for MixtureSnapshot {
	fn mixture(&self, id: usize) -> Option<&RwLock<Mixture>> {
		self.get(id)
	}
}

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
/// One authoritative gas writer at a time. The async turf solver holds this
/// from snapshot through publication; synchronous machine/DM transactions take
/// the same gate before changing mixtures. Reads remain concurrent. This makes
/// snapshot rejection an exceptional topology event instead of the normal
/// outcome of machines racing diffusion.
static GAS_MUTATION_GATE: Mutex<()> = const_mutex(());
static DIRTY_GAS_MIXTURES: RwLock<Option<FxHashMap<usize, u8>>> = const_rwlock(None);
/// Mixtures with a sleeping DM device subscribed to their change notifications.
/// Keeping this in Rust prevents constructing enormous BYOND lists for irrelevant turf gases.
static WATCHED_GAS_MIXTURES: RwLock<Option<FxHashMap<usize, u8>>> = const_rwlock(None);
static DIRTY_GAS_BASELINES: RwLock<Option<FxHashMap<usize, GasChangeSignature>>> =
	const_rwlock(None);
// Gas mixtures are the largest dense arena in the 32-bit DreamDaemon process.
// Letting Vec grow geometrically near the end of map initialization can double
// a ~450K-slot arena merely because the map estimate was a few percent low.
// Grow in bounded exact chunks instead so unused address space remains
// available for BYOND's atoms and explosion temporaries.
const GAS_ARENA_GROWTH: usize = 4_096;

fn grow_gas_storage(
	mixtures: &mut Vec<RwLock<Mixture>>,
	revisions: &mut Vec<AtomicU64>,
	free_ids: &mut Vec<usize>,
	initial_volume: f32,
) -> usize {
	let next_idx = mixtures.len();
	mixtures.reserve_exact(GAS_ARENA_GROWTH);
	revisions.reserve_exact(GAS_ARENA_GROWTH);
	mixtures.push(RwLock::new(Mixture::from_vol(initial_volume)));
	revisions.push(AtomicU64::new(1));
	let chunk_end = next_idx.saturating_add(GAS_ARENA_GROWTH);
	mixtures.resize_with(chunk_end, Default::default);
	revisions.resize_with(chunk_end, || AtomicU64::new(0));
	free_ids.reserve_exact(GAS_ARENA_GROWTH.saturating_sub(1));
	free_ids.extend((next_idx + 1)..chunk_end);
	next_idx
}
// Dependency notifications are gameplay predicates, not a mirror of every
// solver float. These match the tightest consumers (vents stop at 0.5 kPa and
// air-alarm temperature control stops within 0.5 K); smaller solver movement is
// accumulated in the baseline until it becomes material. 0.01 mol is far below
// the smallest alarm partial-pressure threshold at turf volume.
const PRESSURE_DIRTY_EPSILON: f32 = 0.5;
const TEMPERATURE_DIRTY_EPSILON: f32 = 0.5;
const COMPOSITION_DIRTY_EPSILON: f32 = 0.01;
// Dirty-mixture change bits. `@dm-define` exports each one to the generated
// DM bindings, where machinery interest masks use them.
/// @dm-define GAS_DEPENDENCY_PRESSURE
pub const GAS_CHANGE_PRESSURE: u8 = 1;
/// @dm-define GAS_DEPENDENCY_TEMPERATURE
pub const GAS_CHANGE_TEMPERATURE: u8 = 2;
/// @dm-define GAS_DEPENDENCY_COMPOSITION
pub const GAS_CHANGE_COMPOSITION: u8 = 4;

#[derive(Clone)]
pub(crate) struct GasChangeSignature {
	pressure: f32,
	temperature: f32,
	composition: Vec<f32>,
}

#[byondapi::init]
pub fn initialize_gases() {
	*GAS_MIXTURES.write() = Some(Vec::with_capacity(4096));
	*NEXT_GAS_IDS.write() = Some(Vec::with_capacity(2000));
	*GAS_REVISIONS.write() = Some(Vec::with_capacity(4096));
	*DIRTY_GAS_MIXTURES.write() = Some(FxHashMap::default());
	*WATCHED_GAS_MIXTURES.write() = Some(FxHashMap::default());
	*DIRTY_GAS_BASELINES.write() = Some(FxHashMap::default());
}

pub(crate) fn reserve_gas_capacity(target: usize) {
	let mut mixtures = GAS_MIXTURES.write();
	let mixtures = mixtures.as_mut().unwrap();
	mixtures.reserve_exact(target.saturating_sub(mixtures.capacity()));
	let mut revisions = GAS_REVISIONS.write();
	let revisions = revisions.as_mut().unwrap();
	revisions.reserve_exact(target.saturating_sub(revisions.capacity()));
}

pub fn shut_down_gases() {
	crate::turfs::wait_for_tasks();
	GAS_MIXTURES.write().as_mut().unwrap().clear();
	NEXT_GAS_IDS.write().as_mut().unwrap().clear();
	GAS_REVISIONS.write().as_mut().unwrap().clear();
	DIRTY_GAS_MIXTURES.write().as_mut().unwrap().clear();
	WATCHED_GAS_MIXTURES.write().as_mut().unwrap().clear();
	DIRTY_GAS_BASELINES.write().as_mut().unwrap().clear();
}

impl GasArena {
	pub(crate) fn begin_solver_transaction() -> MutexGuard<'static, ()> {
		GAS_MUTATION_GATE.lock()
	}

	/// Publish all pipe-region split/merge results as one arena transaction.
	/// Sources are cloned before any target is overwritten, so a surviving
	/// region may safely reuse its previous public mixture while another child
	/// receives a proportional share from that same pre-commit inventory.
	pub(crate) fn rebalance_pipe_regions(
		recipes: &[(usize, f32, Vec<(usize, f32)>)],
	) -> Result<()> {
		let _single_writer = GAS_MUTATION_GATE.lock();
		let _publication = GAS_PUBLICATION.write();
		let gases = GAS_MIXTURES.read();
		let gases = gases.as_ref().expect("gas arena is initialized");
		let mut source_ids = recipes
			.iter()
			.flat_map(|(_, _, sources)| sources.iter().map(|(source, _)| *source))
			.collect::<Vec<_>>();
		source_ids.sort_unstable();
		source_ids.dedup();
		let mut snapshots = FxHashMap::default();
		for source in source_ids {
			let mixture = gases
				.get(source)
				.ok_or_else(|| eyre::eyre!("No gas mixture with ID {source} exists!"))?
				.read()
				.clone();
			snapshots.insert(source, mixture);
		}

		let mut target_ids = recipes
			.iter()
			.map(|(target, _, _)| *target)
			.collect::<Vec<_>>();
		target_ids.sort_unstable();
		target_ids.dedup();
		if target_ids.len() != recipes.len() {
			eyre::bail!("pipe-region transaction contains a duplicate target mixture");
		}
		for (target, volume, sources) in recipes {
			let entry = gases
				.get(*target)
				.ok_or_else(|| eyre::eyre!("No gas mixture with ID {target} exists!"))?;
			let mut target_mix = entry.write();
			let before = Self::change_signature(&target_mix);
			let mut replacement = Mixture::from_vol(volume.max(1.0));
			for (source, ratio) in sources {
				if *ratio <= 0.0 {
					continue;
				}
				let mut contribution = snapshots
					.get(source)
					.ok_or_else(|| eyre::eyre!("Missing pipe source snapshot {source}"))?
					.clone();
				contribution.multiply(*ratio);
				replacement.merge(&contribution);
			}
			*target_mix = replacement;
			let after = Self::change_signature(&target_mix);
			drop(target_mix);
			if Self::signature_changed(&before, &after) {
				Self::bump_revision_only(*target);
				Self::mark_dirty_if_changed(*target, before, after);
			}
		}
		Ok(())
	}

	pub(crate) fn try_begin_solver_transaction() -> Option<MutexGuard<'static, ()>> {
		GAS_MUTATION_GATE.try_lock()
	}

	/// Equalize every exposed pipe face under one arena publication lock. This is
	/// the exact volume-weighted operation formerly assembled through five FFI
	/// calls per leak in DM. Results indicate which faces still have a material
	/// pressure/composition/temperature residual and therefore need another pass.
	pub(crate) fn batch_mingle(operations: &[(usize, usize, f32)]) -> Vec<bool> {
		let _single_writer = GAS_MUTATION_GATE.lock();
		let _publication = GAS_PUBLICATION.write();
		let gases = GAS_MIXTURES.read();
		let gases = gases.as_ref().expect("gas arena is initialized");
		let mut ids = operations
			.iter()
			.flat_map(|(pipe, environment, _)| [*pipe, *environment])
			.filter(|id| *id < gases.len())
			.collect::<Vec<_>>();
		ids.sort_unstable();
		ids.dedup();
		let slots = ids
			.iter()
			.copied()
			.enumerate()
			.map(|(slot, id)| (id, slot))
			.collect::<rustc_hash::FxHashMap<_, _>>();
		let mut guards = ids
			.iter()
			.map(|&id| (id, gases[id].write()))
			.collect::<Vec<_>>();
		let before = guards
			.iter()
			.map(|(id, gas)| (*id, Self::change_signature(gas)))
			.collect::<rustc_hash::FxHashMap<_, _>>();
		let mut residuals = Vec::with_capacity(operations.len());
		for &(pipe_id, environment_id, share_volume) in operations {
			let (Some(&pipe_slot), Some(&environment_slot)) =
				(slots.get(&pipe_id), slots.get(&environment_id))
			else {
				residuals.push(false);
				continue;
			};
			if pipe_slot == environment_slot || share_volume <= 0.0 {
				residuals.push(false);
				continue;
			}
			let (pipe, environment) = if pipe_slot < environment_slot {
				let (left, right) = guards.split_at_mut(environment_slot);
				(&mut left[pipe_slot].1, &mut right[0].1)
			} else {
				let (left, right) = guards.split_at_mut(pipe_slot);
				(&mut right[0].1, &mut left[environment_slot].1)
			};
			let pipe_volume = pipe.volume.max(1.0);
			let environment_volume = environment.volume.max(1.0);
			let sample = pipe.remove_ratio((share_volume / pipe_volume).clamp(0.0, 1.0));
			environment.merge(&sample);
			let reclaimed = environment
				.remove_ratio((share_volume / (share_volume + environment_volume)).clamp(0.0, 1.0));
			pipe.merge(&reclaimed);

			let pipe_moles = pipe.total_moles();
			let environment_moles = environment.total_moles();
			let pressure_residual =
				(pipe.return_pressure() - environment.return_pressure()).abs() > 0.1;
			let temperature_residual =
				(pipe.get_temperature() - environment.get_temperature()).abs() > 0.1;
			let gas_count = pipe
				.enumerate()
				.count()
				.max(environment.enumerate().count());
			let composition_residual = pipe_moles > GAS_MIN_MOLES
				&& environment_moles > GAS_MIN_MOLES
				&& (0..gas_count).any(|gas| {
					(pipe.get_moles(gas) / pipe_moles
						- environment.get_moles(gas) / environment_moles)
						.abs() > 0.001
				});
			residuals.push(pressure_residual || temperature_residual || composition_residual);
		}
		for (id, gas) in &guards {
			let after = Self::change_signature(gas);
			if let Some(before) = before
				.get(id)
				.filter(|before| Self::signature_changed(before, &after))
			{
				Self::bump_revision_only(*id);
				Self::mark_dirty_if_changed(*id, before.clone(), after);
			}
		}
		residuals
	}

	/// Apply a group of machine transfers under one publication lock. Unique gas
	/// mixtures are locked in arena-ID order, so arbitrary vent/pump ordering can
	/// never deadlock. Requests sharing a source are clamped sequentially to the
	/// authoritative remaining mass and return their actual transferred moles.
	pub(crate) fn batch_transfer(operations: &[(usize, usize, f32)]) -> Vec<f32> {
		let _single_writer = GAS_MUTATION_GATE.lock();
		let _publication = GAS_PUBLICATION.write();
		let gases = GAS_MIXTURES.read();
		let gases = gases.as_ref().expect("gas arena is initialized");
		let mut ids = operations
			.iter()
			.flat_map(|(source, sink, _)| [*source, *sink])
			.filter(|id| *id < gases.len())
			.collect::<Vec<_>>();
		ids.sort_unstable();
		ids.dedup();
		let slots = ids
			.iter()
			.copied()
			.enumerate()
			.map(|(slot, id)| (id, slot))
			.collect::<rustc_hash::FxHashMap<_, _>>();
		let mut guards = ids
			.iter()
			.map(|&id| (id, gases[id].write()))
			.collect::<Vec<_>>();
		let before = guards
			.iter()
			.map(|(id, gas)| (*id, Self::change_signature(gas)))
			.collect::<rustc_hash::FxHashMap<_, _>>();
		let mut transferred = Vec::with_capacity(operations.len());
		for &(source_id, sink_id, requested) in operations {
			let Some(&source_slot) = slots.get(&source_id) else {
				transferred.push(0.0);
				continue;
			};
			let Some(&sink_slot) = slots.get(&sink_id) else {
				transferred.push(0.0);
				continue;
			};
			if source_slot == sink_slot || requested <= 0.0 {
				transferred.push(0.0);
				continue;
			}
			let (source, sink) = if source_slot < sink_slot {
				let (left, right) = guards.split_at_mut(sink_slot);
				(&mut left[source_slot].1, &mut right[0].1)
			} else {
				let (left, right) = guards.split_at_mut(source_slot);
				(&mut right[0].1, &mut left[sink_slot].1)
			};
			let actual = requested.min(source.total_moles()).max(0.0);
			if actual > 0.0 {
				sink.merge(&source.remove(actual));
			}
			transferred.push(actual);
		}
		for (id, gas) in &guards {
			let after = Self::change_signature(gas);
			if let Some(before) = before
				.get(id)
				.filter(|before| Self::signature_changed(before, &after))
			{
				Self::bump_revision_only(*id);
				Self::mark_dirty_if_changed(*id, before.clone(), after);
			}
		}
		transferred
	}

	pub(crate) fn snapshot_mixtures_into(ids: &[usize], snapshot: &mut MixtureSnapshot) {
		let _publication = GAS_PUBLICATION.read();
		let gases = GAS_MIXTURES.read();
		let gases = gases.as_ref().unwrap();
		snapshot.prepare(gases.len(), ids);
		let mut captured_revisions = Vec::with_capacity(ids.len());
		for &id in ids {
			if let (Some(source), Some(target)) = (gases.get(id), snapshot.get(id)) {
				loop {
					let revision_before = Self::revision(id);
					let copied = source.read().clone();
					let revision_after = Self::revision(id);
					if revision_before == revision_after {
						*target.write() = copied;
						captured_revisions.push((id, revision_after));
						break;
					}
				}
			}
		}
		for (id, revision) in captured_revisions {
			snapshot.set_revision(id, revision);
		}
	}

	/// Publishes a transaction only when none of its input mixtures changed while
	/// the worker was computing. The publication lock makes the set visible to DM
	/// readers as one generation.
	/// Publish independent connected components separately. A synchronous DM
	/// mutation invalidates only the component containing that mixture instead of
	/// discarding an unrelated station-wide worker batch.
	pub(crate) fn publish_snapshot_components(
		components: &[Vec<usize>],
		snapshot: &MixtureSnapshot,
	) -> SnapshotPublication {
		let _publication = GAS_PUBLICATION.write();
		let mut result = SnapshotPublication {
			changed: Vec::new(),
			published: rustc_hash::FxHashSet::default(),
			rejected: rustc_hash::FxHashSet::default(),
		};
		let gases = GAS_MIXTURES.read();
		let gases = gases.as_ref().unwrap();
		for component in components {
			let stale = component
				.iter()
				.copied()
				.any(|id| snapshot.revision(id).unwrap_or_default() != Self::revision(id));
			if stale {
				for &id in component {
					result.rejected.insert(id);
					crate::turfs::mark_mix_active(id);
				}
				continue;
			}
			for &id in component {
				result.published.insert(id);
				if let (Some(source), Some(target)) = (snapshot.get(id), gases.get(id)) {
					let source = source.read();
					let mut target = target.write();
					let before = Self::change_signature(&target);
					if source.compare(&target) > crate::constants::GAS_MIN_MOLES
						|| source.temperature_compare(&target)
					{
						*target = source.clone();
						result.changed.push(id);
						Self::bump_revision_only(id);
						Self::mark_dirty_if_changed(id, before, Self::change_signature(&target));
					}
				}
			}
		}
		result
	}

	pub fn revision(id: usize) -> u64 {
		GAS_REVISIONS
			.read()
			.as_ref()
			.and_then(|revisions| revisions.get(id))
			.map_or(0, |revision| revision.load(Ordering::Acquire))
	}

	pub fn bump_revision(id: usize) {
		Self::bump_revision_only(id);
		crate::turfs::mark_mix_active(id);
	}

	/// Advance dependency/subscriber identity without scheduling a new diffusion
	/// generation. Internal turf publication uses this because it separately
	/// computes and queues the exact cells that remain divergent.
	pub(crate) fn bump_revision_only(id: usize) {
		if let Some(revision) = GAS_REVISIONS
			.read()
			.as_ref()
			.and_then(|revisions| revisions.get(id))
		{
			revision.fetch_add(1, Ordering::AcqRel);
		}
	}

	pub(crate) fn change_signature(mixture: &Mixture) -> GasChangeSignature {
		GasChangeSignature {
			pressure: mixture.return_pressure(),
			temperature: mixture.get_temperature(),
			composition: mixture.composition_moles(),
		}
	}

	pub(crate) fn signature_changed(
		before: &GasChangeSignature,
		after: &GasChangeSignature,
	) -> bool {
		before.pressure != after.pressure
			|| before.temperature != after.temperature
			|| before.composition != after.composition
	}

	pub(crate) fn mark_dirty_if_changed(
		id: usize,
		before: GasChangeSignature,
		after: GasChangeSignature,
	) -> bool {
		// Large pressure changes are player-visible immediately (breaches, opened
		// canisters, explosions). Put them ahead of routine machine churn while
		// retaining exact queue identity and conservation semantics.
		let immediate_pressure_delta = (before.pressure - after.pressure).abs();
		if immediate_pressure_delta >= 20.0 {
			crate::turfs::mark_mix_urgent(id, immediate_pressure_delta);
		}
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
			return false;
		}
		if mask & GAS_CHANGE_PRESSURE != 0 {
			baseline.pressure = after.pressure;
		}
		if mask & GAS_CHANGE_TEMPERATURE != 0 {
			baseline.temperature = after.temperature;
			#[cfg(feature = "heat")]
			crate::turfs::heat::gas_temperature_changed(id);
		}
		if mask & GAS_CHANGE_COMPOSITION != 0 {
			baseline.composition = after.composition;
		}
		drop(baselines);
		Self::mark_dirty(id, mask);
		true
	}

	fn mark_dirty(id: usize, mask: u8) {
		let interested_mask = WATCHED_GAS_MIXTURES
			.read()
			.as_ref()
			.and_then(|watched| watched.get(&id).copied())
			.unwrap_or_default();
		let mask = mask & interested_mask;
		if mask == 0 {
			return;
		}
		if let Some(dirty) = DIRTY_GAS_MIXTURES.write().as_mut() {
			*dirty.entry(id).or_default() |= mask;
		}
	}

	pub fn watch_dirty_mixture(id: usize, interest_mask: u8) {
		if let Some(watched) = WATCHED_GAS_MIXTURES.write().as_mut() {
			watched.insert(id, interest_mask);
		}
	}

	pub fn unwatch_dirty_mixture(id: usize) {
		if let Some(watched) = WATCHED_GAS_MIXTURES.write().as_mut() {
			watched.remove(&id);
		}
		// Drop notifications queued before the final subscriber disappeared.
		if let Some(dirty) = DIRTY_GAS_MIXTURES.write().as_mut() {
			dirty.remove(&id);
		}
	}

	pub fn take_dirty_mixtures() -> Vec<(usize, u8)> {
		DIRTY_GAS_MIXTURES
			.write()
			.as_mut()
			.map(|dirty| std::mem::take(dirty).into_iter().collect())
			.unwrap_or_default()
	}

	pub fn diagnostics() -> (usize, usize, usize, usize, usize, usize) {
		let gases = GAS_MIXTURES.read();
		let gases = gases.as_ref().unwrap();
		let free = NEXT_GAS_IDS.read();
		let baselines = DIRTY_GAS_BASELINES.read();
		let baselines = baselines.as_ref().unwrap();
		let composition_capacity = baselines
			.values()
			.map(|signature| signature.composition.capacity())
			.sum();
		(
			gases.len(),
			gases.capacity(),
			free.as_ref().unwrap().len(),
			baselines.len(),
			composition_capacity,
			DIRTY_GAS_MIXTURES.read().as_ref().unwrap().len(),
		)
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

	/// Runs a closure that writes any number of mixtures, holding the single-writer
	/// gate for the whole closure so it cannot interleave with the solver or another
	/// synchronous writer. The closure is responsible for revisions and dirty marks.
	/// # Panics
	/// if `GAS_MIXTURES` hasn't been initialized, somehow.
	pub fn with_all_mixtures_mut<T, F>(f: F) -> T
	where
		F: FnOnce(&[RwLock<Mixture>]) -> T,
	{
		let _single_writer = GAS_MUTATION_GATE.lock();
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
		let _single_writer = GAS_MUTATION_GATE.lock();
		let _publication = GAS_PUBLICATION.read();
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
		if Self::signature_changed(&before, &after) {
			Self::bump_revision(id);
			Self::mark_dirty_if_changed(id, before, after);
		}
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
		Self::with_gas_mixtures_mut_inner(src, arg, f, true)
	}

	/// Mutate two mixtures as part of the authoritative Rust solver. Revisions and
	/// device notifications still advance, but the solver owns subsequent queueing
	/// and must not classify its own output as a fresh external mutation.
	pub(crate) fn with_gas_mixtures_solver_mut<T, F>(src: usize, arg: usize, f: F) -> Result<T>
	where
		F: FnOnce(&mut Mixture, &mut Mixture) -> Result<T>,
	{
		Self::with_gas_mixtures_mut_inner(src, arg, f, false)
	}

	fn with_gas_mixtures_mut_inner<T, F>(src: usize, arg: usize, f: F, activate: bool) -> Result<T>
	where
		F: FnOnce(&mut Mixture, &mut Mixture) -> Result<T>,
	{
		let _single_writer = GAS_MUTATION_GATE.lock();
		let _publication = GAS_PUBLICATION.read();
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
		let src_after = Self::change_signature(&gas_mixtures.get(src).unwrap().read());
		if Self::signature_changed(&src_before, &src_after) {
			if activate {
				Self::bump_revision(src);
			} else {
				Self::bump_revision_only(src);
			}
			Self::mark_dirty_if_changed(src, src_before, src_after);
		}
		if src != arg {
			let arg_after = Self::change_signature(&gas_mixtures.get(arg).unwrap().read());
			if Self::signature_changed(&arg_before, &arg_after) {
				if activate {
					Self::bump_revision(arg);
				} else {
					Self::bump_revision_only(arg);
				}
				Self::mark_dirty_if_changed(arg, arg_before, arg_after);
			}
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
		let _single_writer = GAS_MUTATION_GATE.lock();
		let _publication = GAS_PUBLICATION.read();
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
		let src_after = Self::change_signature(&gas_mixtures.get(src).unwrap().read());
		if Self::signature_changed(&src_before, &src_after) {
			Self::bump_revision(src);
			Self::mark_dirty_if_changed(src, src_before, src_after);
		}
		if src != arg {
			let arg_after = Self::change_signature(&gas_mixtures.get(arg).unwrap().read());
			if Self::signature_changed(&arg_before, &arg_after) {
				Self::bump_revision(arg);
				Self::mark_dirty_if_changed(arg, arg_before, arg_after);
			}
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
		let _single_writer = GAS_MUTATION_GATE.lock();
		let init_volume = mix.read_number_id(byond_string!("initial_volume"))?;
		if NEXT_GAS_IDS.read().as_ref().unwrap().is_empty() {
			let mut gas_lock = GAS_MIXTURES.write();
			let gas_mixtures = gas_lock.as_mut().unwrap();
			// Reserve before push: push-at-capacity uses geometric growth and used to
			// leave hundreds of thousands of unreachable spare Mixture slots on the
			// Southern Cross map. The slots in this exact chunk are immediately made
			// addressable and all but the first enter the free-ID stack.
			let mut revisions_lock = GAS_REVISIONS.write();
			let revisions = revisions_lock.as_mut().unwrap();
			let mut ids_lock = NEXT_GAS_IDS.write();
			let next_gas_ids = ids_lock.as_mut().unwrap();
			let next_idx = grow_gas_storage(gas_mixtures, revisions, next_gas_ids, init_volume);

			mix.write_var_id(
				byond_string!("_extools_pointer_gasmixture"),
				&(next_idx as f32).into(),
			)
			.unwrap();
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
		let _single_writer = GAS_MUTATION_GATE.lock();
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

#[auxmacros::bind("/datum/gas_mixture/proc/revision")]
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
		let _gas_globals = crate::gas::types::TEST_GAS_GLOBALS_LOCK.lock().unwrap();
		set_gas_statics_manually();
		register_gas_manually("test", 20.0);
		register_gas_manually("test2", 20.0);
		initialize_gases();
		GasArena::watch_dirty_mixture(
			0,
			GAS_CHANGE_PRESSURE | GAS_CHANGE_TEMPERATURE | GAS_CHANGE_COMPOSITION,
		);
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

		let mut snapshot = MixtureSnapshot::default();
		GasArena::snapshot_mixtures_into(&[0], &mut snapshot);
		assert_eq!(snapshot.mixtures.len(), 1);
		assert_eq!(snapshot.ids, vec![0]);
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
		snapshot.get(0).unwrap().write().set_moles(0, 5.0);
		assert!(
			!GasArena::publish_snapshot_components(&[vec![0]], &snapshot)
				.rejected
				.is_empty()
		);
		assert_eq!(
			GasArena::with_gas_mixture(0, |mixture| Ok(mixture.get_moles(0))).unwrap(),
			10.0
		);

		GasArena::snapshot_mixtures_into(&[0], &mut snapshot);
		snapshot.get(0).unwrap().write().set_moles(0, 20.0);
		assert!(GasArena::publish_snapshot_components(&[vec![0]], &snapshot)
			.rejected
			.is_empty());
		assert_eq!(
			GasArena::with_gas_mixture(0, |mixture| Ok(mixture.get_moles(0))).unwrap(),
			20.0
		);

		// Independent transactions must not lose useful work because one room was
		// synchronously changed while the worker was processing another.
		let mut second = Mixture::from_vol(2_500.0);
		second.set_moles(0, 2.0);
		GAS_MIXTURES
			.write()
			.as_mut()
			.unwrap()
			.push(RwLock::new(second));
		GAS_REVISIONS
			.write()
			.as_mut()
			.unwrap()
			.push(AtomicU64::new(0));
		GasArena::snapshot_mixtures_into(&[0, 1], &mut snapshot);
		snapshot.get(0).unwrap().write().set_moles(0, 30.0);
		snapshot.get(1).unwrap().write().set_moles(0, 40.0);
		GasArena::with_gas_mixture_mut(0, |mixture| {
			mixture.set_moles(0, 25.0);
			Ok(())
		})
		.unwrap();
		let publication = GasArena::publish_snapshot_components(&[vec![0], vec![1]], &snapshot);
		assert_eq!(publication.rejected, rustc_hash::FxHashSet::from_iter([0]));
		assert_eq!(publication.published, rustc_hash::FxHashSet::from_iter([1]));
		assert_eq!(
			GasArena::with_gas_mixture(0, |mixture| Ok(mixture.get_moles(0))).unwrap(),
			25.0
		);
		assert_eq!(
			GasArena::with_gas_mixture(1, |mixture| Ok(mixture.get_moles(0))).unwrap(),
			40.0
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
				mixture.set_moles(1, 20.0 + step as f32 * 0.002);
				Ok(())
			})
			.unwrap();
			assert!(GasArena::take_dirty_mixtures().is_empty());
		}
		GasArena::with_gas_mixture_mut(0, |mixture| {
			mixture.set_moles(1, 20.012);
			Ok(())
		})
		.unwrap();
		assert_eq!(
			GasArena::take_dirty_mixtures(),
			vec![(0, GAS_CHANGE_COMPOSITION)]
		);
		GasArena::unwatch_dirty_mixture(0);
		GasArena::with_gas_mixture_mut(0, |mixture| {
			mixture.set_moles(1, 21.0);
			Ok(())
		})
		.unwrap();
		assert!(GasArena::take_dirty_mixtures().is_empty());
		let revision = GasArena::revision(0);
		GasArena::with_gas_mixture_mut(0, |_mixture| Ok(())).unwrap();
		assert_eq!(GasArena::revision(0), revision);

		let third = Mixture::from_vol(2_500.0);
		GAS_MIXTURES
			.write()
			.as_mut()
			.unwrap()
			.push(RwLock::new(third));
		GAS_REVISIONS
			.write()
			.as_mut()
			.unwrap()
			.push(AtomicU64::new(0));
		GasArena::with_gas_mixture_mut(0, |mixture| {
			mixture.clear();
			mixture.set_moles(0, 10.0);
			Ok(())
		})
		.unwrap();
		GasArena::with_gas_mixture_mut(1, |mixture| {
			mixture.clear();
			Ok(())
		})
		.unwrap();
		let actual = GasArena::batch_transfer(&[(0, 1, 8.0), (0, 2, 8.0)]);
		assert!((actual[0] - 8.0).abs() < f32::EPSILON * 8.0);
		assert!((actual[1] - 2.0).abs() < f32::EPSILON * 8.0);
		let conserved = (0..=2)
			.map(|id| GasArena::with_gas_mixture(id, |mix| Ok(mix.total_moles())).unwrap())
			.sum::<f32>();
		assert!((conserved - 10.0).abs() < 0.0001);

		// A leaking pipenet transaction must conserve its complete gas inventory
		// and converge to a state that can hibernate without a DM-side polling
		// watchdog. This covers the exact atomic operation exposed to BYOND.
		GasArena::with_gas_mixture_mut(0, |mixture| {
			mixture.clear();
			mixture.volume = 5_000.0;
			mixture.set_moles(0, 100.0);
			mixture.set_temperature(350.0);
			Ok(())
		})
		.unwrap();
		GasArena::with_gas_mixture_mut(1, |mixture| {
			mixture.clear();
			mixture.volume = 2_500.0;
			mixture.set_moles(1, 20.0);
			mixture.set_temperature(250.0);
			Ok(())
		})
		.unwrap();
		let mingle_before = (0..=1)
			.map(|id| GasArena::with_gas_mixture(id, |mix| Ok(mix.total_moles())).unwrap())
			.sum::<f32>();
		let mut residual = true;
		for _ in 0..256 {
			residual = GasArena::batch_mingle(&[(0, 1, 200.0)])[0];
			if !residual {
				break;
			}
		}
		assert!(
			!residual,
			"leak transaction did not converge to hibernation"
		);
		let mingle_after = (0..=1)
			.map(|id| GasArena::with_gas_mixture(id, |mix| Ok(mix.total_moles())).unwrap())
			.sum::<f32>();
		assert!((mingle_after - mingle_before).abs() < 0.0001);
		destroy_gas_statics();
	}

	/// Regression for B14: `equalize_all_gases_in_list` must wait for the
	/// single-writer gate instead of writing while another writer holds it.
	#[test]
	fn equalize_waits_for_the_mutation_gate() {
		let _gas_globals = crate::gas::types::TEST_GAS_GLOBALS_LOCK.lock().unwrap();
		set_gas_statics_manually();
		register_gas_manually("test", 20.0);
		initialize_gases();
		for moles in [10.0, 30.0] {
			let mut mixture = Mixture::from_vol(2_500.0);
			mixture.set_moles(0, moles);
			GAS_MIXTURES
				.write()
				.as_mut()
				.unwrap()
				.push(RwLock::new(mixture));
			GAS_REVISIONS
				.write()
				.as_mut()
				.unwrap()
				.push(AtomicU64::new(0));
		}
		let moles = |id| GasArena::with_gas_mixture(id, |mix| Ok(mix.get_moles(0))).unwrap();

		let gate = GAS_MUTATION_GATE.lock();
		let equalizer = std::thread::spawn(|| crate::equalize_mixture_ids(&[0, 1]));
		std::thread::sleep(std::time::Duration::from_millis(100));
		assert!(!equalizer.is_finished(), "equalize ran without the gate");
		assert_eq!((moles(0), moles(1)), (10.0, 30.0));
		drop(gate);
		equalizer.join().unwrap();
		assert_eq!((moles(0), moles(1)), (20.0, 20.0));
		assert!(GasArena::revision(0) > 0 && GasArena::revision(1) > 0);
		destroy_gas_statics();
	}
}
#[test]
fn gas_arena_growth_is_bounded_instead_of_geometric() {
	let mut mixtures = Vec::new();
	let mut revisions = Vec::new();
	let mut free_ids = Vec::new();
	for generation in 1..=128 {
		free_ids.clear();
		let id = grow_gas_storage(&mut mixtures, &mut revisions, &mut free_ids, 2_500.0);
		assert_eq!(id, (generation - 1) * GAS_ARENA_GROWTH);
		assert_eq!(mixtures.len(), generation * GAS_ARENA_GROWTH);
		assert_eq!(revisions.len(), mixtures.len());
		assert_eq!(free_ids.len(), GAS_ARENA_GROWTH - 1);
		assert!(
			mixtures.capacity() <= mixtures.len() + GAS_ARENA_GROWTH,
			"arena capacity grew geometrically: len={} capacity={}",
			mixtures.len(),
			mixtures.capacity()
		);
	}
}
