use super::*;
use byondapi::{byond_string, prelude::*};
//use indexmap::IndexSet;
use crate::GasArena;
use auxcallback::byond_callback_sender;
use coarsetime::Instant;
use eyre::Result;
use parking_lot::Once;
use std::sync::{
	atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
	OnceLock,
};

static INIT_HEAT: Once = Once::new();

static TURF_HEAT: RwLock<Option<TurfHeat>> = const_rwlock(None);
static HEAT_DIRTY: AtomicBool = AtomicBool::new(true);
static LAST_HEAT_CANDIDATES: AtomicUsize = AtomicUsize::new(0);
static LAST_HEAT_MICROS: AtomicU64 = AtomicU64::new(0);

pub(crate) fn mark_heat_dirty() {
	HEAT_DIRTY.store(true, Ordering::Release);
}

pub(crate) fn heat_diagnostics() -> (bool, usize, u64) {
	(
		HEAT_DIRTY.load(Ordering::Acquire),
		LAST_HEAT_CANDIDATES.load(Ordering::Acquire),
		LAST_HEAT_MICROS.load(Ordering::Acquire),
	)
}

// Ported from auxtools lazy_static to std OnceLock. Bounded(1) so a still-processing
// heat tick can't pile up backlog.
static HEAT_CHANNEL: OnceLock<(flume::Sender<SSheatInfo>, flume::Receiver<SSheatInfo>)> =
	OnceLock::new();

fn heat_channel() -> &'static (flume::Sender<SSheatInfo>, flume::Receiver<SSheatInfo>) {
	HEAT_CHANNEL.get_or_init(|| flume::bounded(1))
}

// world.maxx / world.maxy, needed to compute a turf's cardinal+multiz neighbours by
// coordinate id. Reading world vars from Rust via byondapi is unreliable on BYOND 516
// (a failed World-value read crashes in byondapi's own error path), so DM pushes the
// dimensions in through the world-dimension binds in turfs.rs.
static WORLD_DIMS: RwLock<Option<(i32, i32)>> = const_rwlock(None);

fn world_dims() -> Result<(i32, i32)> {
	(*WORLD_DIMS.read()).ok_or_else(|| {
		eyre::eyre!("auxmos world dimensions not set — call auxmos_set_world_dims first")
	})
}

/// Set by the world-dimension binds in `turfs.rs`.
pub(super) fn set_heat_world_dims(max_x: i32, max_y: i32) {
	*WORLD_DIMS.write() = Some((max_x, max_y));
}

pub(super) fn reserve_heat_capacity(nodes: usize, _edges: usize) {
	let mut heat = TURF_HEAT.write();
	let heat = heat.as_mut().unwrap();
	let map_capacity = heat.map.capacity();
	heat.map.reserve(nodes.saturating_sub(map_capacity));
}

#[byondapi::init]
fn initialize_heat_statics() {
	*TURF_HEAT.write() = Some(TurfHeat {
		graph: StableDiGraph::with_capacity(4096, 16_384),
		map: IndexMap::with_capacity_and_hasher(4096, FxBuildHasher::default()),
	});
}

fn with_turf_heat_read<T, F>(f: F) -> T
where
	F: FnOnce(&TurfHeat) -> T,
{
	f(TURF_HEAT.read().as_ref().unwrap())
}

fn with_turf_heat_write<T, F>(f: F) -> T
where
	F: FnOnce(&mut TurfHeat) -> T,
{
	f(TURF_HEAT.write().as_mut().unwrap())
}

#[derive(Copy, Clone)]
struct SSheatInfo {
	time_delta: f64,
}

#[derive(Default)]
struct ThermalInfo {
	pub id: TurfID,

	pub thermal_conductivity: f32,
	pub heat_capacity: f32,
	pub adjacent_to_space: bool,

	pub temperature: RwLock<f32>,
}

fn with_heat_processing_callback_receiver<T>(f: impl Fn(&flume::Receiver<SSheatInfo>) -> T) -> T {
	f(&heat_channel().1)
}

fn heat_processing_callbacks_sender() -> flume::Sender<SSheatInfo> {
	heat_channel().0.clone()
}
type HeatGraphMap = IndexMap<TurfID, NodeIndex<usize>, FxBuildHasher>;

//turf temperature infos goes here
struct TurfHeat {
	graph: StableDiGraph<ThermalInfo, (), usize>,
	map: HeatGraphMap,
}

