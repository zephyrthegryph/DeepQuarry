pub mod processing;
/*
*/
#[cfg(feature = "heat")]
pub(crate) mod heat;

use crate::{constants::*, gas::Mixture, GasArena};
use bitflags::bitflags;
use byondapi::prelude::*;
use eyre::{Context, Result};
use indexmap::IndexMap;
use parking_lot::{const_mutex, const_rwlock, Mutex, RwLock, RwLockUpgradableReadGuard};
use petgraph::{graph::NodeIndex, stable_graph::StableDiGraph, visit::EdgeRef, Direction};
use rayon::prelude::*;
use rustc_hash::{FxBuildHasher, FxHashMap, FxHashSet};
use std::collections::VecDeque;
use std::hash::{Hash, Hasher};
use std::time::Duration;
use std::{
	mem::drop,
	sync::atomic::{AtomicBool, AtomicU32, AtomicU64, AtomicUsize, Ordering},
};
use vg_core::grid::{Face, GridDims};

bitflags! {
	#[derive(Default, Debug, Clone, Copy, PartialEq, Eq)]
	pub struct Directions: u8 {
		const NORTH = 0b1;
		const SOUTH = 0b10;
		const EAST	= 0b100;
		const WEST	= 0b1000;
		const UP 	= 0b10000;
		const DOWN 	= 0b100000;
		const ALL_CARDINALS = Self::NORTH.bits() | Self::SOUTH.bits() | Self::EAST.bits() | Self::WEST.bits();
		const ALL_CARDINALS_MULTIZ = Self::NORTH.bits() | Self::SOUTH.bits() | Self::EAST.bits() | Self::WEST.bits() | Self::UP.bits() | Self::DOWN.bits();
	}

	#[derive(Default, Debug)]
	pub struct SimulationFlags: u8 {
		const SIMULATION_DIFFUSE = 0b1;
		const SIMULATION_ALL = 0b10;
		const SIMULATION_ANY = Self::SIMULATION_DIFFUSE.bits() | Self::SIMULATION_ALL.bits();
	}

	#[derive(Default, Debug, Clone, Copy)]
	pub struct DirtyFlags: u8 {
		const DIRTY_MIX_REF = 0b1;
		const DIRTY_ADJACENT = 0b10;
		const DIRTY_ADJACENT_TO_SPACE = 0b100;
	}
}

/// Registration flag DM passes for a simulated turf (`SimulationFlags::SIMULATION_ANY`).
/// @dm-define SIMULATION_ANY
pub const DM_SIMULATION_ANY: u8 = 3;
const _: () = assert!(DM_SIMULATION_ANY == SimulationFlags::SIMULATION_ANY.bits());

#[allow(unused)]
const fn adj_flag_to_idx(adj_flag: Directions) -> u8 {
	match adj_flag {
		Directions::NORTH => 0,
		Directions::SOUTH => 1,
		Directions::EAST => 2,
		Directions::WEST => 3,
		Directions::UP => 4,
		Directions::DOWN => 5,
		_ => 6,
	}
}

#[allow(unused)]
const fn idx_to_adj_flag(idx: u8) -> Directions {
	match idx {
		0 => Directions::NORTH,
		1 => Directions::SOUTH,
		2 => Directions::EAST,
		3 => Directions::WEST,
		4 => Directions::UP,
		5 => Directions::DOWN,
		_ => Directions::from_bits_truncate(0),
	}
}

type TurfID = u32;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, PartialOrd, Ord)]
struct CellHandle {
	id: TurfID,
	generation: u64,
}

// TurfMixture can be treated as "immutable" for all intents and purposes--put other data somewhere else
#[derive(Default, Debug)]
struct TurfMixture {
	pub mix: usize,
	pub id: TurfID,
	pub generation: u64,
	pub flags: SimulationFlags,
	pub planetary_atmos: Option<u32>,
	/// Structural boundary flag cached on the turf cell. Keeping this beside the
	/// topology lets the scheduler reject space without taking the gas-arena lock.
	pub immutable: bool,
	pub vis_hash: AtomicU64,
}

#[allow(dead_code)]
impl TurfMixture {
	fn handle(&self) -> CellHandle {
		CellHandle {
			id: self.id,
			generation: self.generation,
		}
	}
	/// Whether the turf is processed at all or not
	pub fn enabled(&self) -> bool {
		self.flags.intersects(SimulationFlags::SIMULATION_ANY)
	}

	/// Whether the turf's gas is immutable or not, see [`super::gas::Mixture`]
	pub fn is_immutable(&self) -> bool {
		self.immutable
	}
	/// Returns the pressure of the turf's gas, see [`super::gas::Mixture`]
	pub fn return_pressure(&self) -> f32 {
		GasArena::with_all_mixtures(|all_mixtures| {
			all_mixtures
				.get(self.mix)
				.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
				.read()
				.return_pressure()
		})
	}
	/// Returns the temperature of the turf's gas, see [`super::gas::Mixture`]
	pub fn return_temperature(&self) -> f32 {
		GasArena::with_all_mixtures(|all_mixtures| {
			all_mixtures
				.get(self.mix)
				.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
				.read()
				.get_temperature()
		})
	}
	/// Returns the total moles of the turf's gas, see [`super::gas::Mixture`]
	pub fn total_moles(&self) -> f32 {
		GasArena::with_all_mixtures(|all_mixtures| {
			all_mixtures
				.get(self.mix)
				.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
				.read()
				.total_moles()
		})
	}
	/// Clears the turf's airs, see [`super::gas::Mixture`]
	pub fn clear_air(&self) {
		let (before, after) = GasArena::with_all_mixtures(|all_mixtures| {
			let mut mixture = all_mixtures
				.get(self.mix)
				.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
				.write();
			let before = GasArena::change_signature(&mixture);
			mixture.clear();
			(before, GasArena::change_signature(&mixture))
		});
		if GasArena::signature_changed(&before, &after) {
			GasArena::bump_revision(self.mix);
			GasArena::mark_dirty_if_changed(self.mix, before, after);
		}
	}
	/// Prevents diffusion and other gas operations from changing this turf's mixture.
	pub fn mark_immutable(&self) {
		let changed = GasArena::with_all_mixtures(|all_mixtures| {
			let mut mixture = all_mixtures
				.get(self.mix)
				.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
				.write();
			let changed = !mixture.is_immutable();
			mixture.mark_immutable();
			changed
		});
		if changed {
			GasArena::bump_revision_only(self.mix);
		}
	}
	/// Copies from a given gas mixture to the turf's airs, see [`super::gas::Mixture`]
	pub fn copy_from_mutable(&self, sample: &Mixture) {
		let (before, after) = GasArena::with_all_mixtures(|all_mixtures| {
			let mut mixture = all_mixtures
				.get(self.mix)
				.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
				.write();
			let before = GasArena::change_signature(&mixture);
			mixture.copy_from_mutable(sample);
			(before, GasArena::change_signature(&mixture))
		});
		if GasArena::signature_changed(&before, &after) {
			GasArena::bump_revision(self.mix);
			GasArena::mark_dirty_if_changed(self.mix, before, after);
		}
	}
	/// Clears a number of moles from the turf's air
	/// If the number of moles is greater than the turf's total moles, just clears the turf
	pub fn clear_moles(&self, amt: f32) {
		let (before, after) = GasArena::with_all_mixtures(|all_mixtures| {
			let before = GasArena::change_signature(
				&all_mixtures
					.get(self.mix)
					.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
					.read(),
			);
			let moles = all_mixtures
				.get(self.mix)
				.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
				.read()
				.total_moles();
			if amt >= moles {
				all_mixtures
					.get(self.mix)
					.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
					.write()
					.clear();
			} else {
				drop(
					all_mixtures
						.get(self.mix)
						.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
						.write()
						.remove(amt),
				);
			}
			let after = GasArena::change_signature(
				&all_mixtures
					.get(self.mix)
					.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
					.read(),
			);
			(before, after)
		});
		if GasArena::signature_changed(&before, &after) {
			GasArena::bump_revision(self.mix);
			GasArena::mark_dirty_if_changed(self.mix, before, after);
		}
	}
	/// Gets a copy of the turf's airs, see [`super::gas::Mixture`]
	pub fn get_gas_copy(&self) -> Mixture {
		let mut ret: Mixture = Mixture::new();
		GasArena::with_all_mixtures(|all_mixtures| {
			let to_copy = all_mixtures
				.get(self.mix)
				.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
				.read();
			ret.copy_from_mutable(&to_copy);
			ret.volume = to_copy.volume;
		});
		ret
	}
	/// Invalidates the turf's visibility cache
	/// This turf will most likely be visually updated the next processing cycle
	/// If that is even running
	pub fn invalidate_vis_cache(&self) {
		self.vis_hash.store(0, std::sync::atomic::Ordering::Relaxed);
	}
}

type TurfGraphMap = IndexMap<TurfID, NodeIndex, FxBuildHasher>;

//adjacency/turf infos goes here
#[derive(Debug)]
struct TurfGases {
	graph: StableDiGraph<TurfMixture, ()>,
	map: TurfGraphMap,
	generations: FxHashMap<TurfID, u64>,
}

