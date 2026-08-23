pub mod groups;
pub mod processing;
/*
#[cfg(feature = "monstermos")]
mod monstermos;
#[cfg(feature = "putnamos")]
mod putnamos;
*/
#[cfg(feature = "katmos")]
pub mod katmos;
#[cfg(feature = "superconductivity")]
pub(crate) mod superconduct;

use crate::{constants::*, gas::Mixture, GasArena};
use bitflags::bitflags;
use byondapi::prelude::*;
use eyre::{Context, Result};
use indexmap::IndexMap;
use parking_lot::{const_mutex, const_rwlock, Mutex, RwLock, RwLockUpgradableReadGuard};
use petgraph::{graph::NodeIndex, stable_graph::StableDiGraph, visit::EdgeRef, Direction};
use rayon::prelude::*;
use rustc_hash::{FxBuildHasher, FxHashMap, FxHashSet};
use std::hash::{Hash, Hasher};
use std::time::Duration;
use std::{
	mem::drop,
	sync::atomic::{AtomicBool, AtomicU64, Ordering},
};

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
		GasArena::bump_revision(self.mix);
		let (before, after) = GasArena::with_all_mixtures(|all_mixtures| {
			let mut mixture = all_mixtures
				.get(self.mix)
				.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
				.write();
			let before = GasArena::change_signature(&mixture);
			mixture.clear();
			(before, GasArena::change_signature(&mixture))
		});
		GasArena::bump_revision(self.mix);
		GasArena::mark_dirty_if_changed(self.mix, before, after);
	}
	/// Prevents diffusion and other gas operations from changing this turf's mixture.
	pub fn mark_immutable(&self) {
		GasArena::bump_revision(self.mix);
		GasArena::with_all_mixtures(|all_mixtures| {
			all_mixtures
				.get(self.mix)
				.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
				.write()
				.mark_immutable();
		});
		GasArena::bump_revision(self.mix);
	}
	/// Copies from a given gas mixture to the turf's airs, see [`super::gas::Mixture`]
	pub fn copy_from_mutable(&self, sample: &Mixture) {
		GasArena::bump_revision(self.mix);
		let (before, after) = GasArena::with_all_mixtures(|all_mixtures| {
			let mut mixture = all_mixtures
				.get(self.mix)
				.unwrap_or_else(|| panic!("Gas mixture not found for turf: {}", self.mix))
				.write();
			let before = GasArena::change_signature(&mixture);
			mixture.copy_from_mutable(sample);
			(before, GasArena::change_signature(&mixture))
		});
		GasArena::bump_revision(self.mix);
		GasArena::mark_dirty_if_changed(self.mix, before, after);
	}
	/// Clears a number of moles from the turf's air
	/// If the number of moles is greater than the turf's total moles, just clears the turf
	pub fn clear_moles(&self, amt: f32) {
		GasArena::bump_revision(self.mix);
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
		GasArena::bump_revision(self.mix);
		GasArena::mark_dirty_if_changed(self.mix, before, after);
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
			let resolved = adjacent
				.iter()
				.copied()
				.filter_map(|(adj_ref, flag)| Some((self.map.get(&adj_ref)?, flag)))
				.map(|(adj_index, flag)| (*adj_index, flag))
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
static ACTIVE_TURFS: RwLock<Option<FxHashSet<CellHandle>>> = const_rwlock(None);
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
#[byondapi::bind("/datum/controller/subsystem/air/proc/auxmos_topology_barrier")]
#[auxmacros::panic_safe]
fn topology_barrier() -> Result<ByondValue> {
	wait_for_tasks();
	apply_pending_topology_updates();
	groups::flush_groups_channel();
	#[cfg(feature = "katmos")]
	katmos::flush_equalize_channel();
	Ok(ByondValue::null())
}

/// Opens a synchronous world-topology transaction. Atmos workers are drained
/// before DM begins mutating turfs and cannot start again until commit.
#[byondapi::bind("/datum/controller/subsystem/air/proc/auxmos_topology_transaction_begin")]
#[auxmacros::panic_safe]
fn topology_transaction_begin() -> Result<ByondValue> {
	wait_for_tasks();
	apply_pending_topology_updates();
	TOPOLOGY_TRANSACTION.lock().clear();
	TOPOLOGY_TRANSACTION_OPEN.store(true, Ordering::Release);
	Ok(ByondValue::null())
}

/// Atomically applies every registration and edge replacement accumulated by
/// the matching begin call, then exposes one new topology generation.
#[byondapi::bind("/datum/controller/subsystem/air/proc/auxmos_topology_transaction_commit")]
#[auxmacros::panic_safe]
fn topology_transaction_commit() -> Result<ByondValue> {
	// panic_safe catches unwinds outside this function. This guard ensures a
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
	groups::flush_groups_channel();
	#[cfg(feature = "katmos")]
	katmos::flush_equalize_channel();
	Ok(ByondValue::null())
}

pub(crate) fn mark_mix_active(mix: usize) {
	let handle = MIX_TO_TURF
		.read()
		.as_ref()
		.and_then(|mapping| mapping.get(&mix).copied());
	let mutable = handle.is_some_and(|handle| {
		with_turf_gases_read(|arena| {
			arena
				.get_handle(handle)
				.and_then(|node| arena.get(node))
				.is_some_and(|mixture| !mixture.is_immutable())
		})
	});
	if mutable {
		let handle = handle.expect("mutable mapped mixture has a turf handle");
		ACTIVE_TURFS.write().as_mut().unwrap().insert(handle);
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
		ACTIVE_TURFS.write().as_mut().unwrap().insert(handle);
	}
}

const MAX_TURF_SEEDS_PER_GENERATION: usize = 4_096;

fn take_active_turfs() -> FxHashSet<CellHandle> {
	let mut active_guard = ACTIVE_TURFS.write();
	let active = active_guard.as_mut().unwrap();
	if active.len() <= MAX_TURF_SEEDS_PER_GENERATION {
		return std::mem::take(active);
	}
	// A generation is an optimistic transaction. Taking the entire station made
	// one legitimate machine write invalidate tens of thousands of unrelated
	// cells forever. Bounded seed batches keep publication latency short while
	// the unconsumed work remains queued for subsequent generations.
	let selected = active
		.iter()
		.take(MAX_TURF_SEEDS_PER_GENERATION)
		.copied()
		.collect::<FxHashSet<_>>();
	active.retain(|handle| !selected.contains(handle));
	selected
}

fn reactivate_cells(ids: impl IntoIterator<Item = CellHandle>) {
	ACTIVE_TURFS.write().as_mut().unwrap().extend(ids);
}

pub(super) fn pending_active_turfs() -> usize {
	ACTIVE_TURFS.read().as_ref().map_or(0, FxHashSet::len)
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

pub(super) fn reactivate_all_turfs() {
	let handles = with_turf_gases_read(|arena| {
		arena
			.map
			.values()
			.filter_map(|&node| {
				let mixture = arena.get(node)?;
				(!mixture.is_immutable()).then_some(mixture.handle())
			})
			.collect::<Vec<_>>()
	});
	reactivate_cells(handles);
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
	ACTIVE_TURFS.write().as_mut().unwrap().clear();
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
					MIX_TO_TURF.write().as_mut().unwrap().remove(&previous.0);
					ACTIVE_TURFS.write().as_mut().unwrap().remove(&previous.1);
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
				ACTIVE_TURFS.write().as_mut().unwrap().insert(handle);
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
				ACTIVE_TURFS.write().as_mut().unwrap().remove(&handle);
				MIX_TO_TURF.write().as_mut().unwrap().remove(&mix);
			}
			groups::retire_turf(id);
			#[cfg(feature = "katmos")]
			katmos::retire_turf(id);
			arena.remove_turf(id);
		}
		PendingTopologyUpdate::Adjacencies(id, adjacent) => {
			arena.update_adjacencies_from_ids(id, &adjacent)
		}
		PendingTopologyUpdate::RemoveAdjacencies(id) => {
			if let Some(&node) = arena.map.get(&id) {
				arena.remove_adjacencies(node);
			}
		}
	}
}