impl TurfHeat {
	pub fn insert_turf(&mut self, info: ThermalInfo) {
		if let Some(&node_id) = self.map.get(&info.id) {
			let thin = self.graph.node_weight_mut(node_id).unwrap();
			thin.thermal_conductivity = info.thermal_conductivity;
			thin.heat_capacity = info.heat_capacity;
			thin.adjacent_to_space = info.adjacent_to_space;
		} else {
			self.map.insert(info.id, self.graph.add_node(info));
		}
	}

	pub fn remove_turf(&mut self, id: TurfID) {
		if let Some(index) = self.map.swap_remove(&id) {
			self.graph.remove_node(index);
		}
	}

	pub fn get(&self, idx: NodeIndex<usize>) -> Option<&ThermalInfo> {
		self.graph.node_weight(idx)
	}

	pub fn get_id(&self, idx: &TurfID) -> Option<&NodeIndex<usize>> {
		self.map.get(idx)
	}

	pub fn adjacent_node_ids<'a>(
		&'a self,
		index: NodeIndex<usize>,
	) -> impl Iterator<Item = NodeIndex<usize>> + 'a {
		self.graph.neighbors(index)
	}

	pub fn adjacent_heats(
		&self,
		index: NodeIndex<usize>,
	) -> impl Iterator<Item = &ThermalInfo> + '_ {
		self.graph
			.neighbors(index)
			.filter_map(|neighbor| self.graph.node_weight(neighbor))
	}

	pub fn update_adjacencies(
		&mut self,
		idx: TurfID,
		blocked_dirs: Directions,
		max_x: i32,
		max_y: i32,
	) {
		if let Some(&this_node) = self.get_id(&idx) {
			self.remove_adjacencies(this_node);
			// A solid deck separates coordinate z-neighbors, and adjacent z slots
			// can hold unrelated maps. Cross-z heat requires an explicit conductor.
			for (_, adj_idx) in
				adjacent_tile_ids(Directions::ALL_CARDINALS - blocked_dirs, idx, max_x, max_y)
			{
				if let Some(&adjacent_node) = self.get_id(&adj_idx) {
					if adjacent_node != this_node {
						self.graph.add_edge(this_node, adjacent_node, ());
						// Registration order must not matter: a neighbour registered
						// earlier never saw this cell, so give it the reverse edge.
						if self.graph.find_edge(adjacent_node, this_node).is_none() {
							self.graph.add_edge(adjacent_node, this_node, ());
						}
					}
				}
			}
		}
	}

	pub fn remove_adjacencies(&mut self, index: NodeIndex<usize>) {
		let edges = self
			.graph
			.edges(index)
			.map(|edgeref| edgeref.id())
			.collect::<Vec<_>>();
		edges.into_iter().for_each(|edgeindex| {
			self.graph.remove_edge(edgeindex);
		});
	}
}

pub fn supercond_update_ref(src: ByondValue) -> Result<()> {
	mark_heat_dirty();
	let id = src.get_ref()?;
	let immutable_atmos = src
		.read_number_id(byond_string!("immutable_atmos"))
		.unwrap_or(0.0)
		!= 0.0;
	let therm_cond = src
		.read_number_id(byond_string!("thermal_conductivity"))
		.unwrap_or(0.0);
	let therm_cap = src
		.read_number_id(byond_string!("heat_capacity"))
		.unwrap_or(0.0);
	if !immutable_atmos && therm_cond > 0.0 && therm_cap > 0.0 {
		let therm_info = ThermalInfo {
			id,
			adjacent_to_space: src
				.call_id(byond_string!("should_conduct_to_space"), &[])?
				.get_number()?
				> 0.0,
			heat_capacity: therm_cap,
			thermal_conductivity: therm_cond,
			temperature: RwLock::new(
				src.read_number_id(byond_string!("temperature"))
					.unwrap_or(TCMB),
			),
		};
		with_turf_heat_write(|arena| arena.insert_turf(therm_info));
	} else {
		with_turf_heat_write(|arena| arena.remove_turf(id));
	}
	Ok(())
}

pub fn supercond_update_adjacencies(id: u32) -> Result<()> {
	mark_heat_dirty();
	let (max_x, max_y) = world_dims()?;
	let src_turf = ByondValue::new_ref(ValueType::Turf, id);
	with_turf_heat_write(|arena| -> Result<()> {
		if let Ok(blocked_dirs) =
			src_turf.read_number_id(byond_string!("conductivity_blocked_directions"))
		{
			let actual_dir = Directions::from_bits_truncate(blocked_dirs as u8);
			arena.update_adjacencies(id, actual_dir, max_x, max_y)
		} else if let Some(&idx) = arena.get_id(&id) {
			arena.remove_adjacencies(idx)
		}
		Ok(())
	})?;
	Ok(())
}