impl TurfGases {
	pub fn insert_turf(&mut self, mut tmix: TurfMixture) {
		if let Some(&node_id) = self.map.get(&tmix.id) {
			let thin = self.graph.node_weight_mut(node_id).unwrap();
			if thin.mix == tmix.mix {
				tmix.generation = thin.generation;
			} else {
				let generation = self.generations.entry(tmix.id).or_default();
				*generation += 1;
				tmix.generation = *generation;
			}
			*thin = tmix
		} else {
			let generation = self.generations.entry(tmix.id).or_default();
			*generation += 1;
			tmix.generation = *generation;
			self.map.insert(tmix.id, self.graph.add_node(tmix));
		}
	}
	pub fn remove_turf(&mut self, id: TurfID) {
		if let Some(index) = self.map.shift_remove(&id) {
			self.graph.remove_node(index);
		}
	}
	/// Makes this cell's solver edges match the published air-block masks: one
	/// edge each way to every open face neighbour that is in the graph, none
	/// elsewhere. Edges only ever join grid neighbours, so a face is counted once
	/// and the result does not depend on registration order. Returns whether any
	/// edge changed.
	fn sync_edges(&mut self, id: TurfID, cells: &AirCells) -> bool {
		let (Some(node), Some(dims)) = (self.get_id(id), cells.dims) else {
			return false;
		};
		let mut changed = false;
		for face in Face::ALL {
			let Some(other_id) = dims.neighbor(id, face) else {
				continue;
			};
			let Some(other) = self.get_id(other_id) else {
				continue;
			};
			// Two immutable cells (space, planet boundaries) never exchange gas,
			// so the solver gets no edge between them. Queries still see the
			// adjacency through AirCells.
			let both_immutable = self.get(node).is_some_and(TurfMixture::is_immutable)
				&& self.get(other).is_some_and(TurfMixture::is_immutable);
			let open = !both_immutable && cells.open_neighbor(id, face) == Some(other_id);
			for (from, to) in [(node, other), (other, node)] {
				match (open, self.graph.find_edge(from, to)) {
					(true, None) => {
						self.graph.add_edge(from, to, ());
						changed = true;
					}
					(false, Some(edge)) => {
						self.graph.remove_edge(edge);
						changed = true;
					}
					_ => {}
				}
			}
		}
		changed
	}

	/// Test helper: joins two cells with an edge each way.
	#[cfg(test)]
	pub(super) fn link(&mut self, a: TurfID, b: TurfID) {
		let (a, b) = (self.get_id(a).unwrap(), self.get_id(b).unwrap());
		for (from, to) in [(a, b), (b, a)] {
			if self.graph.find_edge(from, to).is_none() {
				self.graph.add_edge(from, to, ());
			}
		}
	}

	pub fn get(&self, idx: NodeIndex) -> Option<&TurfMixture> {
		self.graph.node_weight(idx)
	}

	#[allow(unused)]
	pub fn get_from_id(&self, idx: TurfID) -> Option<&TurfMixture> {
		self.map
			.get(&idx)
			.and_then(|&idx| self.graph.node_weight(idx))
	}

	#[allow(unused)]
	pub fn get_id(&self, idx: TurfID) -> Option<NodeIndex> {
		self.map.get(&idx).copied()
	}

	pub fn get_handle(&self, handle: CellHandle) -> Option<NodeIndex> {
		let node = self.get_id(handle.id)?;
		(self.get(node)?.generation == handle.generation).then_some(node)
	}

	pub fn adjacent_node_ids(&self, index: NodeIndex) -> impl Iterator<Item = NodeIndex> + '_ {
		self.graph.neighbors(index)
	}

	#[allow(unused)]
	pub fn adjacent_turf_ids(&self, index: NodeIndex) -> impl Iterator<Item = TurfID> + '_ {
		self.graph
			.neighbors(index)
			.filter_map(|index| Some(self.get(index)?.id))
	}

	#[allow(unused)]
	pub fn adjacent_node_ids_enabled(
		&self,
		index: NodeIndex,
	) -> impl Iterator<Item = NodeIndex> + '_ {
		self.graph.neighbors(index).filter(|&adj_index| {
			self.graph
				.node_weight(adj_index)
				.map_or(false, |mix| mix.enabled())
		})
	}

	pub fn adjacent_mixes<'a>(
		&'a self,
		index: NodeIndex,
		all_mixtures: &'a (impl crate::gas::MixtureLookup + ?Sized),
	) -> impl Iterator<Item = &'a parking_lot::RwLock<Mixture>> {
		self.graph
			.neighbors(index)
			.filter_map(|neighbor| self.graph.node_weight(neighbor))
			.filter_map(move |idx| all_mixtures.mixture(idx.mix))
	}

	pub fn clear(&mut self) {
		self.graph.clear();
		self.map.clear();
		self.generations.clear();
	}

	/*
	pub fn adjacent_infos(
		&self,
		index: NodeIndex,
		dir: Direction,
	) -> impl Iterator<Item = &TurfMixture> {
		self.graph
			.neighbors_directed(index, dir)
			.filter_map(|neighbor| self.graph.node_weight(neighbor))
	}

	pub fn adjacent_ids<'a>(&'a self, idx: TurfID) -> impl Iterator<Item = &'a TurfID> {
		self.graph
			.neighbors(*self.map.get(&idx).unwrap())
			.filter_map(|index| self.graph.node_weight(index))
			.map(|tmix| &tmix.id)
	}
	pub fn adjacents_enabled<'a>(&'a self, idx: TurfID) -> impl Iterator<Item = &'a TurfID> {
		self.graph
			.neighbors(*self.map.get(&idx).unwrap())
			.filter_map(|index| self.graph.node_weight(index))
			.filter(|tmix| tmix.enabled())
			.map(|tmix| &tmix.id)
	}
	pub fn get_mixture(&self, idx: TurfID) -> Option<TurfMixture> {
		self.mixtures.read().get(&idx).cloned()
	}
	*/
}

static TURF_GASES: RwLock<Option<TurfGases>> = const_rwlock(None);

/// Every face a mask can block (`NORTH|SOUTH|EAST|WEST|UP|DOWN`).
/// @dm-define AIR_BLOCK_ALL
pub const AIR_BLOCK_ALL: u8 = 63;

/// Mask argument meaning "keep the mask Rust already has for this turf".
/// @dm-define AIR_BLOCK_KEEP
pub const AIR_BLOCK_KEEP: i32 = -1;

/// Turf adjacency, built from air-block masks DM publishes.
///
/// A turf's mask is the OR of the faces the turf itself and each atom on it
/// block (see `/turf/proc/air_block_mask`). Two registered face neighbours share
/// air when neither blocks the shared face and, for UP/DOWN, the z-levels are
/// linked. This replaces the per-turf DM `atmos_adjacent_turfs` lists.
///
/// DM queries read this directly and so always see the latest publication;
/// the solver graph in `TurfGases` catches up when queued topology updates are
/// applied. Lock order: `TURF_GASES` before `AIR_CELLS`, never the reverse.
#[derive(Default)]
struct AirCells {
	dims: Option<GridDims>,
	/// Registered cells and the faces they block.
	masks: FxHashMap<TurfID, u8>,
	/// Per zero-based z: the `UP`/`DOWN` bits of linked z-levels.
	z_links: Vec<u8>,
}

impl AirCells {
	/// The neighbour across `face` if both cells are registered and air crosses.
	fn open_neighbor(&self, id: TurfID, face: Face) -> Option<TurfID> {
		let dims = self.dims?;
		let mask = *self.masks.get(&id)?;
		if mask & face.bit() != 0 {
			return None;
		}
		let other = dims.neighbor(id, face)?;
		if matches!(face, Face::Up | Face::Down) {
			let (lower, upper) = if face == Face::Up {
				(id, other)
			} else {
				(other, id)
			};
			let link = |cell: TurfID| {
				self.z_links
					.get((cell / dims.layer_len()) as usize)
					.copied()
					.unwrap_or(0)
			};
			if link(lower) & Face::Up.bit() == 0 || link(upper) & Face::Down.bit() == 0 {
				return None;
			}
		}
		let other_mask = *self.masks.get(&other)?;
		(other_mask & face.opposite().bit() == 0).then_some(other)
	}

	fn open_neighbors(&self, id: TurfID) -> impl Iterator<Item = TurfID> + '_ {
		Face::ALL
			.into_iter()
			.filter_map(move |face| self.open_neighbor(id, face))
	}

	/// Bits of the faces across which `id` shares air.
	fn open_dirs(&self, id: TurfID) -> u8 {
		Face::ALL
			.into_iter()
			.filter(|&face| self.open_neighbor(id, face).is_some())
			.fold(0, |acc, face| acc | face.bit())
	}
}

static AIR_CELLS: RwLock<Option<AirCells>> = const_rwlock(None);

fn with_air_cells<T>(f: impl FnOnce(&AirCells) -> T) -> T {
	f(AIR_CELLS.read().as_ref().unwrap())
}

fn with_air_cells_mut<T>(f: impl FnOnce(&mut AirCells) -> T) -> T {
	f(AIR_CELLS.write().as_mut().unwrap())
}

// We store planetary atmos by hash of the initial atmos string here for speed.
static PLANETARY_ATMOS: RwLock<Option<IndexMap<u32, Mixture, FxBuildHasher>>> = const_rwlock(None);
/// The complete activation state lives behind one lock so a cell cannot be in
/// both queues. External mutations upgrade retained frontier work to fresh work;
/// solver retention never downgrades or duplicates a fresh activation.
#[derive(Default)]
struct ActiveQueue {
	order: VecDeque<CellHandle>,
	members: FxHashSet<CellHandle>,
}

impl ActiveQueue {
	fn insert(&mut self, handle: CellHandle) {
		if self.members.insert(handle) {
			self.order.push_back(handle);
		}
	}

	fn remove(&mut self, handle: &CellHandle) {
		self.members.remove(handle);
	}

