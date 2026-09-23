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
	pub struct AdjacentFlags: u8 {
		const ATMOS_ADJACENT_FIRELOCK = 0b10;
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
	graph: StableDiGraph<TurfMixture, AdjacentFlags>,
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
	fn update_adjacencies_from_ids(&mut self, idx: TurfID, adjacent: &[(TurfID, u8)]) {
		if let Some(&this_index) = self.map.get(&idx) {
			self.remove_adjacencies(this_index);
			// DM callers may report the same neighbor through more than one legacy
			// adjacency path. Parallel graph edges make the diffusion stencil count
			// one physical face multiple times, which is both non-conservative and
			// topology-order dependent. Canonicalize every published face here.
			let mut resolved_by_node = FxHashMap::default();
			for (adj_ref, flag) in adjacent.iter().copied() {
				if let Some(&adj_index) = self.map.get(&adj_ref) {
					resolved_by_node
						.entry(adj_index)
						.and_modify(|existing| *existing |= flag)
						.or_insert(flag);
				}
			}
			let resolved = resolved_by_node
				.into_iter()
				.map(|(adj_index, flag)| (adj_index, flag))
				.collect::<Vec<_>>();
			// Diffusion across an edge is physically bidirectional even though the
			// graph stores separately published directed lists. Remove stale reverse
			// edges from neighbors that DM no longer considers adjacent, while
			// retaining valid reverse edges regardless of bulk publication order.
			let stale_incoming = self
				.graph
				.edges_directed(this_index, Direction::Incoming)
				.filter(|edge| !resolved.iter().any(|(node, _)| *node == edge.source()))
				.map(|edge| edge.id())
				.collect::<Vec<_>>();
			for edge in stale_incoming {
				self.graph.remove_edge(edge);
			}
			resolved.into_iter().for_each(|(adj_index, flag)| {
				let flags = AdjacentFlags::from_bits_truncate(flag);
				self.graph.add_edge(this_index, adj_index, flags);
				// Diffusion is physically undirected. Construct the reverse edge in
				// Rust instead of relying on a second, correctly ordered DM callback.
				if self.graph.find_edge(adj_index, this_index).is_none() {
					self.graph.add_edge(adj_index, this_index, flags);
				}
			})
		}
	}

	pub fn remove_adjacencies(&mut self, index: NodeIndex) {
		// Each turf publishes its own directed adjacency list. Incoming edges are
		// owned by neighboring turfs and must survive this replacement; deleting
		// them here makes a bulk republish order-dependent (each later turf would
		// erase the reverse edge just installed by an earlier one).
		let edges = self
			.graph
			.edges_directed(index, Direction::Outgoing)
			.map(|edgeref| edgeref.id())
			.collect::<Vec<_>>();
		edges.into_iter().for_each(|edgeindex| {
			self.graph.remove_edge(edgeindex);
		});
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
	Insert(TurfMixture),
	Remove(TurfID),
	Adjacencies(TurfID, Vec<(TurfID, u8)>),
	RemoveAdjacencies(TurfID),
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

fn mark_turf_active(turf: TurfID) {
	// Immutable space/planet mixtures are boundary conditions, not processing
	// cells. A mutable neighbor still shares against them through its edge; adding
	// every freshly wiped space turf to the active set needlessly creates enormous
	// generations and can starve unrelated components.
	let handle = with_turf_gases_read(|arena| {
		arena.get_id(turf).and_then(|node| {
			let mixture = arena.get(node)?;
			(!mixture.is_immutable()).then_some(mixture.handle())
		})
	});
	if let Some(handle) = handle {
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
}

pub(super) fn reserve_turf_capacity(nodes: usize, _edges: usize) {
	with_turf_gases_write(|arena| {
		let map_capacity = arena.map.capacity();
		arena.map.reserve(nodes.saturating_sub(map_capacity));
	});
}

pub fn shutdown_turfs() {
	wait_for_tasks();
	TURF_GASES.write().as_mut().unwrap().clear();
	PLANETARY_ATMOS.write().as_mut().unwrap().clear();
	*ACTIVE_TURFS.write() = Some(Default::default());
	MIX_TO_TURF.write().as_mut().unwrap().clear();
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
			arena.remove_turf(id);
		}
		PendingTopologyUpdate::Adjacencies(id, adjacent) => {
			arena.update_adjacencies_from_ids(id, &adjacent);
			// A topology change is itself an atmospheric mutation. Activate both
			// endpoints after the graph is authoritative, and promote a mutable cell
			// beside a large immutable pressure reservoir directly to the urgent
			// queue. This makes a newly blasted space boundary impossible to miss even
			// when DM only republishes the replacement turf's adjacency list.
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
					PRESSURE_URGENCY_MILLIKPA
						.fetch_max((urgency * 1_000.0) as u32, Ordering::AcqRel);
					active.activate_urgent(handle);
				} else {
					active.activate_fresh(handle);
				}
			}
		}
		PendingTopologyUpdate::RemoveAdjacencies(id) => {
			if let Some(&node) = arena.map.get(&id) {
				arena.remove_adjacencies(node);
			}
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

/// Returns: null. Updates turf air infos, whether the turf is closed, is space or a regular turf, or even a planet turf is decided here.
#[auxmacros::bind("/turf/proc/update_air_ref")]
fn hook_register_turf(src: ByondValue, flag: ByondValue) -> Result<ByondValue> {
	let flag = flag.get_number()? as i32;
	let visibility = crate::gas::visibility_copies();
	register_turf_impl(src, flag, &visibility)?;
	Ok(ByondValue::null())
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

/// Bulk form of hook_register_turf: takes a /list of turfs and registers each
/// with the given flag in ONE FFI entry. Roundstart setup_allturfs used to make
/// one call_ext per turf (~327k on a 5-z station) — the call dispatch overhead
/// alone dominated SSair init.
#[auxmacros::bind("/proc/_auxmos_register_turfs_bulk")]
fn hook_register_turfs_bulk(list: ByondValue, flag: ByondValue) -> Result<ByondValue> {
	let flag = flag.get_number()? as i32;
	let visibility = crate::gas::visibility_copies();
	for (turf, _) in list.iter()? {
		register_turf_impl(turf, flag, &visibility)?;
		// Round-start bulk registration precedes adjacency publication. Merely
		// existing is not atmospheric work, so do not enqueue every station turf.
		// The following bulk-adjacency pass selectively activates real gradients.
		let id = turf.get_ref()?;
		if let Some(handle) = with_turf_gases_read(|arena| {
			arena
				.get_id(id)
				.and_then(|node| arena.get(node))
				.map(TurfMixture::handle)
		}) {
			remove_active_handle(handle);
		}
	}
	Ok(ByondValue::null())
}

fn register_turf_impl(src: ByondValue, flag: i32, visibility: &[Option<f32>]) -> Result<()> {
	let id = src.get_ref()?;
	if let Ok(blocks) = src.read_number_id(byond_string!("blocks_air")) {
		if blocks > 0.0 {
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
		apply_or_queue_topology_update(PendingTopologyUpdate::Insert(to_insert));
	} else {
		apply_or_queue_topology_update(PendingTopologyUpdate::Remove(id));
	}

	Ok(())
}

/* will come back to you later
const PLANET_TURF: i32 = 1;
const SPACE_TURF: i32 = 0;
const CLOSED_TURF: i32 = -1;
const OPEN_TURF: i32 = 2;

//hardcoded because we can't have nice things
fn determine_turf_flag(src: &ByondValue) -> i32 {
	let path = src
		.read_string_id(byond_string!("("type")
		.unwrap_or_else(|_| "TYPPENOTFOUND".to_string());
	if !path.as_str().starts_with("/turf/open") {
		CLOSED_TURF
	} else if src.read_number_id(byond_string!("planetary_atmos")).unwrap_or(0.0) > 0.0 {
		PLANET_TURF
	} else if path.as_str().starts_with("/turf/open/space") {
		SPACE_TURF
	} else {
		OPEN_TURF
	}
}
*/
/// Updates adjacency infos for turfs, only use this in immediateupdateturfs.
#[auxmacros::bind("/turf/proc/__update_auxtools_turf_adjacency_info")]
fn hook_infos(src: ByondValue) -> Result<ByondValue> {
	infos_impl(src)?;
	Ok(ByondValue::null())
}

/// Bulk form of hook_infos: pushes the adjacency graph for a whole /list of
/// turfs in one FFI entry (see hook_register_turfs_bulk for why).
#[auxmacros::bind("/proc/_auxmos_update_adjacencies_bulk")]
fn hook_infos_bulk(list: ByondValue) -> Result<ByondValue> {
	// Publish the entire graph first. infos_impl() activates both endpoints of
	// each changed edge, so pruning inline is order-dependent: a later neighbor
	// would re-enqueue an already-pruned stable cell and leave most of the map in
	// the startup queue. The second pass evaluates the completed graph once.
	let turfs = list.iter()?.collect::<Vec<_>>();
	for (turf, _) in &turfs {
		infos_impl(*turf)?;
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

fn infos_impl(src: ByondValue) -> Result<ByondValue> {
	let id = src.get_ref()?;
	let update = if let Some(adjacent_list) = src
		.read_var_id(byond_string!("atmos_adjacent_turfs"))
		.ok()
		.and_then(|adjs| adjs.is_list().then_some(adjs))
	{
		PendingTopologyUpdate::Adjacencies(
			id,
			adjacent_list
				.iter()?
				.filter_map(|(key, value)| {
					Some((key.get_ref().ok()?, value.get_number().unwrap_or(0.0) as u8))
				})
				.collect(),
		)
	} else {
		PendingTopologyUpdate::RemoveAdjacencies(id)
	};
	apply_or_queue_topology_update(update);
	mark_turf_active(id);
	Ok(ByondValue::null())
}

/// Diagnostic invariant used by shuttle/atmos tests: Rust's authoritative
/// outgoing edge set for this turf must exactly match DM's published list.
#[auxmacros::bind("/proc/_auxmos_topology_matches")]
fn topology_matches(src: ByondValue) -> Result<ByondValue> {
	let id = src.get_ref()?;
	let expected_mix = src
		.read_var_id(byond_string!("air"))?
		.read_number_id(byond_string!("_extools_pointer_gasmixture"))? as usize;
	let mut expected = Vec::new();
	if let Ok(list) = src.read_var_id(byond_string!("atmos_adjacent_turfs")) {
		if list.is_list() {
			for (key, _) in list.iter()? {
				expected.push(key.get_ref()?);
			}
		}
	}
	let (mut actual, mut incoming, actual_mix) = with_turf_gases_read(|arena| {
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
		(outgoing, reverse, mix)
	});
	expected.sort_unstable();
	expected.dedup();
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
			// gas_overlays: list( GAS_ID = list( VIS_FACTORS = OVERLAYS )) got it? I don't
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
						Some((
							gas_overlays.read_list_index(gas::gas_idx_to_id(idx)).ok()?,
							moles,
						))
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

	#[test]
	fn adjacency_publication_is_symmetric_and_authoritative() {
		let mut arena = empty_arena();
		for id in [1, 2, 3] {
			arena.insert_turf(TurfMixture {
				id,
				mix: id as usize,
				..Default::default()
			});
		}
		arena.update_adjacencies_from_ids(1, &[(2, 0)]);
		let one = arena.get_id(1).unwrap();
		let two = arena.get_id(2).unwrap();
		assert!(arena.graph.find_edge(one, two).is_some());
		assert!(arena.graph.find_edge(two, one).is_some());

		arena.update_adjacencies_from_ids(1, &[(3, 0)]);
		let three = arena.get_id(3).unwrap();
		assert!(arena.graph.find_edge(one, two).is_none());
		assert!(arena.graph.find_edge(two, one).is_none());
		assert!(arena.graph.find_edge(one, three).is_some());
		assert!(arena.graph.find_edge(three, one).is_some());
	}

	#[test]
	fn adjacency_publication_cannot_create_parallel_physical_faces() {
		let mut arena = empty_arena();
		for id in [1, 2] {
			arena.insert_turf(TurfMixture {
				id,
				mix: id as usize,
				..Default::default()
			});
		}
		arena.update_adjacencies_from_ids(1, &[(2, 1), (2, 2), (2, 1)]);
		arena.update_adjacencies_from_ids(2, &[(1, 2), (1, 1)]);
		let one = arena.get_id(1).unwrap();
		let two = arena.get_id(2).unwrap();
		assert_eq!(arena.graph.edges_connecting(one, two).count(), 1);
		assert_eq!(arena.graph.edges_connecting(two, one).count(), 1);
	}

	#[test]
	fn topology_updates_wait_for_generation_barrier() {
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