#[auxmacros::bind("/turf/proc/return_temperature")]
fn hook_turf_temperature(src: ByondValue) -> Result<ByondValue> {
	let id = src.get_ref()?;
	// Untracked turfs (zero heat capacity, immutable reservoirs, or a topology
	// transition) still have a valid DM-side solid temperature. Returning the old
	// arbitrary 102 K sentinel let ordinary callers treat them as cryogenic heat
	// sinks. The mirror is authoritative whenever no heat-arena node exists.
	let fallback = src
		.read_number_id(byond_string!("temperature"))
		.unwrap_or(T20C);
	with_turf_heat_read(|arena| -> Result<ByondValue> {
		if let Some(&node_index) = arena.get_id(&id) {
			let info = arena.get(node_index).unwrap();
			let read = info.temperature.read();
			if read.is_normal() {
				Ok(ByondValue::from(*read))
			} else {
				Ok(ByondValue::from(300.0f32))
			}
		} else {
			Ok(ByondValue::from(fallback))
		}
	})
}

// Push an authoritative temperature into a turf's heat-arena node. The arena owns
// turf heat (it seeds from the DM `temperature` var only at registration, then runs
// its own conduction), so DM heat injections — pipe-to-wall exchange, holodeck heat
// programs — must write here or they silently no-op against the arena. If the turf
// isn't tracked (no thermal_conductivity/heat_capacity), this is a no-op and the DM
// mirror alone stands until the turf next registers. Writes the inner RwLock under an
// arena read-lock, exactly as the heat-share pass does.
#[auxmacros::bind("/turf/proc/set_turf_temperature")]
fn hook_set_turf_temperature(src: ByondValue, temperature: ByondValue) -> Result<ByondValue> {
	let id = src.get_ref()?;
	let temp = temperature.get_number()? as f32;
	with_turf_heat_read(|arena| {
		if let Some(&node_index) = arena.get_id(&id) {
			if let Some(info) = arena.get(node_index) {
				*info.temperature.write() = temp;
			}
		}
	});
	Ok(ByondValue::null())
}

// Expected function call: process_turf_heat()
// Returns: TRUE if thread not done, FALSE otherwise
#[auxmacros::bind("/datum/controller/subsystem/air/proc/process_turf_heat")]
fn process_heat_notify(src: ByondValue) -> Result<ByondValue> {
	/*
		Replacing LINDA's superconductivity system is this much more brute-force
		system--it shares heat between turfs and their neighbors,
		then receives and emits radiation to space, then shares
		between turfs and their gases. Since the latter requires a write lock,
		it's done after the previous step. This one doesn't care about
		consistency like the processing step does--this can run in full parallel.
		Can't get a number from src in the thread, so we get it here.
		Have to get the time delta because the radiation
		is actually physics-based--the stefan boltzmann constant
		and radiation from space both have dimensions of second^-1 that
		need to be multiplied out to have any physical meaning.
		They also have dimensions of meter^-2, but I'm assuming
		turf tiles are 1 meter^2 anyway--the atmos subsystem
		does this in general, thus turf gas mixtures being 2.5 m^3.
	*/
	if !HEAT_DIRTY.load(Ordering::Acquire) {
		return Ok(ByondValue::null());
	}
	// Consume the work that caused this pass. A mutation arriving while the
	// worker runs sets the flag again and must survive an otherwise-idle pass.
	HEAT_DIRTY.store(false, Ordering::Release);
	let sender = heat_processing_callbacks_sender();
	let time_delta = (src.read_number_id(byond_string!("wait")).map_err(|_| {
		eyre::eyre!(
			"Attempt to interpret non-number value as number {} {}:{}",
			std::file!(),
			std::line!(),
			std::column!()
		)
	})? / 10.0) as f64;
	_ = sender.try_send(SSheatInfo { time_delta });
	Ok(ByondValue::null())
}

fn get_share_energy(delta: f32, cap_1: f32, cap_2: f32) -> f32 {
	use vg_core::units::{HeatCapacity, Kelvin};
	vg_core::thermo::equalizing_energy(Kelvin(delta), HeatCapacity(cap_1), HeatCapacity(cap_2)).0
}

#[cfg(test)]
mod tests {
	use super::get_share_energy;