fn apply_or_queue_topology_update(update: PendingTopologyUpdate) {
	if TOPOLOGY_TRANSACTION_OPEN.load(Ordering::Acquire) {
		TOPOLOGY_TRANSACTION.lock().push(update);
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
#[byondapi::bind("/turf/proc/update_air_ref")]
#[auxmacros::panic_safe]
fn hook_register_turf(src: ByondValue, flag: ByondValue) -> Result<ByondValue> {
	let flag = flag.get_number()? as i32;
	let visibility = crate::gas::visibility_copies();
	register_turf_impl(src, flag, &visibility)?;
	Ok(ByondValue::null())
}

/// Monotonic revision of this turf's gas mixture. Consumers can skip expensive
/// polling while the value is unchanged.
#[byondapi::bind("/turf/proc/air_revision")]
#[auxmacros::panic_safe]
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
#[byondapi::bind("/proc/_auxmos_register_turfs_bulk")]
#[auxmacros::panic_safe]
fn hook_register_turfs_bulk(list: ByondValue, flag: ByondValue) -> Result<ByondValue> {
	let flag = flag.get_number()? as i32;
	let visibility = crate::gas::visibility_copies();
	for (turf, _) in list.iter()? {
		register_turf_impl(turf, flag, &visibility)?;
	}
	Ok(ByondValue::null())
}

fn register_turf_impl(src: ByondValue, flag: i32, visibility: &[Option<f32>]) -> Result<()> {
	let id = src.get_ref()?;
	if let Ok(blocks) = src.read_number_id(byond_string!("blocks_air")) {
		if blocks > 0.0 {
			apply_or_queue_topology_update(PendingTopologyUpdate::Remove(id));
			#[cfg(feature = "superconductivity")]
			superconduct::supercond_update_ref(src)?;
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

	#[cfg(feature = "superconductivity")]
	superconduct::supercond_update_ref(src)?;
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
#[byondapi::bind("/turf/proc/__update_auxtools_turf_adjacency_info")]
#[auxmacros::panic_safe]
fn hook_infos(src: ByondValue) -> Result<ByondValue> {
	infos_impl(src)?;
	Ok(ByondValue::null())
}

/// Bulk form of hook_infos: pushes the adjacency graph for a whole /list of
/// turfs in one FFI entry (see hook_register_turfs_bulk for why).
#[byondapi::bind("/proc/_auxmos_update_adjacencies_bulk")]
#[auxmacros::panic_safe]
fn hook_infos_bulk(list: ByondValue) -> Result<ByondValue> {
	for (turf, _) in list.iter()? {
		infos_impl(turf)?;
	}
	Ok(ByondValue::null())
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

	#[cfg(feature = "superconductivity")]
	superconduct::supercond_update_adjacencies(id)?;
	Ok(ByondValue::null())
}

/// Diagnostic invariant used by shuttle/atmos tests: Rust's authoritative
/// outgoing edge set for this turf must exactly match DM's published list.
#[byondapi::bind("/proc/_auxmos_topology_matches")]
#[auxmacros::panic_safe]
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

const fn adjacent_tile_id(id: u8, i: TurfID, max_x: i32, max_y: i32) -> TurfID {
	let z_size = max_x * max_y;
	let i = i as i32;
	match id {
		0 => (i + max_x) as TurfID,
		1 => (i - max_x) as TurfID,
		2 => (i + 1) as TurfID,
		3 => (i - 1) as TurfID,
		4 => (i + z_size) as TurfID,
		5 => (i - z_size) as TurfID,
		_ => panic!("Invalid id passed to adjacent_tile_id!"),
	}
}

#[derive(Clone, Copy)]
struct AdjacentTileIDs {
	adj: Directions,
	i: TurfID,
	max_x: i32,
	max_y: i32,
	count: u8,
}

impl Iterator for AdjacentTileIDs {
	type Item = (Directions, TurfID);

	fn next(&mut self) -> Option<Self::Item> {
		loop {
			if self.count == 6 {
				return None;
			}
			//SAFETY: count can never be invalid
			let dir = Directions::from_bits_retain(1 << self.count);
			self.count += 1;
			if self.adj.contains(dir) {
				return Some((
					dir,
					adjacent_tile_id(self.count - 1, self.i, self.max_x, self.max_y),
				));
			}
		}
	}

	fn size_hint(&self) -> (usize, Option<usize>) {
		(0, Some(self.adj.bits().count_ones() as usize))
	}
}

use std::iter::FusedIterator;

impl FusedIterator for AdjacentTileIDs {}

#[allow(unused)]
fn adjacent_tile_ids(adj: Directions, i: TurfID, max_x: i32, max_y: i32) -> AdjacentTileIDs {
	AdjacentTileIDs {
		adj,
		i,
		max_x,
		max_y,
		count: 0,
	}
}

#[cfg(test)]
mod tests {
	use super::*;

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
}
