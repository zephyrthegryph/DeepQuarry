use super::*;
use crate::{gas::MixtureSnapshot, react_hook, GasArena};
use auxcallback::{byond_callback_sender, process_callbacks_for_millis};
use byondapi::{byond_string, prelude::*};
use coarsetime::{Duration, Instant};
use parking_lot::RwLock;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::{
	atomic::{AtomicBool, AtomicU64, Ordering},
	OnceLock,
};
use tinyvec::TinyVec;

#[derive(Clone, Copy)]
struct TurfProcessRequest {
	fdm_max_steps: i32,
	equalize_enabled: bool,
	planet_share_ratio: f32,
	group_pressure_goal: f32,
}

#[derive(Default)]
struct TurfProcessResult {
	generation: u64,
	turf_cost_ms: f32,
	post_process_cost_ms: f32,
	total_cost_ms: f32,
	low_pressure_turfs: usize,
	high_pressure_turfs: usize,
	active_turfs: usize,
	seed_turfs: usize,
	retained_turfs: usize,
	pending_turfs: usize,
	snapshot_mixtures: usize,
	published_mixtures: usize,
	rejected_generations: u64,
	group_cost_ms: f32,
	group_turfs: usize,
}

static TURF_PROCESS_CHANNEL: OnceLock<(
	flume::Sender<TurfProcessRequest>,
	flume::Receiver<TurfProcessRequest>,
)> = OnceLock::new();
static TURF_RESULT_CHANNEL: OnceLock<(
	flume::Sender<TurfProcessResult>,
	flume::Receiver<TurfProcessResult>,
)> = OnceLock::new();
static TURF_PROCESS_RUNNING: AtomicBool = AtomicBool::new(false);
static TURF_GENERATION: AtomicU64 = AtomicU64::new(0);
static TURF_REJECTED_GENERATIONS: AtomicU64 = AtomicU64::new(0);

fn turf_process_channel() -> &'static (
	flume::Sender<TurfProcessRequest>,
	flume::Receiver<TurfProcessRequest>,
) {
	TURF_PROCESS_CHANNEL.get_or_init(|| flume::bounded(1))
}

fn turf_result_channel() -> &'static (
	flume::Sender<TurfProcessResult>,
	flume::Receiver<TurfProcessResult>,
) {
	TURF_RESULT_CHANNEL.get_or_init(|| flume::bounded(1))
}

/// Returns: If a processing thread is running or not.
/// NOTE: the DM caller (SSair.thread_running) was removed as dead code; this
/// bind is currently unused but kept as a harmless export.
#[byondapi::bind("/datum/controller/subsystem/air/proc/thread_running")]
#[auxmacros::panic_safe]
fn thread_running_hook() -> Result<ByondValue> {
	Ok(TURF_PROCESS_RUNNING.load(Ordering::Acquire).into())
}