	fn contains(&self, handle: &CellHandle) -> bool {
		self.members.contains(handle)
	}

	fn len(&self) -> usize {
		self.members.len()
	}

	/// Drain in FIFO order without `IndexSet::shift_remove`'s O(n) compaction.
	/// Moving a cell between priority lanes leaves a harmless tombstone in the
	/// old deque; one bounded pass skips tombstones and rotates epoch-excluded
	/// live entries to the back for the next physical step.
	fn drain_unseen(
		&mut self,
		selected: &mut FxHashSet<CellHandle>,
		excluded: &FxHashSet<CellHandle>,
		count: usize,
	) {
		let scan_limit = self.order.len();
		for _ in 0..scan_limit {
			if selected.len() >= count {
				break;
			}
			let Some(handle) = self.order.pop_front() else {
				break;
			};
			if !self.members.contains(&handle) {
				continue;
			}
			if excluded.contains(&handle) {
				self.order.push_back(handle);
				continue;
			}
			self.members.remove(&handle);
			selected.insert(handle);
		}
	}
}

#[derive(Default)]
struct ActiveTurfs {
	urgent: ActiveQueue,
	fresh: ActiveQueue,
	frontier: ActiveQueue,
}

impl ActiveTurfs {
	fn activate_fresh(&mut self, handle: CellHandle) {
		if self.urgent.contains(&handle) {
			return;
		}
		self.frontier.remove(&handle);
		self.fresh.insert(handle);
	}

	fn activate_urgent(&mut self, handle: CellHandle) {
		self.fresh.remove(&handle);
		self.frontier.remove(&handle);
		self.urgent.insert(handle);
	}

	fn activate_frontier(&mut self, handle: CellHandle) {
		if !self.fresh.contains(&handle) {
			self.frontier.insert(handle);
		}
	}

	fn remove(&mut self, handle: CellHandle) {
		self.urgent.remove(&handle);
		self.fresh.remove(&handle);
		self.frontier.remove(&handle);
	}

	fn len(&self) -> usize {
		self.urgent.len() + self.fresh.len() + self.frontier.len()
	}

	fn queue_counts(&self) -> (usize, usize, usize) {
		(self.urgent.len(), self.fresh.len(), self.frontier.len())
	}

	fn contains(&self, handle: CellHandle) -> bool {
		self.urgent.contains(&handle)
			|| self.fresh.contains(&handle)
			|| self.frontier.contains(&handle)
	}

	fn take(&mut self, limit: usize) -> FxHashSet<CellHandle> {
		self.take_unseen(limit, &FxHashSet::default())
	}

	/// Take work which has not already participated in the current physical
	/// simulation epoch. Retained gradients stay queued for the following epoch
	/// instead of cycling back through several microtransactions while older
	/// regions remain frozen.
	fn take_unseen(
		&mut self,
		limit: usize,
		excluded: &FxHashSet<CellHandle>,
	) -> FxHashSet<CellHandle> {
		let mut selected = FxHashSet::default();
		self.urgent.drain_unseen(&mut selected, excluded, limit);
		if selected.len() == limit {
			return selected;
		}
		// Reserve one quarter of a full generation for retained physical work.
		// A continuously operated machine can no longer starve an older plume.
		let remaining_limit = limit - selected.len();
		let eligible_frontier = self
			.frontier
			.members
			.iter()
			.filter(|handle| !excluded.contains(handle))
			.count();
		let frontier_reserve = eligible_frontier.min(remaining_limit / 4);
		let fresh_target = selected.len() + remaining_limit - frontier_reserve;
		self.fresh
			.drain_unseen(&mut selected, excluded, fresh_target);
		let frontier_count = limit - selected.len();
		let frontier_target = selected.len() + frontier_count;
		self.frontier
			.drain_unseen(&mut selected, excluded, frontier_target);
		if selected.len() < limit {
			self.fresh.drain_unseen(&mut selected, excluded, limit);
		}
		selected
	}
}

static ACTIVE_TURFS: RwLock<Option<ActiveTurfs>> = const_rwlock(None);
static PRESSURE_URGENCY_MILLIKPA: AtomicU32 = AtomicU32::new(0);
static PRESSURE_URGENCY_INFLIGHT_MILLIKPA: AtomicU32 = AtomicU32::new(0);

#[cfg(test)]
mod active_turf_tests {
	use super::*;
	static PRESSURE_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

	fn handle(id: TurfID) -> CellHandle {
		CellHandle { id, generation: 1 }
	}

	#[test]
	fn activation_state_is_exclusive_and_fresh_upgrades_frontier() {
		let mut active = ActiveTurfs::default();
		active.activate_frontier(handle(1));
		active.activate_fresh(handle(1));
		assert_eq!(active.len(), 1);
		assert!(active.fresh.contains(&handle(1)));
		assert!(!active.frontier.contains(&handle(1)));
		active.activate_frontier(handle(1));
		assert_eq!(active.len(), 1);
		assert!(active.fresh.contains(&handle(1)));
	}

	#[test]
	fn retained_frontier_has_guaranteed_capacity_under_fresh_load() {
		let mut active = ActiveTurfs::default();
		for id in 1..=5_000 {
			active.activate_fresh(handle(id));
		}
		for id in 10_001..=11_500 {
			active.activate_frontier(handle(id));
		}
		let selected = active.take(MAX_TURF_SEEDS_PER_GENERATION);
		let selected_frontier = selected.iter().filter(|cell| cell.id >= 10_001).count();
		assert_eq!(selected.len(), MAX_TURF_SEEDS_PER_GENERATION);
		assert_eq!(selected_frontier, MAX_TURF_SEEDS_PER_GENERATION / 4);
	}

	#[test]
	fn an_epoch_never_selects_the_same_cell_twice() {
		let mut active = ActiveTurfs::default();
		for id in 1..=12 {
			active.activate_urgent(handle(id));
		}
		let first = active.take_unseen(6, &FxHashSet::default());
		// A retained gradient is reactivated immediately after publication, but it
		// must wait until the next epoch rather than starving untouched cells.
		for cell in &first {
			active.activate_urgent(*cell);
		}
		let second = active.take_unseen(6, &first);
		assert_eq!(second.len(), 6);
		assert!(first.is_disjoint(&second));
		assert_eq!(active.len(), 6);
	}

	#[test]
	fn urgent_pressure_work_preempts_routine_and_retained_work() {
		let mut active = ActiveTurfs::default();
		for id in 1..=20 {
			active.activate_fresh(handle(id));
		}
		for id in 101..=120 {
			active.activate_frontier(handle(id));
		}
		active.activate_urgent(handle(999));
		let selected = active.take(4);
		assert!(selected.contains(&handle(999)));
		assert_eq!(selected.len(), 4);
	}

	#[test]
	fn adaptive_limit_is_bounded_and_moves_toward_latency_target() {
		TURF_SEED_LIMIT.store(INITIAL_TURF_SEEDS_PER_GENERATION, Ordering::Release);
		adapt_turf_seed_limit(160.0, 40.0);
		let reduced = turf_seed_limit();
		assert!(reduced < INITIAL_TURF_SEEDS_PER_GENERATION);
		adapt_turf_seed_limit(1.0, 40.0);
		assert!(turf_seed_limit() > reduced);
		for _ in 0..100 {
			adapt_turf_seed_limit(10_000.0, 40.0);
		}
		assert_eq!(turf_seed_limit(), MIN_TURF_SEEDS_PER_GENERATION);
		TURF_SEED_LIMIT.store(INITIAL_TURF_SEEDS_PER_GENERATION, Ordering::Release);
	}

	#[test]
	fn pressure_urgency_tracks_the_largest_pending_delta() {
		let _pressure_test = PRESSURE_TEST_LOCK.lock().unwrap();
		PRESSURE_URGENCY_MILLIKPA.store(0, Ordering::Release);
		PRESSURE_URGENCY_INFLIGHT_MILLIKPA.store(0, Ordering::Release);
		mark_mix_urgent(usize::MAX, 25.0);
		mark_mix_urgent(usize::MAX, 180.0);
		assert_eq!(current_pressure_urgency_kpa(), 180.0);
		assert_eq!(begin_pressure_generation(), 180.0);
		assert_eq!(current_pressure_urgency_kpa(), 180.0);
		finish_pressure_generation();
		assert_eq!(current_pressure_urgency_kpa(), 0.0);
	}

	#[test]
	fn cancelled_generation_restores_pressure_urgency() {
		let _pressure_test = PRESSURE_TEST_LOCK.lock().unwrap();
		PRESSURE_URGENCY_MILLIKPA.store(0, Ordering::Release);
		PRESSURE_URGENCY_INFLIGHT_MILLIKPA.store(0, Ordering::Release);
		mark_mix_urgent(usize::MAX, 75.0);
		assert_eq!(begin_pressure_generation(), 75.0);
		abort_pressure_generation();
		assert_eq!(current_pressure_urgency_kpa(), 75.0);
		assert_eq!(begin_pressure_generation(), 75.0);
		finish_pressure_generation();
	}
}
static MIX_TO_TURF: RwLock<Option<FxHashMap<usize, CellHandle>>> = const_rwlock(None);

#[derive(Debug)]
enum PendingTopologyUpdate {
	/// Register or refresh a cell, then sync its edges from `AIR_CELLS`.
	Insert(TurfMixture),
	Remove(TurfID),
	/// The z-level links changed: re-sync every cell's edges.
	ResyncAll,
}