	#[test]
	fn solid_heat_transfer_conserves_energy() {
		let hot_capacity = 10_000.0;
		let cold_capacity = 2_500.0;
		let hot_start = 350.0;
		let cold_start = 250.0;
		let transferred =
			0.04 * 0.5 * get_share_energy(cold_start - hot_start, hot_capacity, cold_capacity);
		let hot_end = hot_start + transferred / hot_capacity;
		let cold_end = cold_start - transferred / cold_capacity;
		let energy_before = hot_start * hot_capacity + cold_start * cold_capacity;
		let energy_after = hot_end * hot_capacity + cold_end * cold_capacity;
		assert!((energy_before - energy_after).abs() < 0.5);
		assert!(hot_end < hot_start);
		assert!(cold_end > cold_start);
	}
}

//Fires the task into the thread pool, once
#[byondapi::init]
fn process_heat_start() {
	INIT_HEAT.call_once(|| {
		rayon::spawn(|| loop {
			//this will block until process_turf_heat is called
			let tick_info =
				with_heat_processing_callback_receiver(|receiver| receiver.recv().unwrap());
			let task_lock = TASKS.read();
			let start_time = Instant::now();
			let sender = byond_callback_sender();
			let had_work = AtomicBool::new(false);
			let time_delta = tick_info.time_delta as f32;
			with_turf_heat_read(|arena| {
				with_turf_gases_read(|air_arena| {
					let adjacencies_to_consider = arena
						.map
						.par_iter()
						.filter_map(|(&turf_id, &heat_index)| {
							/*
								If it has no thermal conductivity, low thermal capacity or has no adjacencies,
								then it's not gonna interact, or at least shouldn't.
							*/
							let info = arena.get(heat_index).unwrap();
							let temp = { *info.temperature.read() };
							//can share w/ adjacents?
							if arena.adjacent_heats(heat_index).any(|item| {
								(temp - *item.temperature.read()).abs()
									> MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER
							}) {
								had_work.store(true, Ordering::Relaxed);
								return Some((turf_id, heat_index, true));
							}
							if temp > MINIMUM_TEMPERATURE_FOR_SUPERCONDUCTION {
								//can share w/ space/air?
								if info.adjacent_to_space
									|| air_arena
										.get_id(turf_id)
										.and_then(|nodeid| {
											air_arena.get(nodeid)?.enabled().then(|| ())
										})
										.is_some()
								{
									had_work.store(true, Ordering::Relaxed);
									Some((turf_id, heat_index, false))
								} else {
									None
								}
							} else if let Some(node) = air_arena.get_id(turf_id) {
								let cur_mix = air_arena.get(node).unwrap();
								if !cur_mix.enabled() {
									return None;
								}
								GasArena::with_all_mixtures(|all_mixtures| {
									let air_temp = all_mixtures[cur_mix.mix].try_read();
									if air_temp.is_none() {
										return false;
									}
									let air_temp = air_temp.unwrap().get_temperature();

									if air_temp < MINIMUM_TEMPERATURE_FOR_SUPERCONDUCTION {
										return false;
									}
									(temp - air_temp).abs() > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER
								})
								.then(|| {
									had_work.store(true, Ordering::Relaxed);
									(turf_id, heat_index, false)
								})
							} else {
								None
							}
						})
						.filter_map(|(id, node_index, has_adjacents)| {
							let info = arena.get(node_index).unwrap();
							// Gas ownership must precede the turf-temperature lock. Never
							// block a Rayon worker here: diffusion uses the same pool, so a
							// busy gas shard means this heat cell retries on the next pass.
							let _single_writer = GasArena::try_begin_solver_transaction()?;
							let mut temp_write = info.temperature.try_write()?;

							/*
							//share w/ space
							if info.adjacent_to_space && *temp_write > T0C {
								/*
									Straight up the standard blackbody radiation
									equation. All these are f64s because
									f32::MAX^4 < f64::MAX, and t.temperature
									is ordinarily an f32, meaning that
									this will never go into infinities.
								*/
								let blackbody_radiation: f64 = (emissivity_constant
									* STEFAN_BOLTZMANN_CONSTANT
									* (f64::from(*temp_write).powi(4)))
									- radiation_from_space_tick;
								*temp_write -= blackbody_radiation as f32 / info.heat_capacity;
							}
							*/
							//share w/ space
							if info.adjacent_to_space && *temp_write > T20C {
								let delta = *temp_write - TCMB;
								let energy = get_share_energy(
									info.thermal_conductivity * time_delta * delta,
									HEAT_CAPACITY_VACUUM,
									info.heat_capacity,
								);
								*temp_write -= energy / info.heat_capacity;
							}

							//share w/ air
							if let Some(node_idx) = air_arena.get_id(id) {
								let tmix = air_arena.get(node_idx).unwrap();
								if tmix.enabled() {
									GasArena::with_all_mixtures(|all_mixtures| {
										if let Some(entry) = all_mixtures.get(tmix.mix) {
											if let Some(mut gas) = entry.try_write() {
												let before = GasArena::change_signature(&gas);
												*temp_write = gas.temperature_share_non_gas(
													/*
														This value should be lower than the
														turf-to-turf conductivity for balance reasons
														as well as realism, otherwise fires will
														just sort of solve theirselves over time.
													*/
													info.thermal_conductivity
														* OPEN_HEAT_TRANSFER_COEFFICIENT * time_delta,
													*temp_write,
													info.heat_capacity,
												);
												let after = GasArena::change_signature(&gas);
												let changed =
													GasArena::signature_changed(&before, &after);
												if GasArena::mark_dirty_if_changed(
													tmix.mix, before, after,
												) {
													GasArena::bump_revision(tmix.mix);
												} else if changed {
													// Preserve exact authoritative revision semantics for
													// sub-epsilon heat drift without turning it into new
													// diffusion work.
													GasArena::bump_revision_only(tmix.mix);
												}
											}
										}
									})
								}
							}

							if !temp_write.is_normal() {
								*temp_write = TCMB;
							}

							if *temp_write > MINIMUM_TEMPERATURE_START_SUPERCONDUCTION
								&& *temp_write > info.heat_capacity
							{
								// not what heat capacity means but whatever
								drop(sender.try_send(Box::new(move || -> Result<()> {
									let mut turf = ByondValue::new_ref(ValueType::Turf, id);
									turf.write_var_id(
										byond_string!("to_be_destroyed"),
										&ByondValue::from(1.0f32),
									)?;
									Ok(())
								})));
							}
							has_adjacents.then(|| node_index)
						})
						.collect::<Vec<_>>();
					LAST_HEAT_CANDIDATES.store(adjacencies_to_consider.len(), Ordering::Release);

					_ = adjacencies_to_consider
						.par_iter()
						.try_for_each(|&cur_index| {
							let info = arena.get(cur_index).unwrap();
							if let Some(mut temp_write) = info.temperature.try_write() {
								//share w/ adjacents that are strictly in zone
								for other in arena
									.adjacent_node_ids(cur_index)
									.filter_map(|idx| arena.get(idx))
								{
									if other.id <= info.id {
										continue;
									}
									/*
										The horrible line below is essentially
										sharing between solids--making it the minimum of both
										conductivities makes this consistent, funnily enough.
									*/
									if let Some(mut other_write) = other.temperature.try_write() {
										let shareds =
											info.thermal_conductivity
												.min(other.thermal_conductivity) * get_share_energy(
												*other_write - *temp_write,
												info.heat_capacity,
												other.heat_capacity,
											);
										let shareds = shareds * time_delta;
										*temp_write += shareds / info.heat_capacity;
										*other_write -= shareds / other.heat_capacity;
									}
								}
							}
							Ok::<(), eyre::Report>(())
						});
				});
			});
			// (Profiling writeback of cost_superconductivity onto SSair was removed:
			// reading the SSair global off the World value is unreliable on BYOND 516,
			// the same failure that crashes world-var reads. Heat conduction itself
			// does not need it.)
			if had_work.load(Ordering::Relaxed) {
				HEAT_DIRTY.store(true, Ordering::Release);
			}
			LAST_HEAT_MICROS.store(start_time.elapsed().as_micros() as u64, Ordering::Release);
			drop(task_lock);
		});
	});
}
/*

fn flood_fill_temps(
	input: Vec<NodeIndex<usize>>,
	arena: &TurfHeat,
) -> Vec<IndexSet<NodeIndex<usize>, FxBuildHasher>> {
	let mut found_turfs: HashSet<NodeIndex<usize>, FxBuildHasher> = Default::default();
	let mut return_val: Vec<IndexSet<NodeIndex<usize>, FxBuildHasher>> = Default::default();
	for temp_id in input {
		let mut turfs: IndexSet<NodeIndex<usize>, FxBuildHasher> = Default::default();
		let mut border_turfs: std::collections::VecDeque<NodeIndex<usize>> = Default::default();
		border_turfs.push_back(temp_id);
		found_turfs.insert(temp_id);
		while let Some(cur_index) = border_turfs.pop_front() {
			for adj_index in arena.adjacent_node_ids(cur_index) {
				if found_turfs.insert(adj_index) {
					border_turfs.push_back(adj_index)
				}
			}
			turfs.insert(cur_index);
		}
		return_val.push(turfs)
	}
	return_val
}
*/