/// Returns: If this cycle is interrupted by overtiming or not. Calls all outstanding callbacks created by other processes, usually ones that can't run on other threads and only the main thread.
#[byondapi::bind("/datum/controller/subsystem/air/proc/finish_turf_processing_auxtools")]
#[auxmacros::panic_safe]
fn finish_process_turfs(time_remaining: ByondValue) -> Result<ByondValue> {
	Ok(process_callbacks_for_millis(time_remaining.get_number()? as u64).into())
}
/// Returns: If this cycle is interrupted by overtiming or not. Starts a processing turfs cycle.
#[byondapi::bind("/datum/controller/subsystem/air/proc/process_turfs_auxtools")]
#[auxmacros::panic_safe]
fn process_turf_hook(mut src: ByondValue, remaining: ByondValue) -> Result<ByondValue> {
	let _ = remaining;
	if let Ok(result) = turf_result_channel().1.try_recv() {
		let previous_turf_cost = src.read_number_id(byond_string!("cost_turfs"))?;
		src.write_var_id(
			byond_string!("cost_turfs"),
			&(0.8 * previous_turf_cost + 0.2 * result.turf_cost_ms).into(),
		)?;
		let previous_post_cost = src.read_number_id(byond_string!("cost_post_process"))?;
		src.write_var_id(
			byond_string!("cost_post_process"),
			&(0.8 * previous_post_cost + 0.2 * result.post_process_cost_ms).into(),
		)?;
		src.write_var_id(
			byond_string!("low_pressure_turfs"),
			&(result.low_pressure_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("high_pressure_turfs"),
			&(result.high_pressure_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_generation"),
			&(result.generation as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_compute_cost"),
			&result.total_cost_ms.into(),
		)?;
		src.write_var_id(
			byond_string!("async_active_turfs"),
			&(result.active_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_seed_turfs"),
			&(result.seed_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_retained_turfs"),
			&(result.retained_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_pending_turfs"),
			&(result.pending_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_snapshot_mixtures"),
			&(result.snapshot_mixtures as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_published_mixtures"),
			&(result.published_mixtures as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_rejected_generations"),
			&(result.rejected_generations as f32).into(),
		)?;
		let previous_group_cost = src.read_number_id(byond_string!("cost_groups"))?;
		src.write_var_id(
			byond_string!("cost_groups"),
			&(0.8 * previous_group_cost + 0.2 * result.group_cost_ms).into(),
		)?;
		src.write_var_id(
			byond_string!("num_group_turfs_processed"),
			&(result.group_turfs as f32).into(),
		)?;
		return Ok(false.into());
	}

	if TURF_PROCESS_RUNNING.load(Ordering::Acquire) {
		return Ok(true.into());
	}

	let fdm_max_steps = src
		.read_number_id(byond_string!("share_max_steps"))
		.unwrap_or(1.0) as i32;
	let equalize_enabled =
		cfg!(feature = "fastmos") && src.read_number_id(byond_string!("equalize_enabled"))? != 0.0;

	let planet_share_ratio = src
		.read_number_id(byond_string!("planet_share_ratio"))
		.unwrap_or(GAS_DIFFUSION_CONSTANT);
	let group_pressure_goal = src
		.read_number_id(byond_string!("excited_group_pressure_goal"))
		.unwrap_or(0.5);

	let request = TurfProcessRequest {
		fdm_max_steps,
		equalize_enabled,
		planet_share_ratio,
		group_pressure_goal,
	};
	TURF_PROCESS_RUNNING.store(true, Ordering::Release);
	if turf_process_channel().0.try_send(request).is_err() {
		TURF_PROCESS_RUNNING.store(false, Ordering::Release);
	}
	Ok(true.into())
}

#[byondapi::init]
fn start_turf_process_worker() {
	rayon::spawn(|| {
		let mut snapshot = MixtureSnapshot::default();
		loop {
			let request = match turf_process_channel().1.recv() {
				Ok(request) => request,
				Err(_) => return,
			};
			let _task_lock = TASKS.read();
			apply_pending_topology_updates();
			let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
				process_turf(request, &mut snapshot)
			}))
			.unwrap_or_else(|panic| {
				TURF_REJECTED_GENERATIONS.fetch_add(1, Ordering::AcqRel);
				super::reactivate_all_turfs();
				snapshot.release_values();
				let message = panic
					.downcast_ref::<&str>()
					.copied()
					.or_else(|| panic.downcast_ref::<String>().map(String::as_str))
					.unwrap_or("unknown panic");
				eprintln!("auxmos turf worker rejected a panicked generation: {message}");
				TurfProcessResult {
					generation: TURF_GENERATION.fetch_add(1, Ordering::AcqRel) + 1,
					rejected_generations: TURF_REJECTED_GENERATIONS.load(Ordering::Acquire),
					..Default::default()
				}
			});
			apply_pending_topology_updates();
			if turf_result_channel().0.send(result).is_err() {
				return;
			}
			TURF_PROCESS_RUNNING.store(false, Ordering::Release);
		}
	});
}

#[cfg_attr(feature = "tracy", tracing::instrument(skip_all))]
fn process_turf(request: TurfProcessRequest, snapshot: &mut MixtureSnapshot) -> TurfProcessResult {
	let total_start = Instant::now();
	let (active_nodes, seed_turfs) = with_turf_gases_read(|arena| {
		let seeds = take_active_turfs();
		let seed_count = seeds.len();
		let mut nodes = rustc_hash::FxHashSet::default();
		for turf_id in seeds {
			if let Some(node) = arena.get_id(turf_id) {
				nodes.insert(node);
				nodes.extend(arena.adjacent_node_ids(node));
			}
		}
		(nodes, seed_count)
	});
	if active_nodes.is_empty() {
		return TurfProcessResult {
			generation: TURF_GENERATION.fetch_add(1, Ordering::AcqRel) + 1,
			total_cost_ms: total_start.elapsed().as_millis() as f32,
			rejected_generations: TURF_REJECTED_GENERATIONS.load(Ordering::Acquire),
			..Default::default()
		};
	}
	let snapshot_mix_ids = with_turf_gases_read(|arena| {
		let mut ids = rustc_hash::FxHashSet::default();
		for &node in &active_nodes {
			if let Some(mixture) = arena.get(node) {
				ids.insert(mixture.mix);
			}
			ids.extend(
				arena
					.adjacent_node_ids(node)
					.filter_map(|adjacent| arena.get(adjacent).map(|mixture| mixture.mix)),
			);
		}
		ids.into_iter().collect::<Vec<_>>()
	});
	GasArena::snapshot_mixtures_into(&snapshot_mix_ids, snapshot);
	//this will block until process_turfs is called
	let (low_pressure_turfs, high_pressure_turfs, pressure_events, turf_cost_ms) = {
		let start_time = Instant::now();
		let (low_pressure_turfs, high_pressure_turfs, pressure_events) = fdm(
			(&start_time, Duration::from_secs(60)),
			request.fdm_max_steps,
			request.equalize_enabled,
			snapshot,
			&active_nodes,
		);
		let bench = start_time.elapsed().as_millis() as f32;
		(
			low_pressure_turfs,
			high_pressure_turfs,
			pressure_events,
			bench,
		)
	};
	planet_process(request.planet_share_ratio, snapshot, &active_nodes);
	let next_active = with_turf_gases_read(|arena| {
		active_nodes
			.par_iter()
			.filter(|&&node| {
				arena
					.get(node)
					.is_some_and(|mixture| should_process(node, mixture, snapshot, arena))
			})
			.filter_map(|&node| arena.get(node).map(|mixture| mixture.id))
			.collect::<rustc_hash::FxHashSet<_>>()
	});
	let retained_turfs = next_active.len();
	let published_ids = GasArena::publish_snapshot(&snapshot_mix_ids, snapshot);
	let published = published_ids.is_some();
	if !published {
		TURF_REJECTED_GENERATIONS.fetch_add(1, Ordering::AcqRel);
	} else {
		super::reactivate_turfs(next_active);
	}
	let post_process_cost_ms = {
		let start_time = Instant::now();
		if published {
			post_process(&active_nodes);
		}
		start_time.elapsed().as_millis() as f32
	};
	let (group_turfs, group_cost_ms) = if published {
		dispatch_pressure_events(pressure_events);
		super::groups::process_groups(request.group_pressure_goal, low_pressure_turfs.clone())
	} else {
		(0, 0.0)
	};
	if published && request.equalize_enabled {
		#[cfg(feature = "fastmos")]
		{
			super::katmos::send_to_equalize(high_pressure_turfs.clone());
		}
	}
	// The snapshot vector stays indexed by arena ID, but completed mixtures must
	// not retain their heap-backed gas arrays. The first generation snapshots the
	// whole station; keeping those clones would permanently duplicate the gas arena
	// even after the active frontier shrinks to a few hundred mixtures.
	snapshot.release_values();
	TurfProcessResult {
		generation: TURF_GENERATION.fetch_add(1, Ordering::AcqRel) + 1,
		turf_cost_ms,
		post_process_cost_ms,
		total_cost_ms: total_start.elapsed().as_millis() as f32,
		low_pressure_turfs: low_pressure_turfs.len(),
		high_pressure_turfs: high_pressure_turfs.len(),
		active_turfs: active_nodes.len(),
		seed_turfs,
		retained_turfs,
		pending_turfs: super::pending_active_turfs(),
		snapshot_mixtures: snapshot_mix_ids.len(),
		published_mixtures: published_ids.as_ref().map_or(0, Vec::len),
		rejected_generations: TURF_REJECTED_GENERATIONS.load(Ordering::Acquire),
		group_cost_ms,
		group_turfs,
	}
}

#[cfg_attr(not(target_feature = "avx2"), auxmacros::generate_simd_functions)]
#[cfg_attr(feature = "tracy", tracing::instrument(skip_all))]
fn planet_process(
	planet_share_ratio: f32,
	all_mixtures: &MixtureSnapshot,
	active_nodes: &rustc_hash::FxHashSet<NodeIndex>,
) {
	with_turf_gases_read(|arena| {
		with_planetary_atmos(|map| {
			active_nodes
				.par_iter()
				.filter_map(|&node_idx| {
					let mix = arena.get(node_idx)?;
					Some((mix, mix.planetary_atmos.and_then(|id| map.get(&id))?))
				})
				.for_each(|(turf_mix, planet_atmos)| {
					if let Some(gas_read) = all_mixtures
						.get(turf_mix.mix)
						.and_then(|lock| lock.try_upgradable_read())
					{
						let comparison = gas_read.compare(planet_atmos);
						let has_temp_difference = gas_read.temperature_compare(planet_atmos);
						if let Some(mut gas) = (has_temp_difference || (comparison > GAS_MIN_MOLES))
							.then(|| {
								parking_lot::lock_api::RwLockUpgradableReadGuard::try_upgrade(
									gas_read,
								)
								.ok()
							})
							.flatten()
						{
							if comparison > 0.1 || has_temp_difference {
								gas.share_ratio(planet_atmos, planet_share_ratio);
							} else {
								gas.copy_from_mutable(planet_atmos);
							}
						}
					}
				})
		})
	});
}

// Compares with neighbors, returning early if any of them are valid.
fn should_process(
	index: NodeIndex,
	mixture: &TurfMixture,
	all_mixtures: &MixtureSnapshot,
	arena: &TurfGases,
) -> bool {
	mixture.enabled()
		&& arena.adjacent_node_ids(index).next().is_some()
		&& all_mixtures
			.get(mixture.mix)
			.and_then(RwLock::try_read)
			.map_or(false, |gas| {
				for entry in arena.adjacent_mixes(index, all_mixtures) {
					if let Some(mix) = entry.try_read() {
						if gas.temperature_compare(&mix)
							|| gas.compare_with(&mix, MINIMUM_MOLES_DELTA_TO_MOVE)
						{
							return true;
						}
					} else {
						return false;
					}
				}
				false
			})
}

// Creates the combined gas mixture of all this mix's neighbors, as well as gathering some other pertinent info for future processing.
// Clippy go away, this type is only used once
#[allow(clippy::type_complexity)]
fn process_cell(
	index: NodeIndex,
	all_mixtures: &MixtureSnapshot,
	arena: &TurfGases,
) -> Option<(NodeIndex, Mixture, TinyVec<[(TurfID, f32); 6]>, i32)> {
	let mut adj_amount = 0;
	/*
		Getting write locks is potential danger zone,
		so we make sure we don't do that unless we
		absolutely need to. Saving is fast enough.
	*/
	let mut end_gas = Mixture::from_vol(crate::constants::CELL_VOLUME);
	let mut pressure_diffs: TinyVec<[(TurfID, f32); 6]> = Default::default();
	/*
		The pressure here is negative
		because we're going to be adding it
		to the base turf's pressure later on.
		It's multiplied by the diffusion constant
		because it's not representing the total
		gas pressure difference but the force exerted
		due to the pressure gradient.
		Technically that's ρν², but, like, video games.
	*/
	for (&loc, entry) in
		arena.adjacent_mixes_with_adj_ids(index, all_mixtures, petgraph::Direction::Incoming)
	{
		match entry.try_read() {
			Some(mix) => {
				end_gas.merge(&mix);
				adj_amount += 1;
				pressure_diffs.push((loc, -mix.return_pressure() * GAS_DIFFUSION_CONSTANT));
			}
			None => return None, // this would lead to inconsistencies--no bueno
		}
	}
	/*
		This method of simulating diffusion
		diverges at coefficients that are
		larger than the inverse of the number
		of adjacent finite elements.
		As such, we must multiply it
		by a coefficient that is at most
		as big as this coefficient. The
		GAS_DIFFUSION_CONSTANT chosen here
		is 1/8, chosen both because it is
		smaller than 1/7 and because, in
		floats, 1/8 is exact and so are
		all multiples of it up to 1.
		(Technically up to 2,097,152,
		but I digress.)
	*/
	end_gas.multiply(GAS_DIFFUSION_CONSTANT);
	Some((index, end_gas, pressure_diffs, adj_amount))
}

// Solving the heat equation using a Finite Difference Method, an iterative stencil loop.
#[cfg_attr(not(target_feature = "avx2"), auxmacros::generate_simd_functions)]
#[cfg_attr(feature = "tracy", tracing::instrument(skip_all))]
fn fdm(
	(start_time, remaining_time): (&Instant, Duration),
	fdm_max_steps: i32,
	equalize_enabled: bool,
	all_mixtures: &MixtureSnapshot,
	active_nodes: &rustc_hash::FxHashSet<NodeIndex>,
) -> (
	BTreeSet<TurfID>,
	BTreeSet<TurfID>,
	Vec<(TurfID, TinyVec<[(TurfID, f32); 6]>)>,
) {
	/*
		This is the replacement system for LINDA. LINDA requires a lot of bookkeeping,
		which, when coefficient-wise operations are this fast, is all just unnecessary overhead.
		This is a much simpler FDM system, basically like LINDA but without its most important feature,
		sleeping turfs, which is why I've renamed it to fdm.
	*/
	let mut low_pressure_turfs: BTreeSet<TurfID> = Default::default();
	let mut high_pressure_turfs: BTreeSet<TurfID> = Default::default();
	let mut pressure_events = Vec::new();
	let mut cur_count = 1;
	with_turf_gases_read(|arena| {
		loop {
			if cur_count > fdm_max_steps || start_time.elapsed() >= remaining_time {
				break;
			}
			if active_nodes.is_empty() {
				break;
			}
			{
				let turfs_to_save = active_nodes
					.par_iter()
					.filter_map(|&idx| arena.get(idx).map(|mixture| (idx, mixture)))
					.filter(|(index, mixture)| should_process(*index, mixture, all_mixtures, arena))
					.filter_map(|(index, _)| process_cell(index, all_mixtures, arena))
					.collect::<Vec<_>>();
				/*
					For the optimization-heads reading this: this is not an unnecessary collect().
					Saving all this to the turfs_to_save vector is, in fact, the reason
					that gases don't need an archive anymore--this *is* the archival step,
					simultaneously saving how the gases will change after the fact.
					In short: the above actually needs to finish before the below starts
					for consistency, so collect() is desired. This has been tested, by the way.
				*/
				let (low_pressure, high_pressure): (Vec<_>, Vec<_>) = turfs_to_save
					.into_par_iter()
					.filter_map(|(i, end_gas, mut pressure_diffs, adj_amount)| {
						let m = arena.get(i)?;
						all_mixtures.get(m.mix).map(|entry| {
							let mut max_diff = 0.0_f32;
							let moved_pressure = {
								let gas = entry.read();
								gas.return_pressure() * GAS_DIFFUSION_CONSTANT
							};
							for pressure_diff in &mut pressure_diffs {
								// pressure_diff.1 here was set to a negative above, so we just add.
								pressure_diff.1 += moved_pressure;
								max_diff = max_diff.max(pressure_diff.1.abs());
							}
							/*
								1.0 - GAS_DIFFUSION_CONSTANT * adj_amount is going to be
								precisely equal to the amount the surrounding tiles'
								end_gas have "taken" from this tile--
								they didn't actually take anything, just calculated
								how much would be. This is the "taking" step.
								Just to illustrate: say you have a turf with 3 neighbors.
								Each of those neighbors will have their end_gas added to by
								GAS_DIFFUSION_CONSTANT (at this writing, 0.125) times
								this gas. So, 1.0 - (0.125 * adj_amount) = 0.625--
								exactly the amount those gases "took" from this.
							*/
							{
								let gas: &mut Mixture = &mut entry.write();
								gas.multiply(1.0 - (adj_amount as f32 * GAS_DIFFUSION_CONSTANT));
								gas.merge(&end_gas);
							}
							/*
								If there is neither a major pressure difference
								nor are there any visible gases nor does it need
								to react, we're done outright. We don't need
								to do any more and we don't need to send the
								value to byond, so we don't. However, if we do...
							*/
							(m.id, pressure_diffs, max_diff, i)
						})
					})
					.partition(|&(_, _, max_diff, _)| max_diff <= 5.0);

				high_pressure_turfs.par_extend(high_pressure.par_iter().map(|(i, _, _, _)| i));
				low_pressure_turfs.par_extend(low_pressure.par_iter().map(|(i, _, _, _)| i));
				//tossing things around is already handled by katmos, so we don't need to do it here.
				if !equalize_enabled {
					pressure_events.extend(
						high_pressure
							.into_par_iter()
							.filter_map(|(_, pressures, _, node_id)| {
								Some((arena.get(node_id)?.id, pressures))
							})
							.collect::<Vec<_>>(),
					);
				}
			}

			cur_count += 1;
		}
	});
	(low_pressure_turfs, high_pressure_turfs, pressure_events)
}

fn dispatch_pressure_events(events: Vec<(TurfID, TinyVec<[(TurfID, f32); 6]>)>) {
	events.into_par_iter().for_each(|(id, diffs)| {
		let sender = byond_callback_sender();
		drop(sender.try_send(Box::new(move || {
			let turf = ByondValue::new_ref(ValueType::Turf, id);
			for (other_id, diff) in diffs.iter().copied() {
				if other_id == 0 {
					continue;
				}
				let other_turf = ByondValue::new_ref(ValueType::Turf, other_id);
				if diff > 5.0 {
					turf.call_id(
						byond_string!("consider_pressure_difference"),
						&[other_turf, diff.into()],
					)
					.wrap_err("Processing consider pressure differences")?;
				} else if diff < -5.0 {
					other_turf
						.call_id(
							byond_string!("consider_pressure_difference"),
							&[turf, (-diff).into()],
						)
						.wrap_err("Processing consider pressure differences")?;
				}
			}
			Ok(())
		})));
	});
}

// Checks if the gas can react or can update visuals, returns None if not.
fn post_process_cell<'a>(
	mixture: &'a TurfMixture,
	vis: &[Option<f32>],
	all_mixtures: &[RwLock<Mixture>],
	reactions: &BTreeMap<crate::reaction::ReactionPriority, crate::reaction::Reaction>,
) -> Option<(&'a TurfMixture, bool, bool)> {
	all_mixtures
		.get(mixture.mix)
		.and_then(RwLock::try_read)
		.and_then(|gas| {
			let should_update_visuals = gas.vis_hash_changed(vis, &mixture.vis_hash);
			let reactable = gas.can_react_with_reactions(reactions);
			(should_update_visuals || reactable).then_some((
				mixture,
				should_update_visuals,
				reactable,
			))
		})
}

// Goes through every turf, checks if it should reset to planet atmos, if it should
// update visuals, if it should react, sends a callback if it should.
#[cfg_attr(not(target_feature = "avx2"), auxmacros::generate_simd_functions)]
#[cfg_attr(feature = "tracy", tracing::instrument(skip_all))]
fn post_process(active_nodes: &rustc_hash::FxHashSet<NodeIndex>) {
	let vis = crate::gas::visibility_copies();
	with_turf_gases_read(|arena| {
		let processables = crate::gas::types::with_reactions(|reactions| {
			GasArena::with_all_mixtures(|all_mixtures| {
				active_nodes
					.par_iter()
					.filter_map(|&node_index| {
						let mix = arena.get(node_index)?;
						mix.enabled().then_some(mix)
					})
					.filter_map(|mixture| post_process_cell(mixture, &vis, all_mixtures, reactions))
					.collect::<Vec<_>>()
			})
		});
		processables
			.into_par_iter()
			.for_each(|(tmix, should_update_vis, should_react)| {
				let sender = byond_callback_sender();
				let id = tmix.id;
				drop(sender.try_send(Box::new(move || {
					let turf = ByondValue::new_ref(ValueType::Turf, id);
					if should_react {
						if let Ok(air) = turf.read_var_id(byond_string!("air")) {
							if !air.is_null() {
								react_hook(air, turf).wrap_err("Reacting")?;
							}
						}
					}
					if should_update_vis {
						update_visuals(turf).wrap_err("Updating Visuals")?;
					}
					Ok(())
				})));
			});
	});
}
