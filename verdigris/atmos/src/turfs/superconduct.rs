use super::*;
use byondapi::{byond_string, prelude::*};
//use indexmap::IndexSet;
use crate::GasArena;
use auxcallback::byond_callback_sender;
use coarsetime::Instant;
use eyre::Result;
use parking_lot::Once;
use std::sync::OnceLock;

static INIT_HEAT: Once = Once::new();

static TURF_HEAT: RwLock<Option<TurfHeat>> = const_rwlock(None);

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
// dimensions in once at SSair init via auxmos_set_world_dims(). The map never resizes
// at runtime, so a single set is sufficient.
static WORLD_DIMS: RwLock<Option<(i32, i32)>> = const_rwlock(None);

fn world_dims() -> Result<(i32, i32)> {
	(*WORLD_DIMS.read())
		.ok_or_else(|| eyre::eyre!("auxmos world dimensions not set — call auxmos_set_world_dims first"))
}

// Called once by DM (SSair init) with world.maxx / world.maxy before any turf
// adjacency is registered.
#[byondapi::bind("/datum/controller/subsystem/air/proc/auxmos_set_world_dims")]
#[auxmacros::panic_safe]
fn set_world_dims(max_x: ByondValue, max_y: ByondValue) -> Result<ByondValue> {
	*WORLD_DIMS.write() = Some((max_x.get_number()? as i32, max_y.get_number()? as i32));
	Ok(ByondValue::null())
}

#[byondapi::init]
fn initialize_heat_statics() {
	*TURF_HEAT.write() = Some(TurfHeat {
		graph: StableDiGraph::with_capacity(650_250, 1_300_500),
		map: IndexMap::with_capacity_and_hasher(650_250, FxBuildHasher::default()),
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
	) -> impl Iterator<Item = NodeIndex<usize>> + '_ {
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
			for (_, adj_idx) in adjacent_tile_ids(
				Directions::ALL_CARDINALS_MULTIZ - blocked_dirs,
				idx,
				max_x,
				max_y,
			) {
				if let Some(&adjacent_node) = self.get_id(&adj_idx) {
					//this fucking happens, I don't even know anymore
					if adjacent_node != this_node {
						self.graph.add_edge(this_node, adjacent_node, ());
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
	let id = src.get_ref()?;
	let therm_cond = src
		.read_number_id(byond_string!("thermal_conductivity"))
		.unwrap_or(0.0);
	let therm_cap = src
		.read_number_id(byond_string!("heat_capacity"))
		.unwrap_or(0.0);
	if therm_cond > 0.0 && therm_cap > 0.0 {
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
	let (max_x, max_y) = world_dims()?;
	let src_turf = ByondValue::new_ref(ValueType::Turf, id);
	with_turf_heat_write(|arena| -> Result<()> {
		if let Ok(blocked_dirs) = src_turf.read_number_id(byond_string!("conductivity_blocked_directions")) {
			let actual_dir = Directions::from_bits_truncate(blocked_dirs as u8);
			arena.update_adjacencies(id, actual_dir, max_x, max_y)
		} else if let Some(&idx) = arena.get_id(&id) {
			arena.remove_adjacencies(idx)
		}
		Ok(())
	})?;
	Ok(())
}

#[byondapi::bind("/turf/proc/return_temperature")]
#[auxmacros::panic_safe]
fn hook_turf_temperature(src: ByondValue) -> Result<ByondValue> {
	let id = src.get_ref()?;
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
			Ok(ByondValue::from(102.0f32))
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
#[byondapi::bind("/turf/proc/set_turf_temperature")]
#[auxmacros::panic_safe]
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
#[byondapi::bind("/datum/controller/subsystem/air/proc/process_turf_heat")]
#[auxmacros::panic_safe]
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
	delta * ((cap_1 * cap_2) / (cap_1 + cap_2))
}

//Fires the task into the thread pool, once
#[byondapi::init]
fn process_heat_start() {
	INIT_HEAT.call_once(|| {
		rayon::spawn(|| loop {
			//this will block until process_turf_heat is called
			let info = with_heat_processing_callback_receiver(|receiver| receiver.recv().unwrap());
			let task_lock = TASKS.read();
			let start_time = Instant::now();
			let sender = byond_callback_sender();
			let _emissivity_constant: f64 = STEFAN_BOLTZMANN_CONSTANT * info.time_delta;
			let _radiation_from_space_tick: f64 = RADIATION_FROM_SPACE * info.time_delta;
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
								.then(|| (turf_id, heat_index, false))
							} else {
								None
							}
						})
						.filter_map(|(id, node_index, has_adjacents)| {
							let info = arena.get(node_index).unwrap();
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
									info.thermal_conductivity * delta,
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
												*temp_write = gas.temperature_share_non_gas(
													/*
														This value should be lower than the
														turf-to-turf conductivity for balance reasons
														as well as realism, otherwise fires will
														just sort of solve theirselves over time.
													*/
													info.thermal_conductivity
														* OPEN_HEAT_TRANSFER_COEFFICIENT,
													*temp_write,
													info.heat_capacity,
												);
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
			let _ = start_time.elapsed();
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