static PENDING_TOPOLOGY: RwLock<Vec<PendingTopologyUpdate>> = const_rwlock(Vec::new());
static TOPOLOGY_TRANSACTION: Mutex<Vec<PendingTopologyUpdate>> = const_mutex(Vec::new());
static TOPOLOGY_TRANSACTION_OPEN: AtomicBool = AtomicBool::new(false);
static TOPOLOGY_BATCH_OPEN: AtomicBool = AtomicBool::new(false);
static TURF_TOPOLOGY_GENERATION: AtomicU64 = AtomicU64::new(0);

//whether there is any tasks running
static TASKS: RwLock<()> = const_rwlock(());

pub(super) fn topology_generation() -> u64 {
	TURF_TOPOLOGY_GENERATION.load(Ordering::Acquire)
}

pub fn wait_for_tasks() {
	match TASKS.try_write_for(Duration::from_secs(5)) {
		Some(_) => (),
		None => panic!(
			"Threads failed to release resources within 5 seconds, this may indicate a deadlock!"
		),
	}
}

/// Synchronous topology mutations (notably shuttle translation) must begin
/// with no diffusion/equalization generation still referring to the old turf
/// graph. These operations are rare, so a bounded barrier is preferable to
/// publishing any result across a moving topology.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_topology_barrier")]
fn topology_barrier() -> Result<ByondValue> {
	wait_for_tasks();
	apply_pending_topology_updates();
	Ok(ByondValue::null())
}

/// Opens a synchronous world-topology transaction. Atmos workers are drained
/// before DM begins mutating turfs and cannot start again until commit.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_topology_transaction_begin")]
fn topology_transaction_begin() -> Result<ByondValue> {
	wait_for_tasks();
	apply_pending_topology_updates();
	TOPOLOGY_TRANSACTION.lock().clear();
	TOPOLOGY_TRANSACTION_OPEN.store(true, Ordering::Release);
	Ok(ByondValue::null())
}

/// Atomically applies every registration and edge replacement accumulated by
/// the matching begin call, then exposes one new topology generation.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_topology_transaction_commit")]
fn topology_transaction_commit() -> Result<ByondValue> {
	// The bind macro catches unwinds outside this function. This guard ensures a
	// failed commit can never strand atmos processing in the paused state.
	struct TransactionReset;
	impl Drop for TransactionReset {
		fn drop(&mut self) {
			TOPOLOGY_TRANSACTION_OPEN.store(false, Ordering::Release);
		}
	}
	let _reset = TransactionReset;
	let updates = std::mem::take(&mut *TOPOLOGY_TRANSACTION.lock());
	with_turf_gases_write(|arena| {
		let (structural, adjacency): (Vec<_>, Vec<_>) = updates.into_iter().partition(|update| {
			matches!(
				update,
				PendingTopologyUpdate::Insert(_) | PendingTopologyUpdate::Remove(_)
			)
		});
		// Register every replacement cell before resolving any edge. This makes
		// transaction results independent of DM's per-turf ChangeTurf ordering.
		for update in structural {
			apply_topology_update(arena, update);
		}
		for update in adjacency {
			apply_topology_update(arena, update);
		}
	});
	TURF_TOPOLOGY_GENERATION.fetch_add(1, Ordering::AcqRel);
	Ok(ByondValue::null())
}

/// Opens a non-blocking destructive-world batch (explosions). Unlike shuttle
/// transactions this never waits for the worker: it invalidates its generation,
/// queues every topology mutation, and lets the worker cancel at its next budget
/// checkpoint.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_topology_batch_begin")]
fn topology_batch_begin() -> Result<ByondValue> {
	TOPOLOGY_BATCH_OPEN.store(true, Ordering::Release);
	TURF_TOPOLOGY_GENERATION.fetch_add(1, Ordering::AcqRel);
	Ok(ByondValue::null())
}

#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_topology_batch_commit")]
fn topology_batch_commit() -> Result<ByondValue> {
	TOPOLOGY_BATCH_OPEN.store(false, Ordering::Release);
	TURF_TOPOLOGY_GENERATION.fetch_add(1, Ordering::AcqRel);
	if let Some(_task_barrier) = TASKS.try_write() {
		apply_pending_topology_updates();
	}
	Ok(ByondValue::null())
}

pub(crate) fn mark_mix_active(mix: usize) {
	let handle = MIX_TO_TURF
		.read()
		.as_ref()
		.and_then(|mapping| mapping.get(&mix).copied());
	if let Some(handle) = handle {
		// Do not inspect TURF_GASES here. This proc is called while gas locks are
		// held by the heat worker; recursively taking TURF_GASES.read() deadlocks
		// if an explosion/topology writer queued between the two reads. Immutable
		// boundary cells are harmlessly filtered when the active queue is consumed.
		ACTIVE_TURFS
			.write()
			.as_mut()
			.unwrap()
			.activate_fresh(handle);
	}
}

const MAX_TURF_SEEDS_PER_GENERATION: usize = 4_096;
const MIN_TURF_SEEDS_PER_GENERATION: usize = 128;
const INITIAL_TURF_SEEDS_PER_GENERATION: usize = 1_024;
static TURF_SEED_LIMIT: AtomicUsize = AtomicUsize::new(INITIAL_TURF_SEEDS_PER_GENERATION);

fn take_active_turfs(
	_arena: &TurfGases,
	limit: usize,
	excluded: &FxHashSet<CellHandle>,
) -> FxHashSet<CellHandle> {
	ACTIVE_TURFS.write().as_mut().unwrap().take_unseen(
		limit.clamp(MIN_TURF_SEEDS_PER_GENERATION, MAX_TURF_SEEDS_PER_GENERATION),
		excluded,
	)
}

pub(super) fn turf_seed_limit() -> usize {
	TURF_SEED_LIMIT.load(Ordering::Acquire)
}

pub(super) fn adapt_turf_seed_limit(elapsed_ms: f32, target_ms: f32) {
	let old = turf_seed_limit();
	let ratio = (target_ms / elapsed_ms.max(1.0)).clamp(0.5, 2.0);
	let proposed = (old as f32 * ratio) as usize;
	// Smooth the controller so one unusually cheap/expensive generation does not
	// make the following generation oscillate between the hard bounds.
	let next = ((old * 3 + proposed) / 4)
		.clamp(MIN_TURF_SEEDS_PER_GENERATION, MAX_TURF_SEEDS_PER_GENERATION);
	TURF_SEED_LIMIT.store(next, Ordering::Release);
}

pub(crate) fn mark_mix_urgent(mix: usize, pressure_delta_kpa: f32) {
	let severity = (pressure_delta_kpa.max(0.0).min(u32::MAX as f32 / 1_000.0) * 1_000.0) as u32;
	PRESSURE_URGENCY_MILLIKPA.fetch_max(severity, Ordering::AcqRel);
	let handle = MIX_TO_TURF
		.read()
		.as_ref()
		.and_then(|mapping| mapping.get(&mix).copied());
	if let Some(handle) = handle {
		ACTIVE_TURFS
			.write()
			.as_mut()
			.unwrap()
			.activate_urgent(handle);
	}
}

pub(super) fn begin_pressure_generation() -> f32 {
	let severity = PRESSURE_URGENCY_MILLIKPA.swap(0, Ordering::AcqRel);
	PRESSURE_URGENCY_INFLIGHT_MILLIKPA.store(severity, Ordering::Release);
	severity as f32 / 1_000.0
}

pub(super) fn finish_pressure_generation() {
	PRESSURE_URGENCY_INFLIGHT_MILLIKPA.store(0, Ordering::Release);
}

/// A cancelled topology generation did not consume its pressure event. Return
/// its urgency to the pending lane so the replacement graph is serviced at the
/// same cadence instead of silently degrading to routine 1 Hz work.
pub(super) fn abort_pressure_generation() {
	let severity = PRESSURE_URGENCY_INFLIGHT_MILLIKPA.swap(0, Ordering::AcqRel);
	PRESSURE_URGENCY_MILLIKPA.fetch_max(severity, Ordering::AcqRel);
}

pub(super) fn current_pressure_urgency_kpa() -> f32 {
	PRESSURE_URGENCY_MILLIKPA
		.load(Ordering::Acquire)
		.max(PRESSURE_URGENCY_INFLIGHT_MILLIKPA.load(Ordering::Acquire)) as f32
		/ 1_000.0
}

fn reactivate_cells(ids: impl IntoIterator<Item = CellHandle>) {
	let mut active = ACTIVE_TURFS.write();
	let active = active.as_mut().unwrap();
	for handle in ids {
		active.activate_frontier(handle);
	}
}

fn reactivate_urgent_cells(ids: impl IntoIterator<Item = CellHandle>, pressure_delta_kpa: f32) {
	let severity = (pressure_delta_kpa.max(0.0).min(u32::MAX as f32 / 1_000.0) * 1_000.0) as u32;
	PRESSURE_URGENCY_MILLIKPA.fetch_max(severity, Ordering::AcqRel);
	let mut active = ACTIVE_TURFS.write();
	let active = active.as_mut().unwrap();
	for handle in ids {
		active.activate_urgent(handle);
	}
}

fn remove_active_handle(handle: CellHandle) {
	ACTIVE_TURFS.write().as_mut().unwrap().remove(handle);
}

pub(super) fn pending_active_turfs() -> usize {
	ACTIVE_TURFS.read().as_ref().map_or(0, ActiveTurfs::len)
}

pub(super) fn pending_active_turf_queue_counts() -> (usize, usize, usize) {
	ACTIVE_TURFS
		.read()
		.as_ref()
		.map_or((0, 0, 0), ActiveTurfs::queue_counts)
}

/// Diagnostic/test query for one authoritative cell. Gameplay never polls this;
/// it exists so convergence tests can distinguish their local frontier from
/// unrelated map activity.
#[auxmacros::bind("/turf/proc/auxmos_is_atmos_active")]
fn turf_active_hook(src: ByondValue) -> Result<ByondValue> {
	let id = src.get_ref()?;
	let handle = with_turf_gases_read(|arena| {
		arena
			.get_id(id)
			.and_then(|node| arena.get(node))
			.map(TurfMixture::handle)
	});
	Ok(handle
		.is_some_and(|handle| {
			ACTIVE_TURFS
				.read()
				.as_ref()
				.is_some_and(|active| active.contains(handle))
		})
		.into())
}

pub(super) fn turf_arena_diagnostics() -> (usize, usize, usize, usize, usize, usize) {
	with_turf_gases_read(|arena| {
		let (node_capacity, edge_capacity) = arena.graph.capacity();
		(
			arena.map.len(),
			arena.map.capacity(),
			arena.graph.node_count(),
			arena.graph.edge_count(),
			node_capacity,
			edge_capacity,
		)
	})
}

#[byondapi::init]
pub fn initialize_turfs() {
	*TURF_GASES.write() = Some(TurfGases {
		graph: StableDiGraph::with_capacity(4096, 16_384),
		map: IndexMap::with_capacity_and_hasher(4096, FxBuildHasher),
		generations: FxHashMap::default(),
	});
	*PLANETARY_ATMOS.write() = Some(Default::default());
	*ACTIVE_TURFS.write() = Some(Default::default());
	*MIX_TO_TURF.write() = Some(Default::default());
	*AIR_CELLS.write() = Some(Default::default());
}

pub(super) fn reserve_turf_capacity(nodes: usize, _edges: usize) {
	with_turf_gases_write(|arena| {
		let map_capacity = arena.map.capacity();
		arena.map.reserve(nodes.saturating_sub(map_capacity));
	});
	with_air_cells_mut(|cells| {
		let capacity = cells.masks.capacity();
		cells.masks.reserve(nodes.saturating_sub(capacity));
	});
}

pub fn shutdown_turfs() {
	wait_for_tasks();
	TURF_GASES.write().as_mut().unwrap().clear();
	PLANETARY_ATMOS.write().as_mut().unwrap().clear();
	*ACTIVE_TURFS.write() = Some(Default::default());
	MIX_TO_TURF.write().as_mut().unwrap().clear();
	with_air_cells_mut(|cells| {
		cells.masks.clear();
		cells.z_links.clear();
	});
}

fn with_turf_gases_read<T, F>(f: F) -> T
where
	F: FnOnce(&TurfGases) -> T,
{
	f(TURF_GASES.read().as_ref().unwrap())
}

fn with_turf_gases_write<T, F>(f: F) -> T
where
	F: FnOnce(&mut TurfGases) -> T,
{
	f(TURF_GASES.write().as_mut().unwrap())
}

fn apply_topology_update(arena: &mut TurfGases, update: PendingTopologyUpdate) {
	match update {
		PendingTopologyUpdate::Insert(mixture) => {
			let id = mixture.id;
			let mix = mixture.mix;
			let mutable = !mixture.is_immutable();
			if let Some(previous) = arena
				.get_id(id)
				.and_then(|node| arena.get(node))
				.map(|cell| (cell.mix, cell.handle()))
			{
				if previous.0 != mix {
					// Only drop the old mix -> turf mapping if it still points at
					// THIS handle. A shared immutable mixture (e.g. the static
					// vacuum instance every space turf points `air` at) can have
					// its mix id mapped to a different, still-live turf by the
					// time this one is replaced; blindly removing here would
					// orphan that other turf's entry even though its cell is
					// still very much alive in the arena.
					let mut mix_to_turf = MIX_TO_TURF.write();
					let map = mix_to_turf.as_mut().unwrap();
					if map.get(&previous.0) == Some(&previous.1) {
						map.remove(&previous.0);
					}
					drop(mix_to_turf);
					remove_active_handle(previous.1);
				}
			}
			arena.insert_turf(mixture);
			let handle = arena
				.get_id(id)
				.and_then(|node| arena.get(node))
				.expect("inserted turf missing from arena")
				.handle();
			MIX_TO_TURF.write().as_mut().unwrap().insert(mix, handle);
			if mutable {
				ACTIVE_TURFS
					.write()
					.as_mut()
					.unwrap()
					.activate_fresh(handle);
			}
			if with_air_cells(|cells| arena.sync_edges(id, cells)) {
				activate_topology_change(arena, id);
			}
		}
		PendingTopologyUpdate::Remove(id) => {
			// Turf IDs can be reused by BYOND after ChangeTurf. Never leave the old
			// mutable cell scheduled after its arena node has been removed (notably
			// when expedition teardown replaces a whole z-level with immutable space).
			if let Some((mix, handle)) = arena
				.get_id(id)
				.and_then(|node| arena.get(node))
				.map(|mixture| (mixture.mix, mixture.handle()))
			{
				remove_active_handle(handle);
				// Same shared-mixture caveat as the Insert arm above: many live
				// turfs (all of space) can carry this exact mix id. Only clear
				// the mapping if it still refers to the turf being removed, so
				// removing one space turf never orphans the mapping for every
				// other space turf still sharing the vacuum mixture.
				let mut mix_to_turf = MIX_TO_TURF.write();
				let map = mix_to_turf.as_mut().unwrap();
				if map.get(&mix) == Some(&handle) {
					map.remove(&mix);
				}
			}
			// The cells that shared air with this one lost a face: wake them.
			let neighbours = arena
				.get_id(id)
				.map(|node| {
					arena
						.adjacent_node_ids(node)
						.filter_map(|n| arena.get(n).filter(|c| !c.is_immutable()))
						.map(TurfMixture::handle)
						.collect::<Vec<_>>()
				})
				.unwrap_or_default();
			arena.remove_turf(id);
			reactivate_cells(neighbours);
		}
		PendingTopologyUpdate::ResyncAll => {
			let ids = arena.map.keys().copied().collect::<Vec<_>>();
			with_air_cells(|cells| {
				for id in ids {
					arena.sync_edges(id, cells);
				}
			});
		}
	}
}

/// A topology change is itself an atmospheric mutation. Activate both endpoints
/// once the graph is authoritative, and promote a mutable cell beside a large
/// immutable pressure reservoir straight to the urgent queue, so a freshly
/// breached space boundary cannot be missed.
fn activate_topology_change(arena: &TurfGases, id: TurfID) {
	let mut handles = Vec::new();
	if let Some(node) = arena.get_id(id) {
		if let Some(cell) = arena.get(node).filter(|cell| !cell.is_immutable()) {
			handles.push((cell.handle(), topology_pressure_urgency(arena, node)));
		}
		for neighbor in arena.adjacent_node_ids(node) {
			if let Some(cell) = arena.get(neighbor).filter(|cell| !cell.is_immutable()) {
				handles.push((cell.handle(), topology_pressure_urgency(arena, neighbor)));
			}
		}
	}
	let mut active = ACTIVE_TURFS.write();
	let active = active.as_mut().unwrap();
	for (handle, urgency) in handles {
		if urgency >= 20.0 {
			PRESSURE_URGENCY_MILLIKPA.fetch_max((urgency * 1_000.0) as u32, Ordering::AcqRel);
			active.activate_urgent(handle);
		} else {
			active.activate_fresh(handle);
		}
	}
}

/// Largest pressure jump from a mutable cell to an immutable boundary in the
/// already-published topology. Used only on structural updates, not in the hot
/// solver loop.
fn topology_pressure_urgency(arena: &TurfGases, node: NodeIndex) -> f32 {
	let Some(source) = arena.get(node) else {
		return 0.0;
	};
	GasArena::with_all_mixtures(|mixtures| {
		let Some(source_gas) = mixtures.get(source.mix).and_then(RwLock::try_read) else {
			return 0.0;
		};
		let source_pressure = source_gas.return_pressure();
		arena
			.adjacent_node_ids(node)
			.filter_map(|neighbor| arena.get(neighbor).filter(|cell| cell.is_immutable()))
			.filter_map(|cell| mixtures.get(cell.mix).and_then(RwLock::try_read))
			.map(|gas| (source_pressure - gas.return_pressure()).abs())
			.fold(0.0_f32, f32::max)
	})
}

fn apply_or_queue_topology_update(update: PendingTopologyUpdate) {
	if TOPOLOGY_TRANSACTION_OPEN.load(Ordering::Acquire) {
		TOPOLOGY_TRANSACTION.lock().push(update);
		return;
	}
	if TOPOLOGY_BATCH_OPEN.load(Ordering::Acquire) {
		PENDING_TOPOLOGY.write().push(update);
		return;
	}
	// Gas revisions reject stale diffusion writes after synchronous gas changes.
	// Topology changes need the same protection: a shuttle move or dynamic map
	// load can otherwise let an in-flight snapshot publish against its old graph.
	TURF_TOPOLOGY_GENERATION.fetch_add(1, Ordering::AcqRel);
	if let Some(_task_barrier) = TASKS.try_write() {
		with_turf_gases_write(|arena| apply_topology_update(arena, update));
	} else {
		PENDING_TOPOLOGY.write().push(update);
	}
}

pub(super) fn apply_pending_topology_updates() {
	let pending = std::mem::take(&mut *PENDING_TOPOLOGY.write());
	if pending.is_empty() {
		return;
	}
	with_turf_gases_write(|arena| {
		for update in pending {
			apply_topology_update(arena, update);
		}
	});
}

fn with_planetary_atmos<T, F>(f: F) -> T
where
	F: FnOnce(&IndexMap<u32, Mixture, FxBuildHasher>) -> T,
{
	f(PLANETARY_ATMOS.read().as_ref().unwrap())
}

fn with_planetary_atmos_upgradeable_read<T, F>(f: F) -> T
where
	F: FnOnce(RwLockUpgradableReadGuard<'_, Option<IndexMap<u32, Mixture, FxBuildHasher>>>) -> T,
{
	f(PLANETARY_ATMOS.upgradable_read())
}

/// World dimensions for turf-index neighbour arithmetic. Reading world vars
/// from Rust is unreliable on BYOND 516, so DM pushes them.
fn set_world_dims_impl(max_x: i32, max_y: i32) {
	let dims = u32::try_from(max_x)
		.ok()
		.zip(u32::try_from(max_y).ok())
		.and_then(|(x, y)| GridDims::planar(x, y));
	with_air_cells_mut(|cells| cells.dims = dims);
}

/// Args: (maxx, maxy). Called by SSair init before any turf registers.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_set_world_dims")]
fn set_world_dims(max_x: ByondValue, max_y: ByondValue) -> Result<ByondValue> {
	set_world_dims_impl(max_x.get_number()? as i32, max_y.get_number()? as i32);
	Ok(ByondValue::null())
}

/// Args: (maxx, maxy, maxz). Sets the world dimensions and reserves arena room
/// for a whole map. Called at world start and when the map grows.
#[auxmacros::bind("/proc/auxmos_configure_world")]
fn configure_world(max_x: ByondValue, max_y: ByondValue, max_z: ByondValue) -> Result<ByondValue> {
	let max_x = max_x.get_number()? as i32;
	let max_y = max_y.get_number()? as i32;
	let max_z = max_z.get_number()? as i32;
	set_world_dims_impl(max_x, max_y);
	let tiles = (max_x.max(1) as usize)
		.saturating_mul(max_y.max(1) as usize)
		.saturating_mul(max_z.max(1) as usize);
	let edges = tiles.saturating_mul(4);
	reserve_turf_capacity(tiles, edges);
	#[cfg(feature = "heat")]
	heat::configure_heat(max_x.max(1) as u32, max_y.max(1) as u32, max_z.max(1) as u32)?;
	crate::gas::reserve_gas_capacity(tiles.saturating_add(8192));
	Ok(ByondValue::null())
}

/// Args: (links). A positional list with one entry per z-level: the `UP`/`DOWN`
/// bits of the levels air may cross into. Vertical adjacency needs both sides
/// linked. Every cell's edges are re-synced.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_set_z_links")]
fn set_z_links(links: ByondValue) -> Result<ByondValue> {
	// get_list_values, not iter(): iter() indexes the list by each item, so a
	// plain list of numbers stops at the first 0.
	let links = links
		.get_list_values()?
		.iter()
		.map(|value| value.get_number().unwrap_or(0.0) as u8)
		.collect::<Vec<_>>();
	with_air_cells_mut(|cells| cells.z_links = links);
	apply_or_queue_topology_update(PendingTopologyUpdate::ResyncAll);
	Ok(ByondValue::null())
}

/// Args: (flag, mask). Registers (flag >= 0) or removes (flag < 0) this turf's
/// air in the arena and publishes its air-block mask (`AIR_BLOCK_KEEP` keeps the
/// current one). Rust reads blocks_air, air, immutable_atmos, planetary_atmos
/// and initial_gas_mix, and rebuilds the turf's adjacency from the masks.
#[auxmacros::bind("/turf/proc/update_air_ref")]
fn hook_register_turf(src: ByondValue, flag: ByondValue, mask: ByondValue) -> Result<ByondValue> {
	let flag = flag.get_number()? as i32;
	let visibility = crate::gas::visibility_copies();
	register_turf_impl(src, flag, mask_from_value(&mask), &visibility)?;
	Ok(ByondValue::null())
}

fn mask_from_value(mask: &ByondValue) -> Option<u8> {
	mask.get_number()
		.ok()
		.filter(|&m| m >= 0.0)
		.map(|m| (m as u8) & AIR_BLOCK_ALL)
}

/// Monotonic revision of this turf's gas mixture. Consumers can skip expensive
/// polling while the value is unchanged.
#[auxmacros::bind("/turf/proc/air_revision")]
fn hook_air_revision(src: ByondValue) -> Result<ByondValue> {
	let id = src.get_ref()?;
	let revision = with_turf_gases_read(|arena| {
		arena
			.get_id(id)
			.and_then(|node| arena.get(node))
			.map_or(0, |mixture| GasArena::revision(mixture.mix))
	});
	Ok((revision as f32).into())
}

/// Bulk registration for round start and map loads. Args: (turfs, flag), where
/// `turfs` is an assoc list of turf -> air-block mask. One FFI entry registers the
/// whole batch and builds its adjacency; afterwards only cells that actually
/// differ from a neighbour stay scheduled, so equal station air is not queued.
#[auxmacros::bind("/proc/_auxmos_register_turfs_bulk")]
fn hook_register_turfs_bulk(list: ByondValue, flag: ByondValue) -> Result<ByondValue> {
	let flag = flag.get_number()? as i32;
	let visibility = crate::gas::visibility_copies();
	let turfs = list.iter()?.collect::<Vec<_>>();
	for (turf, mask) in &turfs {
		register_turf_impl(*turf, flag, mask_from_value(mask), &visibility)?;
	}
	for (turf, _) in turfs {
		let id = turf.get_ref()?;
		if !turf_has_material_gradient(id) {
			if let Some(handle) = with_turf_gases_read(|arena| {
				arena
					.get_id(id)
					.and_then(|node| arena.get(node))
					.map(TurfMixture::handle)
			}) {
				remove_active_handle(handle);
			}
		}
	}
	Ok(ByondValue::null())
}

fn register_turf_impl(
	src: ByondValue,
	flag: i32,
	mask: Option<u8>,
	visibility: &[Option<f32>],
) -> Result<()> {
	let id = src.get_ref()?;
	if let Ok(blocks) = src.read_number_id(byond_string!("blocks_air")) {
		if blocks > 0.0 {
			with_air_cells_mut(|cells| cells.masks.remove(&id));
			apply_or_queue_topology_update(PendingTopologyUpdate::Remove(id));
			return Ok(());
		}
	}
	if flag >= 0 {
		let mut to_insert: TurfMixture = TurfMixture::default();
		let air = src.read_var_id(byond_string!("air"))?;
		to_insert.mix = air.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize;
		if src
			.read_number_id(byond_string!("immutable_atmos"))
			.unwrap_or(0.0)
			!= 0.0
		{
			to_insert.immutable = true;
			to_insert.mark_immutable();
		}
		to_insert.flags = SimulationFlags::from_bits_truncate(flag as u8);
		to_insert.id = id;
		// Ordinary station air has no gas overlay. Prime its visibility hash at
		// registration so the first whole-map generation does not queue one
		// no-op BYOND callback per turf. Visible maploaded gas keeps the zero
		// sentinel and receives the normal initial overlay update.
		let (is_visible, vis_hash) = GasArena::with_gas_mixture(to_insert.mix, |gas| {
			Ok((gas.is_visible(), gas.vis_hash(visibility)))
		})?;
		if !is_visible {
			to_insert
				.vis_hash
				.store(vis_hash, std::sync::atomic::Ordering::Relaxed);
		}

		if let Ok(is_planet) = src.read_number_id(byond_string!("planetary_atmos")) {
			if is_planet != 0.0 {
				if let Ok(at_str) = src.read_string_id(byond_string!("initial_gas_mix")) {
					with_planetary_atmos_upgradeable_read(|lock| {
						to_insert.planetary_atmos = Some({
							let mut state = rustc_hash::FxHasher::default();
							at_str.hash(&mut state);
							state.finish() as u32
						});
						if lock
							.as_ref()
							.unwrap()
							.contains_key(&to_insert.planetary_atmos.unwrap())
						{
							return;
						}

						let mut write =
							parking_lot::lock_api::RwLockUpgradableReadGuard::upgrade(lock);

						write
							.as_mut()
							.unwrap()
							.insert(to_insert.planetary_atmos.unwrap(), {
								let mut gas = to_insert.get_gas_copy();
								gas.mark_immutable();
								gas
							});
					});
				}
			}
		}
		// A re-registration that keeps the mask (a device waking the turf) changes
		// no topology, so it must not touch the heat graph either.
		let topology_changed = with_air_cells_mut(|cells| match cells.masks.get_mut(&id) {
			Some(current) => mask.is_some_and(|mask| std::mem::replace(current, mask) != mask),
			None => {
				cells.masks.insert(id, mask.unwrap_or(0));
				true
			}
		});
		apply_or_queue_topology_update(PendingTopologyUpdate::Insert(to_insert));
		// Heat takes turf values from DM (update_heat_cell), not from here.
		let _ = topology_changed;
	} else {
		with_air_cells_mut(|cells| cells.masks.remove(&id));
		apply_or_queue_topology_update(PendingTopologyUpdate::Remove(id));
	}
	Ok(())
}

/// True when a newly published round-start cell actually differs from one of
/// its neighbors. This preserves authored pressure/composition/temperature
/// gradients without scheduling tens of thousands of already-equal cells.
fn turf_has_material_gradient(id: TurfID) -> bool {
	with_turf_gases_read(|arena| {
		let Some(node) = arena.get_id(id) else {
			return false;
		};
		let Some(cell) = arena.get(node) else {
			return false;
		};
		if cell.is_immutable() {
			return false;
		}
		GasArena::with_all_mixtures(|mixtures| {
			let Some(gas) = mixtures.get(cell.mix).map(|entry| entry.read()) else {
				return false;
			};
			arena.adjacent_mixes(node, mixtures).any(|entry| {
				let adjacent = entry.read();
				gas.temperature_compare(&adjacent)
					|| gas.compare_with(&adjacent, MINIMUM_MOLES_DELTA_TO_MOVE)
			})
		})
	})
}

fn turf_value(id: TurfID) -> ByondValue {
	ByondValue::new_ref(ValueType::Turf, id)
}

fn adjacent_turf_list(id: TurfID, cells: &AirCells) -> Result<ByondValue> {
	let list = ByondValue::new_list()?;
	let turfs = cells.open_neighbors(id).map(turf_value).collect::<Vec<_>>();
	list.write_list(&turfs)?;
	Ok(list)
}

/// Returns: the turfs this turf shares air with (face neighbours only).
#[auxmacros::bind("/proc/atmos_adjacent_turfs")]
fn atmos_adjacent_turfs(turf: ByondValue) -> Result<ByondValue> {
	let id = turf.get_ref()?;
	with_air_cells(|cells| adjacent_turf_list(id, cells))
}

/// Batched form of `atmos_adjacent_turfs`. Args: (list of turfs). Returns a list
/// of lists, one per input turf, in order.
#[auxmacros::bind("/proc/atmos_adjacent_turfs_bulk")]
fn atmos_adjacent_turfs_bulk(turfs: ByondValue) -> Result<ByondValue> {
	let ids = turfs
		.get_list_values()?
		.iter()
		.map(ByondValue::get_ref)
		.collect::<Result<Vec<_>, _>>()?;
	with_air_cells(|cells| {
		let lists = ids
			.into_iter()
			.map(|id| adjacent_turf_list(id, cells))
			.collect::<Result<Vec<_>>>()?;
		let out = ByondValue::new_list()?;
		out.write_list(&lists)?;
		Ok(out)
	})
}

/// Returns: the direction bits (NORTH..DOWN) across which this turf shares air.
#[auxmacros::bind("/proc/atmos_open_dirs")]
fn atmos_open_dirs(turf: ByondValue) -> Result<ByondValue> {
	let id = turf.get_ref()?;
	Ok(f32::from(with_air_cells(|cells| cells.open_dirs(id))).into())
}

/// Diagnostic: what Rust holds for this turf, as list(registered, mask, z-level
/// links, zero-based z). Tests use it to explain a missing edge.
#[auxmacros::bind("/proc/atmos_cell_info")]
fn atmos_cell_info(turf: ByondValue) -> Result<ByondValue> {
	let id = turf.get_ref()?;
	let values = with_air_cells(|cells| {
		let z = cells.dims.map_or(0, |dims| id / dims.layer_len());
		let mask = cells.masks.get(&id).copied();
		[
			f32::from(u8::from(mask.is_some())),
			f32::from(mask.unwrap_or(AIR_BLOCK_ALL)),
			f32::from(cells.z_links.get(z as usize).copied().unwrap_or(0)),
			z as f32,
		]
	});
	let list = ByondValue::new_list()?;
	list.write_list(&values.map(ByondValue::from))?;
	Ok(list)
}

/// Returns: whether two turfs are face neighbours that share air.
#[auxmacros::bind("/proc/atmos_turfs_share")]
fn atmos_turfs_share(first: ByondValue, second: ByondValue) -> Result<ByondValue> {
	let (first, second) = (first.get_ref()?, second.get_ref()?);
	Ok(with_air_cells(|cells| cells.open_neighbors(first).any(|n| n == second)).into())
}

/// Diagnostic invariant for shuttle/atmos tests: once queued updates apply, the
/// solver graph's edges for this turf (both directions) match the adjacency the
/// masks describe, and the graph holds the turf's current mixture.
#[auxmacros::bind("/proc/_auxmos_topology_matches")]
fn topology_matches(src: ByondValue) -> Result<ByondValue> {
	if let Some(_task_barrier) = TASKS.try_write() {
		apply_pending_topology_updates();
	}
	let id = src.get_ref()?;
	let expected_mix = src
		.read_var_id(byond_string!("air"))?
		.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize;
	let open = with_air_cells(|cells| cells.open_neighbors(id).collect::<Vec<_>>());
	let (mut expected, mut actual, mut incoming, actual_mix) = with_turf_gases_read(|arena| {
		// sync_edges gives two immutable cells no solver edge.
		let immutable = |cell: TurfID| {
			arena
				.get_from_id(cell)
				.is_some_and(TurfMixture::is_immutable)
		};
		let expected = open
			.iter()
			.copied()
			.filter(|&other| !(immutable(id) && immutable(other)))
			.collect::<Vec<_>>();
		let outgoing = arena
			.get_id(id)
			.into_iter()
			.flat_map(|node| arena.graph.edges_directed(node, Direction::Outgoing))
			.filter_map(|edge| arena.graph.node_weight(edge.target()).map(|mix| mix.id))
			.collect::<Vec<_>>();
		let reverse = arena
			.get_id(id)
			.into_iter()
			.flat_map(|node| arena.graph.edges_directed(node, Direction::Incoming))
			.filter_map(|edge| arena.graph.node_weight(edge.source()).map(|mix| mix.id))
			.collect::<Vec<_>>();
		let mix = arena
			.get_id(id)
			.and_then(|node| arena.get(node))
			.map(|turf| turf.mix);
		(expected, outgoing, reverse, mix)
	});
	expected.sort_unstable();
	actual.sort_unstable();
	actual.dedup();
	incoming.sort_unstable();
	incoming.dedup();
	Ok(ByondValue::from(
		expected == actual && expected == incoming && actual_mix == Some(expected_mix),
	))
}

/// Updates the visual overlays for the given turf.
/// Will use a cached overlay list if one exists.
/// # Errors
/// If auxgm wasn't implemented properly or there's an invalid gas mixture.
fn update_visuals(src: ByondValue) -> Result<ByondValue> {
	use super::gas;
	match src.read_var_id(byond_string!("air")) {
		Ok(air) if !air.is_null() => {
			// gas_overlays: a positional list, entry GAS_ID + 1 = list(VIS_FACTOR = OVERLAY).
			let gas_overlays = ByondValue::new_global_ref()
				.read_var_id(byond_string!("GLOB"))
				.wrap_err("Unable to get GLOB from BYOND globals")?
				.read_var_id(byond_string!("gas_data"))
				.wrap_err("gas_data is undefined on GLOB")?
				.read_var_id(byond_string!("overlays"))
				.wrap_err("overlays is undefined in GLOB.gas_data")?;
			let ptr = air
				.read_var_id(byond_string!("_extools_pointer_gasmixture"))
				.wrap_err("air is undefined on turf")?
				.get_number()
				.wrap_err("Gas mixture has invalid pointer")? as usize;
			let overlay_types = GasArena::with_gas_mixture(ptr, |mix| {
				Ok(mix
					.enumerate()
					.filter_map(|(idx, moles)| Some((idx, moles, gas::types::gas_visibility(idx)?)))
					.filter(|(_, moles, amt)| moles > amt)
					// getting the list(VIS_FACTORS = OVERLAYS) with GAS_ID
					.filter_map(|(idx, moles, _)| {
						Some((gas_overlays.read_list_index((idx + 1) as f32).ok()?, moles))
					})
					// getting the OVERLAYS with VIS_FACTOR
					.filter_map(|(this_overlay_list, moles)| {
						this_overlay_list
							.read_list_index(gas::mixture::visibility_step(moles) as f32)
							.ok()
					})
					.collect::<Vec<_>>())
			})?;

			Ok(src
				.call_id(
					byond_string!("set_visuals"),
					&[overlay_types.as_slice().try_into()?],
				)
				.wrap_err("Calling set_visuals")?)
		}
		// If air is null, clear the visuals
		Ok(_) => Ok(src
			.call_id(byond_string!("set_visuals"), &[])
			.wrap_err("Calling set_visuals with no args")?),
		// If air is not defined, it must be a closed turf. Do .othing
		Err(_) => Ok(ByondValue::null()),
	}
}

/// Bounds-checked neighbour iteration for the heat graph (B1: this used to be
/// raw `i ± 1` / `i ± max_x` arithmetic that wrapped across the east/west map
/// edge and from the top row into the next z-level).
#[derive(Clone, Copy)]
struct AdjacentTileIDs {
	adj: Directions,
	i: TurfID,
	dims: Option<GridDims>,
	count: u8,
}

impl Iterator for AdjacentTileIDs {
	type Item = (Directions, TurfID);

	fn next(&mut self) -> Option<Self::Item> {
		let dims = self.dims?;
		while self.count < 6 {
			let bit = self.count;
			self.count += 1;
			let dir = Directions::from_bits_retain(1 << bit);
			if !self.adj.contains(dir) {
				continue;
			}
			let face = Face::from_bit_index(bit)?;
			if let Some(neighbor) = dims.neighbor(self.i, face) {
				return Some((dir, neighbor));
			}
		}
		None
	}

	fn size_hint(&self) -> (usize, Option<usize>) {
		(0, Some(self.adj.bits().count_ones() as usize))
	}
}

use std::iter::FusedIterator;

impl FusedIterator for AdjacentTileIDs {}

#[allow(unused)]
fn adjacent_tile_ids(adj: Directions, i: TurfID, max_x: i32, max_y: i32) -> AdjacentTileIDs {
	let dims = u32::try_from(max_x)
		.ok()
		.zip(u32::try_from(max_y).ok())
		.and_then(|(max_x, max_y)| GridDims::planar(max_x, max_y));
	AdjacentTileIDs {
		adj,
		i,
		dims,
		count: 0,
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	/// Regression for B1: heat neighbours must not wrap across the map edge.
	#[test]
	fn adjacent_tile_ids_do_not_wrap_at_map_edges() {
		// 3x2 map, z-level 1: indices 0..6, row-major from the south-west.
		let collect = |i| {
			adjacent_tile_ids(Directions::ALL_CARDINALS, i, 3, 2)
				.map(|(_, id)| id)
				.collect::<Vec<_>>()
		};
		// East edge of the bottom row: no east neighbour (was 3, the next row).
		assert_eq!(collect(2), vec![5, 1]);
		// West edge of the top row: no west neighbour (was 2, the previous row).
		assert_eq!(collect(3), vec![0, 4]);
		// Top-right corner: no north neighbour (was 8, on the next z-level).
		assert_eq!(collect(5), vec![2, 4]);
		assert_eq!(
			adjacent_tile_ids(Directions::ALL_CARDINALS, 0, 0, 2).count(),
			0
		);
	}

	fn empty_arena() -> TurfGases {
		TurfGases {
			graph: StableDiGraph::default(),
			map: IndexMap::with_hasher(FxBuildHasher),
			generations: FxHashMap::default(),
		}
	}

	#[test]
	fn recycled_turf_ids_invalidate_old_handles() {
		let mut arena = empty_arena();
		arena.insert_turf(TurfMixture {
			id: 7,
			mix: 1,
			..Default::default()
		});
		let first = arena.get_from_id(7).unwrap().handle();
		arena.remove_turf(7);
		arena.insert_turf(TurfMixture {
			id: 7,
			mix: 2,
			..Default::default()
		});
		let second = arena.get_from_id(7).unwrap().handle();
		assert_ne!(first, second);
		assert!(arena.get_handle(first).is_none());
		assert!(arena.get_handle(second).is_some());
	}

	/// A 3x3x2 world; masks for the given ids, z-levels 0 and 1 linked.
	fn cells(masks: &[(TurfID, u8)]) -> AirCells {
		AirCells {
			dims: GridDims::planar(3, 3),
			masks: masks.iter().copied().collect(),
			z_links: vec![Face::Up.bit(), Face::Down.bit()],
		}
	}

	fn arena_with(ids: &[TurfID]) -> TurfGases {
		let mut arena = empty_arena();
		for &id in ids {
			arena.insert_turf(TurfMixture {
				id,
				mix: id as usize,
				..Default::default()
			});
		}
		arena
	}

	fn linked(arena: &TurfGases, a: TurfID, b: TurfID) -> (bool, bool) {
		let (a, b) = (arena.get_id(a).unwrap(), arena.get_id(b).unwrap());
		(
			arena.graph.find_edge(a, b).is_some(),
			arena.graph.find_edge(b, a).is_some(),
		)
	}

	#[test]
	fn masks_build_symmetric_face_edges_in_any_order() {
		// Row 0: cells 0, 1, 2. Sync in both orders; the result is the same.
		let air = cells(&[(0, 0), (1, 0), (2, 0)]);
		for order in [[0, 1, 2], [2, 1, 0]] {
			let mut arena = arena_with(&[0, 1, 2]);
			for id in order {
				arena.sync_edges(id, &air);
			}
			assert_eq!(linked(&arena, 0, 1), (true, true));
			assert_eq!(linked(&arena, 1, 2), (true, true));
			assert_eq!(arena.graph.edge_count(), 4, "one edge each way per face");
		}
	}

	#[test]
	fn either_side_blocking_a_face_removes_both_edges() {
		let mut arena = arena_with(&[0, 1]);
		arena.sync_edges(0, &cells(&[(0, 0), (1, 0)]));
		assert_eq!(linked(&arena, 0, 1), (true, true));
		// A door on cell 1 closes its WEST face (towards cell 0).
		let closed = cells(&[(0, 0), (1, Face::West.bit())]);
		assert!(arena.sync_edges(1, &closed));
		assert_eq!(linked(&arena, 0, 1), (false, false));
		// A directional blocker on cell 0's EAST face blocks the same edge.
		let directional = cells(&[(0, Face::East.bit()), (1, 0)]);
		assert!(!arena.sync_edges(0, &directional), "already closed");
		assert_eq!(directional.open_neighbor(0, Face::East), None);
		assert_eq!(directional.open_neighbor(1, Face::West), None);
		// Blocking an unrelated face leaves the edge alone.
		let open = cells(&[(0, Face::North.bit()), (1, 0)]);
		assert!(arena.sync_edges(0, &open));
		assert_eq!(linked(&arena, 0, 1), (true, true));
	}

	#[test]
	fn unregistered_cells_and_map_edges_have_no_neighbours() {
		let air = cells(&[(2, 0), (5, 0)]);
		// Cell 2 is the east end of row 0: no east neighbour, and cell 3 (the
		// next row's west end) must not be reached by wrapping.
		assert_eq!(air.open_neighbor(2, Face::East), None);
		assert_eq!(
			air.open_neighbor(2, Face::West),
			None,
			"cell 1 is unregistered"
		);
		assert_eq!(air.open_neighbor(2, Face::North), Some(5));
		assert_eq!(air.open_dirs(2), Face::North.bit());
	}

	#[test]
	fn vertical_adjacency_needs_linked_levels_and_open_faces() {
		// Cell 4 on z0 and cell 13 above it on z1.
		let mut air = cells(&[(4, 0), (13, 0)]);
		assert_eq!(air.open_neighbor(4, Face::Up), Some(13));
		assert_eq!(air.open_neighbor(13, Face::Down), Some(4));
		// A floor on the upper cell blocks its DOWN face.
		air.masks.insert(13, Face::Down.bit());
		assert_eq!(air.open_neighbor(4, Face::Up), None);
		air.masks.insert(13, 0);
		// Unlinked levels never connect.
		air.z_links = vec![0, 0];
		assert_eq!(air.open_neighbor(4, Face::Up), None);
		assert_eq!(air.open_neighbor(13, Face::Down), None);
	}

	#[test]
	fn topology_updates_wait_for_generation_barrier() {
		// initialize_turfs() resets process-wide statics other tests use.
		let _globals = crate::gas::types::TEST_GAS_GLOBALS_LOCK.lock().unwrap();
		initialize_turfs();
		let id = 42;
		let mixture = TurfMixture {
			id,
			..Default::default()
		};
		let task = TASKS.read();
		apply_or_queue_topology_update(PendingTopologyUpdate::Insert(mixture));
		assert!(with_turf_gases_read(|arena| arena.get_id(id)).is_none());
		drop(task);
		apply_pending_topology_updates();
		assert!(with_turf_gases_read(|arena| arena.get_id(id)).is_some());

		let task = TASKS.read();
		apply_or_queue_topology_update(PendingTopologyUpdate::Remove(id));
		assert!(with_turf_gases_read(|arena| arena.get_id(id)).is_some());
		drop(task);
		apply_pending_topology_updates();
		assert!(with_turf_gases_read(|arena| arena.get_id(id)).is_none());
	}

	/// Reproduces the shared-vacuum-mixture scenario: many DM turfs (e.g. every
	/// `/turf/space`) can register with the exact same `mix` id, because DM now
	/// points them all at one cached immutable gas mixture instead of allocating
	/// one per turf. `MIX_TO_TURF` must never let removing/replacing one such
	/// turf orphan the mapping for the others that are still alive and sharing
	/// that mix id.
	#[test]
	fn shared_immutable_mix_survives_sibling_removal() {
		// initialize_turfs() resets process-wide statics other tests use.
		let _globals = crate::gas::types::TEST_GAS_GLOBALS_LOCK.lock().unwrap();
		initialize_turfs();
		const SHARED_MIX: usize = 999;

		let insert = |id: TurfID| {
			apply_or_queue_topology_update(PendingTopologyUpdate::Insert(TurfMixture {
				id,
				mix: SHARED_MIX,
				immutable: true,
				..Default::default()
			}));
		};
		insert(100);
		insert(101);
		apply_pending_topology_updates();

		let handle_101 = with_turf_gases_read(|arena| arena.get_from_id(101).unwrap().handle());
		assert_eq!(
			MIX_TO_TURF.read().as_ref().unwrap().get(&SHARED_MIX),
			Some(&handle_101),
			"MIX_TO_TURF should point at the most recently inserted sharer"
		);

		// Removing the turf that is NOT currently on record for the shared mix
		// must not touch the mapping at all.
		apply_or_queue_topology_update(PendingTopologyUpdate::Remove(100));
		apply_pending_topology_updates();
		assert_eq!(
			MIX_TO_TURF.read().as_ref().unwrap().get(&SHARED_MIX),
			Some(&handle_101),
			"removing a non-recorded sharer of an immutable mix must not orphan \
			 the mapping for the turf still on record"
		);

		// Turf 101 is still alive in the arena even though 100 was removed —
		// the shared mixture keeps working for every remaining sharer.
		assert!(with_turf_gases_read(|arena| arena
			.get_from_id(101)
			.is_some()));

		// Now remove the turf that IS on record: the mapping must finally clear,
		// since nothing else is tracked as holding it.
		apply_or_queue_topology_update(PendingTopologyUpdate::Remove(101));
		apply_pending_topology_updates();
		assert_eq!(MIX_TO_TURF.read().as_ref().unwrap().get(&SHARED_MIX), None);
	}
}
