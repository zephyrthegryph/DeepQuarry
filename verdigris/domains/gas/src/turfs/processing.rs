use super::*;
use crate::{gas::MixtureSnapshot, react_hook, GasArena};
use auxcallback::{byond_callback_sender, process_callbacks_for_millis};
use byondapi::{byond_string, prelude::*};
use parking_lot::RwLock;
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::sync::{
	atomic::{AtomicBool, AtomicU64, Ordering},
	OnceLock,
};
use std::time::{Duration, Instant};
use tinyvec::TinyVec;

#[derive(Clone, Copy)]
struct TurfProcessRequest {
	fdm_max_steps: i32,
	planet_share_ratio: f32,
	target_worker_ms: f32,
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
	retained_temperature_turfs: usize,
	retained_mole_turfs: usize,
	pending_turfs: usize,
	pending_urgent_turfs: usize,
	pending_fresh_turfs: usize,
	pending_frontier_turfs: usize,
	snapshot_mixtures: usize,
	published_mixtures: usize,
	rejected_generations: u64,
	conservation_rejections: u64,
	closed_components: usize,
	conservation_violation_components: usize,
	conservation_worst_component_mixtures: usize,
	conservation_max_gas_delta: f32,
	conservation_max_energy_delta: f32,
	conservation_diagnostic: String,
	group_cost_ms: f32,
	group_turfs: usize,
	seed_limit: usize,
	selection_ms: f32,
	snapshot_ms: f32,
	fdm_ms: f32,
	equalize_ms: f32,
	publication_ms: f32,
	semantic_events: usize,
	reaction_events: usize,
	overlay_events: usize,
	reaction_callback_ms: f32,
	overlay_callback_ms: f32,
	cancelled: bool,
	pressure_urgency_kpa: f32,
}

// The worker consumes a bounded seed batch before doing fallible processing.
// Preserve that exact batch so panic recovery retries only affected cells rather
// than enrolling every mutable turf on the station.
static PANIC_RETRY_TURFS: RwLock<Vec<CellHandle>> = parking_lot::const_rwlock(Vec::new());
/// Main-thread semantic publication costs accumulated by the compact callback.
/// They are reported with the following completed worker generation.
static REACTION_CALLBACK_MICROS: AtomicU64 = AtomicU64::new(0);
static OVERLAY_CALLBACK_MICROS: AtomicU64 = AtomicU64::new(0);

#[derive(Default)]
struct ConservationSignature {
	gases: rustc_hash::FxHashMap<usize, f64>,
	energy: f64,
}

#[derive(Debug)]
struct ConservationViolation {
	component_size: usize,
	mixture_ids: Vec<usize>,
	gas_deltas: Vec<(usize, f64, f64, f64)>,
	energy_before: f64,
	energy_after: f64,
}

fn conservation_signature(mix_ids: &[usize], mixtures: &MixtureSnapshot) -> ConservationSignature {
	let mut signature = ConservationSignature::default();
	let mut seen = rustc_hash::FxHashSet::default();
	for &mix_id in mix_ids {
		if !seen.insert(mix_id) {
			continue;
		}
		let Some(mixture) = mixtures.get(mix_id) else {
			continue;
		};
		let mixture = mixture.read();
		for (gas, moles) in mixture.enumerate() {
			*signature.gases.entry(gas).or_default() += moles as f64;
		}
		signature.energy += mixture.thermal_energy() as f64;
	}
	signature
}

#[cfg(test)]
fn conserves(before: &ConservationSignature, after: &ConservationSignature) -> bool {
	conservation_violation(&[], before, after).is_none()
}

fn conservation_violation(
	component: &[usize],
	before: &ConservationSignature,
	after: &ConservationSignature,
) -> Option<ConservationViolation> {
	let gas_ids = before
		.gases
		.keys()
		.chain(after.gases.keys())
		.copied()
		.collect::<rustc_hash::FxHashSet<_>>();
	let mut gas_deltas = gas_ids
		.into_iter()
		.filter_map(|gas| {
			let before_moles = before.gases.get(&gas).copied().unwrap_or_default();
			let after_moles = after.gases.get(&gas).copied().unwrap_or_default();
			// SIMD float diffusion and trace-gas garbage collection introduce tiny
			// per-component rounding losses. Reject material loss, not sub-centimole
			// numerical noise; the historical shuttle bug lost roughly 68%.
			let tolerance = 0.1_f64.max(before_moles.abs() * 0.001);
			((before_moles - after_moles).abs() > tolerance).then_some((
				gas,
				before_moles,
				after_moles,
				after_moles - before_moles,
			))
		})
		.collect::<Vec<_>>();
	gas_deltas.sort_by(|a, b| b.3.abs().total_cmp(&a.3.abs()));
	let energy_tolerance = 100.0_f64.max(before.energy.abs() * 0.001);
	let energy_bad = (before.energy - after.energy).abs() > energy_tolerance;
	(!gas_deltas.is_empty() || energy_bad).then_some(ConservationViolation {
		component_size: component.len(),
		mixture_ids: component.iter().copied().take(16).collect(),
		gas_deltas,
		energy_before: before.energy,
		energy_after: after.energy,
	})
}

/// Project a closed transaction component back onto its conserved mass/energy
/// manifold. Pairwise edge flux is conservative algebraically, but positivity
/// clamps and the final f64 -> f32 representation can otherwise accumulate a
/// one-sided residual. Scaling each gas independently and thermal energy as a
/// whole preserves the solved spatial distribution while making creation or
/// destruction structurally impossible for a closed component.
fn project_closed_conservation(
	component: &[usize],
	target: &ConservationSignature,
	mixtures: &MixtureSnapshot,
) {
	let mut states = Vec::with_capacity(component.len());
	let mut current = ConservationSignature::default();
	let mut seen = rustc_hash::FxHashSet::default();
	for &mixture_id in component {
		if !seen.insert(mixture_id) {
			continue;
		}
		let Some(gas) = mixtures.get(mixture_id).and_then(RwLock::try_read) else {
			return;
		};
		let moles = gas
			.composition_moles()
			.into_iter()
			.map(f64::from)
			.collect::<Vec<_>>();
		for (gas_id, amount) in moles.iter().copied().enumerate() {
			*current.gases.entry(gas_id).or_default() += amount;
		}
		let energy = f64::from(gas.thermal_energy());
		current.energy += energy;
		states.push((mixture_id, moles, energy));
	}
	let gas_count = target
		.gases
		.keys()
		.chain(current.gases.keys())
		.max()
		.map_or(0, |maximum| maximum + 1);
	let gas_scales = (0..gas_count)
		.map(|gas_id| {
			let present = current.gases.get(&gas_id).copied().unwrap_or_default();
			let wanted = target.gases.get(&gas_id).copied().unwrap_or_default();
			if present > 0.0 {
				wanted / present
			} else {
				0.0
			}
		})
		.collect::<Vec<_>>();
	let energy_scale = if current.energy > 0.0 {
		target.energy / current.energy
	} else {
		0.0
	};
	for (mixture_id, mut moles, energy) in states {
		moles.resize(gas_count, 0.0);
		for (gas_id, amount) in moles.iter_mut().enumerate() {
			*amount *= gas_scales[gas_id];
		}
		if let Some(mut gas) = mixtures.get(mixture_id).and_then(RwLock::try_write) {
			gas.replace_conserved(&moles, energy * energy_scale);
		}
	}
}

fn format_conservation_violations(violations: &[ConservationViolation]) -> String {
	if violations.is_empty() {
		return String::new();
	}
	let worst = violations
		.iter()
		.max_by(|a, b| {
			let a_delta = (a.energy_after - a.energy_before)
				.abs()
				.max(a.gas_deltas.first().map_or(0.0, |entry| entry.3.abs()));
			let b_delta = (b.energy_after - b.energy_before)
				.abs()
				.max(b.gas_deltas.first().map_or(0.0, |entry| entry.3.abs()));
			a_delta.total_cmp(&b_delta)
		})
		.expect("non-empty violations");
	let gases = worst
		.gas_deltas
		.iter()
		.take(8)
		.map(|(gas, before, after, delta)| {
			format!("gas={gas} before={before:.6} after={after:.6} delta={delta:+.6}")
		})
		.collect::<Vec<_>>()
		.join(", ");
	format!(
		"ATMOS_CONSERVATION_ERROR components={} worst_component_mixtures={} sample_mixture_ids={:?} energy_before={:.6} energy_after={:.6} energy_delta={:+.6} gas_deltas=[{}]",
		violations.len(),
		worst.component_size,
		worst.mixture_ids,
		worst.energy_before,
		worst.energy_after,
		worst.energy_after - worst.energy_before,
		gases,
	)
}

fn report_conservation_violations(_violations: &[ConservationViolation], _diagnostic: &str) {
	#[cfg(test)]
	panic!("atmos conservation failure: {_violations:#?}");
	#[cfg(not(test))]
	eprintln!("{_diagnostic}");
}

/// The solver only processes an edge when at least one endpoint is an active
/// seed and both mutable endpoints participate in this generation. Keeping this
/// predicate shared prevents one-sided subtraction/addition.
fn solver_edge_enabled(
	arena: &TurfGases,
	node: NodeIndex,
	neighbor: NodeIndex,
	participant_nodes: &rustc_hash::FxHashSet<NodeIndex>,
) -> bool {
	if !participant_nodes.contains(&node) {
		return false;
	}
	let Some(node_mixture) = arena.get(node) else {
		return false;
	};
	let Some(neighbor_mixture) = arena.get(neighbor) else {
		return false;
	};
	// Topology is published incrementally. During a bulk explosion update one
	// side of a physical face can briefly retain an old edge after the other side
	// has removed it. A diffusion stencil must never consume that half-edge: its
	// opposite endpoint would not apply the equal-and-opposite transfer. Only a
	// reciprocal pair is an authoritative physical face.
	node_mixture.enabled()
		&& (neighbor_mixture.is_immutable()
			|| (neighbor_mixture.enabled() && participant_nodes.contains(&neighbor)))
		&& arena.graph.find_edge(neighbor, node).is_some()
}

/// Return the complete mutable pressure region containing `start`. Turf solver
/// transactions are normally bounded for latency, but an open-to-vacuum region
/// is a single physical reservoir: partitioning it changes its apparent volume
/// and aperture ratio and makes evacuation depend on scheduler order.
fn connected_mutable_region(arena: &TurfGases, start: NodeIndex) -> Vec<NodeIndex> {
	let mut region = Vec::new();
	let mut visited = rustc_hash::FxHashSet::default();
	let mut frontier = vec![start];
	while let Some(node) = frontier.pop() {
		if !visited.insert(node) {
			continue;
		}
		let Some(mixture) = arena.get(node) else {
			continue;
		};
		if mixture.is_immutable() || !mixture.enabled() {
			continue;
		}
		region.push(node);
		for neighbor in arena.adjacent_node_ids(node) {
			let Some(neighbor_mixture) = arena.get(neighbor) else {
				continue;
			};
			if !neighbor_mixture.is_immutable()
				&& neighbor_mixture.enabled()
				&& arena.graph.find_edge(neighbor, node).is_some()
			{
				frontier.push(neighbor);
			}
		}
	}
	region
}

/// Find selected mutable cells with a reciprocal face onto an immutable vacuum
/// reservoir. This inspects gas state in one arena read rather than taking a gas
/// lock once per face.
fn selected_vacuum_apertures(
	arena: &TurfGases,
	nodes: &rustc_hash::FxHashSet<NodeIndex>,
) -> Vec<NodeIndex> {
	let candidates = nodes
		.iter()
		.copied()
		.filter_map(|node| {
			let external_mixes = arena
				.adjacent_node_ids(node)
				.filter(|&neighbor| arena.graph.find_edge(neighbor, node).is_some())
				.filter_map(|neighbor| arena.get(neighbor))
				.filter(|mixture| mixture.is_immutable())
				.map(|mixture| mixture.mix)
				.collect::<Vec<_>>();
			(!external_mixes.is_empty()).then_some((node, external_mixes))
		})
		.collect::<Vec<_>>();
	if candidates.is_empty() {
		return Vec::new();
	}
	GasArena::with_all_mixtures(|all_mixtures| {
		candidates
			.into_iter()
			.filter_map(|(node, external_mixes)| {
				external_mixes
					.into_iter()
					.any(|mix| {
						all_mixtures
							.get(mix)
							.is_some_and(|gas| gas.read().return_pressure() < 1.0)
					})
					.then_some(node)
			})
			.collect()
	})
}

/// Returns mutable connected components that have no immutable boundary. Only
/// those components are closed systems and therefore subject to strict mass and
/// energy conservation at publication.
fn closed_component_mixtures(
	arena: &TurfGases,
	active_nodes: &rustc_hash::FxHashSet<NodeIndex>,
	participant_nodes: &rustc_hash::FxHashSet<NodeIndex>,
) -> Vec<Vec<usize>> {
	let mut visited = rustc_hash::FxHashSet::default();
	let mut closed = Vec::new();
	for &start in active_nodes {
		if visited.contains(&start) {
			continue;
		}
		let mut frontier = vec![start];
		let mut component = Vec::new();
		let mut has_immutable_boundary = false;
		while let Some(node) = frontier.pop() {
			if !visited.insert(node) {
				continue;
			}
			let Some(mixture) = arena.get(node) else {
				continue;
			};
			// Planetary cells exchange with an external atmosphere reservoir during
			// planet_process(), so their component is intentionally not closed.
			if mixture.planetary_atmos.is_some() {
				has_immutable_boundary = true;
			}
			component.push(mixture.mix);
			for neighbor in arena.adjacent_node_ids(node) {
				if !solver_edge_enabled(arena, node, neighbor, participant_nodes) {
					continue;
				}
				let Some(neighbor_mixture) = arena.get(neighbor) else {
					continue;
				};
				if neighbor_mixture.is_immutable() {
					has_immutable_boundary = true;
				} else if active_nodes.contains(&neighbor) {
					if !visited.contains(&neighbor) {
						frontier.push(neighbor);
					}
				}
			}
		}
		if !has_immutable_boundary && !component.is_empty() {
			closed.push(component);
		}
	}
	// A mixture may temporarily or deliberately be referenced by several turf
	// nodes. Node components which share one are a single conservation domain;
	// projecting them separately rescales the same mixture twice.
	coalesce_overlapping_mixture_components(closed)
}

fn coalesce_overlapping_mixture_components(components: Vec<Vec<usize>>) -> Vec<Vec<usize>> {
	fn root(parents: &mut [usize], mut index: usize) -> usize {
		while parents[index] != index {
			parents[index] = parents[parents[index]];
			index = parents[index];
		}
		index
	}

	let mut parents = (0..components.len()).collect::<Vec<_>>();
	let mut owner = rustc_hash::FxHashMap::default();
	for (index, component) in components.iter().enumerate() {
		for &mixture_id in component {
			if let Some(&other) = owner.get(&mixture_id) {
				let left = root(&mut parents, index);
				let right = root(&mut parents, other);
				if left != right {
					parents[right] = left;
				}
			} else {
				owner.insert(mixture_id, index);
			}
		}
	}
	let mut merged: rustc_hash::FxHashMap<usize, rustc_hash::FxHashSet<usize>> =
		rustc_hash::FxHashMap::default();
	for (index, component) in components.into_iter().enumerate() {
		let component_root = root(&mut parents, index);
		merged.entry(component_root).or_default().extend(component);
	}
	merged
		.into_values()
		.map(|component| component.into_iter().collect())
		.collect()
}

/// Partition the mutable cells touched by this generation using the exact edge
/// predicate used by `process_cell`. Each component is an independent optimistic
/// transaction, so a synchronous mutation can reject its room/pipenet without
/// throwing away unrelated diffusion work from the same worker batch.
fn transaction_components(
	arena: &TurfGases,
	active_nodes: &rustc_hash::FxHashSet<NodeIndex>,
	participant_nodes: &rustc_hash::FxHashSet<NodeIndex>,
) -> Vec<Vec<usize>> {
	let mut visited = rustc_hash::FxHashSet::default();
	let mut components = Vec::new();
	for &start in active_nodes {
		if visited.contains(&start) {
			continue;
		}
		let mut frontier = vec![start];
		let mut mix_ids = rustc_hash::FxHashSet::default();
		while let Some(node) = frontier.pop() {
			if !visited.insert(node) {
				continue;
			}
			if let Some(mixture) = arena.get(node) {
				mix_ids.insert(mixture.mix);
			}
			for neighbor in arena.adjacent_node_ids(node) {
				if !active_nodes.contains(&neighbor)
					|| !solver_edge_enabled(arena, node, neighbor, participant_nodes)
				{
					continue;
				}
				if !visited.contains(&neighbor) {
					frontier.push(neighbor);
				}
			}
		}
		if !mix_ids.is_empty() {
			components.push(mix_ids.into_iter().collect());
		}
	}
	components
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
static TURF_CONSERVATION_REJECTIONS: AtomicU64 = AtomicU64::new(0);

/// A transaction is deliberately much smaller than an open station region.
/// This bounds snapshot age, topology-lock latency, and rejection scope while
/// still giving every selected physical edge both mutable endpoints.
// Large open compartments otherwise spend most of their recovery time paying
// selection/snapshot/publication overhead for 512-cell fragments. 2K remains a
// bounded shard (and an ~8 ms solver slice) while allowing one transaction to
// own a useful section of an SM-scale pressure front.
const MAX_MICROTRANSACTION_TURFS: usize = 2_048;
// Leave at least half of a bounded transaction available for the neighboring
// endpoints required by conservative edge updates. The adaptive controller may
// shrink this under load or grow it to 1K when the worker has headroom.
const MICROTRANSACTION_SEEDS: usize = MAX_MICROTRANSACTION_TURFS / 2;
const ATMOS_SIMULATION_STEP_MS: u64 = 100;

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
#[auxmacros::bind("/datum/controller/subsystem/air/proc/thread_running")]
fn thread_running_hook() -> Result<ByondValue> {
	Ok(TURF_PROCESS_RUNNING.load(Ordering::Acquire).into())
}

/// Returns: If this cycle is interrupted by overtiming or not. Calls all outstanding callbacks created by other processes, usually ones that can't run on other threads and only the main thread.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/finish_turf_processing_auxtools")]
fn finish_process_turfs(time_remaining: ByondValue) -> Result<ByondValue> {
	Ok(process_callbacks_for_millis(time_remaining.get_number()? as u64).into())
}
/// Returns: If this cycle is interrupted by overtiming or not. Starts a processing turfs cycle.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/process_turfs_auxtools")]
fn process_turf_hook(mut src: ByondValue, remaining: ByondValue) -> Result<ByondValue> {
	let _ = remaining;
	src.write_var_id(
		byond_string!("async_pressure_urgency"),
		&super::current_pressure_urgency_kpa().into(),
	)?;
	if TOPOLOGY_TRANSACTION_OPEN.load(Ordering::Acquire) {
		return Ok(true.into());
	}
	if TOPOLOGY_BATCH_OPEN.load(Ordering::Acquire) {
		return Ok(true.into());
	}
	if let Ok(result) = turf_result_channel().1.try_recv() {
		let previous_turf_cost = src.read_number_id(byond_string!("cost_turfs"))?;
		src.write_var_id(
			byond_string!("cost_turfs"),
			&(if previous_turf_cost == 0.0 {
				result.turf_cost_ms
			} else {
				0.8 * previous_turf_cost + 0.2 * result.turf_cost_ms
			})
			.into(),
		)?;
		let previous_post_cost = src.read_number_id(byond_string!("cost_post_process"))?;
		src.write_var_id(
			byond_string!("cost_post_process"),
			&(if previous_post_cost == 0.0 {
				result.post_process_cost_ms
			} else {
				0.8 * previous_post_cost + 0.2 * result.post_process_cost_ms
			})
			.into(),
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
			byond_string!("async_retained_temperature_turfs"),
			&(result.retained_temperature_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_retained_mole_turfs"),
			&(result.retained_mole_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_pending_turfs"),
			&(result.pending_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_pending_urgent_turfs"),
			&(result.pending_urgent_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_pending_fresh_turfs"),
			&(result.pending_fresh_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_pending_frontier_turfs"),
			&(result.pending_frontier_turfs as f32).into(),
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
		src.write_var_id(
			byond_string!("async_conservation_rejections"),
			&(result.conservation_rejections as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_closed_components"),
			&(result.closed_components as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_conservation_violation_components"),
			&(result.conservation_violation_components as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_conservation_worst_component_mixtures"),
			&(result.conservation_worst_component_mixtures as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_conservation_max_gas_delta"),
			&result.conservation_max_gas_delta.into(),
		)?;
		src.write_var_id(
			byond_string!("async_conservation_max_energy_delta"),
			&result.conservation_max_energy_delta.into(),
		)?;
		src.write_var_id(
			byond_string!("async_conservation_diagnostic"),
			&ByondValue::new_str(result.conservation_diagnostic.as_bytes().to_vec())?,
		)?;
		src.write_var_id(
			byond_string!("async_seed_limit"),
			&(result.seed_limit as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_selection_cost"),
			&result.selection_ms.into(),
		)?;
		src.write_var_id(
			byond_string!("async_snapshot_cost"),
			&result.snapshot_ms.into(),
		)?;
		src.write_var_id(byond_string!("async_fdm_cost"), &result.fdm_ms.into())?;
		src.write_var_id(
			byond_string!("async_equalize_cost"),
			&result.equalize_ms.into(),
		)?;
		src.write_var_id(
			byond_string!("async_publication_cost"),
			&result.publication_ms.into(),
		)?;
		src.write_var_id(
			byond_string!("async_semantic_events"),
			&(result.semantic_events as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_reaction_events"),
			&(result.reaction_events as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_overlay_events"),
			&(result.overlay_events as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("async_reaction_callback_cost"),
			&result.reaction_callback_ms.into(),
		)?;
		src.write_var_id(
			byond_string!("async_overlay_callback_cost"),
			&result.overlay_callback_ms.into(),
		)?;
		src.write_var_id(
			byond_string!("async_cancelled"),
			&(if result.cancelled { 1.0 } else { 0.0 }).into(),
		)?;
		src.write_var_id(
			byond_string!("async_pressure_urgency"),
			&result
				.pressure_urgency_kpa
				.max(super::current_pressure_urgency_kpa())
				.into(),
		)?;
		let previous_group_cost = src.read_number_id(byond_string!("cost_groups"))?;
		src.write_var_id(
			byond_string!("cost_groups"),
			&(if previous_group_cost == 0.0 {
				result.group_cost_ms
			} else {
				0.8 * previous_group_cost + 0.2 * result.group_cost_ms
			})
			.into(),
		)?;
		let previous_equalize_cost = src.read_number_id(byond_string!("cost_equalize"))?;
		src.write_var_id(
			byond_string!("cost_equalize"),
			&(if previous_equalize_cost == 0.0 {
				result.group_cost_ms
			} else {
				0.8 * previous_equalize_cost + 0.2 * result.group_cost_ms
			})
			.into(),
		)?;
		src.write_var_id(
			byond_string!("num_group_turfs_processed"),
			&(result.group_turfs as f32).into(),
		)?;
		src.write_var_id(
			byond_string!("num_equalize_processed"),
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
	let planet_share_ratio = src
		.read_number_id(byond_string!("planet_share_ratio"))
		.unwrap_or(GAS_DIFFUSION_CONSTANT);
	let request = TurfProcessRequest {
		fdm_max_steps,
		planet_share_ratio,
		// This is a latency bound for one independently publishable shard, not a
		// budget for the persistent worker as a whole.
		target_worker_ms: 8.0,
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
			let mut request = match turf_process_channel().1.recv() {
				Ok(request) => request,
				Err(_) => return,
			};
			// Keep the worker alive while there is atmospheric work. One sweep takes
			// the queue length observed at its start in bounded shards; retained
			// gradients wait for the next 100 ms epoch, while newly dirtied cells are
			// naturally included by the following sweep.
			while !TOPOLOGY_TRANSACTION_OPEN.load(Ordering::Acquire) {
				while let Ok(updated) = turf_process_channel().1.try_recv() {
					request = updated;
				}
				// Destructive world edits publish topology atomically. The generation
				// that was in flight when the batch opened is cancelled once; launching
				// more shards against the intentionally stale graph only discards work
				// and competes with explosion teardown.
				if TOPOLOGY_BATCH_OPEN.load(Ordering::Acquire) {
					std::thread::sleep(std::time::Duration::from_millis(1));
					continue;
				}
				let pending_at_start = super::pending_active_turfs();
				if pending_at_start == 0 {
					break;
				}
				let epoch_seed_limit = super::turf_seed_limit().min(MICROTRANSACTION_SEEDS);
				let sweep_transactions = pending_at_start.div_ceil(epoch_seed_limit).max(1);
				let epoch_start = std::time::Instant::now();
				let mut epoch_processed = rustc_hash::FxHashSet::default();
				for _ in 0..sweep_transactions {
					if TOPOLOGY_TRANSACTION_OPEN.load(Ordering::Acquire) {
						break;
					}
					let result = {
						let _task_lock = TASKS.read();
						apply_pending_topology_updates();
						std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
							process_turf(request, &mut snapshot, &mut epoch_processed)
						}))
						.unwrap_or_else(|panic| {
							TURF_REJECTED_GENERATIONS.fetch_add(1, Ordering::AcqRel);
							super::reactivate_cells(std::mem::take(
								&mut *PANIC_RETRY_TURFS.write(),
							));
							snapshot.release_values();
							let message = panic
								.downcast_ref::<&str>()
								.copied()
								.or_else(|| panic.downcast_ref::<String>().map(String::as_str))
								.unwrap_or("unknown panic");
							eprintln!(
								"auxmos turf worker rejected a panicked generation: {message}"
							);
							TurfProcessResult {
								generation: TURF_GENERATION.fetch_add(1, Ordering::AcqRel) + 1,
								rejected_generations: TURF_REJECTED_GENERATIONS
									.load(Ordering::Acquire),
								cancelled: true,
								..Default::default()
							}
						})
					};
					if result.seed_turfs == 0 {
						break;
					}
					if result.cancelled {
						super::abort_pressure_generation();
					} else {
						super::finish_pressure_generation();
					}
					// Telemetry is lossy by design. Publication already happened; keeping
					// only the newest result prevents a slow DM callback from throttling Rust.
					if let Err(flume::TrySendError::Full(result)) =
						turf_result_channel().0.try_send(result)
					{
						let _ = turf_result_channel().1.try_recv();
						let _ = turf_result_channel().0.try_send(result);
					}
				}
				if let Some(_topology_barrier) = TASKS.try_write() {
					apply_pending_topology_updates();
				}
				let elapsed = epoch_start.elapsed();
				let cadence = std::time::Duration::from_millis(ATMOS_SIMULATION_STEP_MS);
				if elapsed < cadence {
					std::thread::sleep(cadence - elapsed);
				}
			}
			TURF_PROCESS_RUNNING.store(false, Ordering::Release);
		}
	})
}

#[cfg_attr(feature = "tracy", tracing::instrument(skip_all))]
fn process_turf(
	request: TurfProcessRequest,
	snapshot: &mut MixtureSnapshot,
	epoch_processed: &mut rustc_hash::FxHashSet<CellHandle>,
) -> TurfProcessResult {
	let total_start = Instant::now();
	let pressure_urgency_kpa = super::begin_pressure_generation();
	let topology_generation = super::topology_generation();
	let seed_limit = super::turf_seed_limit();
	let selection_start = Instant::now();
	let (active_nodes, seed_turfs, boundary_handles) = with_turf_gases_read(|arena| {
		let seeds = take_active_turfs(
			arena,
			seed_limit.min(MICROTRANSACTION_SEEDS),
			epoch_processed,
		);
		let mut seed_count = 0;
		let mut nodes = rustc_hash::FxHashSet::default();
		let mut pressure_frontier = VecDeque::new();
		for handle in seeds {
			if nodes.len() >= MAX_MICROTRANSACTION_TURFS {
				super::reactivate_cells([handle]);
				continue;
			}
			if let Some(node) = arena.get_handle(handle) {
				if arena
					.get(node)
					.is_none_or(|mixture| mixture.is_immutable() || !mixture.enabled())
				{
					continue;
				}
				seed_count += 1;
				if nodes.insert(node) {
					pressure_frontier.push_back(node);
				}
				// Pairwise edge processing applies equal-and-opposite changes to each
				// mutable endpoint. Include exactly the opposite endpoints of seed
				// edges; recursively walking the graph would turn one local mutation
				// into a whole-station job.
				for neighbor in arena.adjacent_node_ids(node) {
					if nodes.len() >= MAX_MICROTRANSACTION_TURFS {
						break;
					}
					if arena
						.get(neighbor)
						.is_some_and(|mixture| !mixture.is_immutable() && mixture.enabled())
					{
						if nodes.insert(neighbor) && pressure_urgency_kpa >= 20.0 {
							pressure_frontier.push_back(neighbor);
						}
					}
				}
			}
		}
		// A pressure front is a connected physical event. Expand urgent work to a
		// bounded connected shard so a large room does not advance only one tile per
		// 100 ms epoch. The hard shard cap preserves latency and lets larger regions
		// continue as adjacent partitions on following transactions.
		if pressure_urgency_kpa >= 20.0 {
			while let Some(node) = pressure_frontier.pop_front() {
				if nodes.len() >= MAX_MICROTRANSACTION_TURFS {
					break;
				}
				for neighbor in arena.adjacent_node_ids(node) {
					if nodes.len() >= MAX_MICROTRANSACTION_TURFS {
						break;
					}
					if arena
						.get(neighbor)
						.is_some_and(|mixture| !mixture.is_immutable() && mixture.enabled())
						&& nodes.insert(neighbor)
					{
						pressure_frontier.push_back(neighbor);
					}
				}
			}
		}
		// Once any selected cell reaches vacuum, promote its entire connected
		// mutable region into this atomic transaction. Topology, not a sampled
		// global urgency scalar, owns this decision: that scalar can legitimately
		// fall between microtransactions while the reservoir remains pressurized.
		// The ordinary 2K shard cap remains in force for diffusion-only work;
		// decompression is exceptional because aperture/volume flow is only
		// physically meaningful for a complete reservoir.
		let vacuum_apertures = selected_vacuum_apertures(arena, &nodes);
		for aperture in vacuum_apertures {
			nodes.extend(connected_mutable_region(arena, aperture));
		}
		for &node in &nodes {
			if let Some(mixture) = arena.get(node) {
				epoch_processed.insert(mixture.handle());
			}
		}
		// A transaction shard is only a scheduling boundary, never a physical
		// boundary. Persist every mutable edge crossing the shard as frontier work.
		// This is the liveness invariant that prevents a >512-cell room from going
		// to sleep with an unprocessed gradient beyond the selected shard.
		let boundary = nodes
			.iter()
			.flat_map(|&node| arena.adjacent_node_ids(node))
			.filter(|neighbor| !nodes.contains(neighbor))
			.filter_map(|neighbor| arena.get(neighbor))
			.filter(|mixture| mixture.enabled() && !mixture.is_immutable())
			.map(TurfMixture::handle)
			.collect::<rustc_hash::FxHashSet<_>>();
		*PANIC_RETRY_TURFS.write() = nodes
			.iter()
			.filter_map(|&node| arena.get(node).map(TurfMixture::handle))
			.chain(boundary.iter().copied())
			.collect();
		(nodes, seed_count, boundary)
	});
	let selection_ms = selection_start.elapsed().as_micros() as f32 / 1_000.0;
	if active_nodes.is_empty() {
		return TurfProcessResult {
			generation: TURF_GENERATION.fetch_add(1, Ordering::AcqRel) + 1,
			total_cost_ms: total_start.elapsed().as_micros() as f32 / 1_000.0,
			rejected_generations: TURF_REJECTED_GENERATIONS.load(Ordering::Acquire),
			..Default::default()
		};
	}
	// The arena has a single authoritative writer. Synchronous DM/machinery gas
	// changes queue briefly behind this bounded shard, so the snapshot can always
	// publish atomically instead of repeatedly losing work to revision races.
	let single_writer = GasArena::begin_solver_transaction();
	let snapshot_mix_ids = with_turf_gases_read(|arena| {
		let mut ids = rustc_hash::FxHashSet::default();
		for &node in &active_nodes {
			if let Some(mixture) = arena.get(node) {
				ids.insert(mixture.mix);
			}
			ids.extend(
				arena
					.adjacent_node_ids(node)
					.filter_map(|adjacent| arena.get(adjacent))
					.map(|mixture| mixture.mix),
			);
		}
		ids.into_iter().collect::<Vec<_>>()
	});
	let snapshot_start = Instant::now();
	GasArena::snapshot_mixtures_into(&snapshot_mix_ids, snapshot);
	let snapshot_ms = snapshot_start.elapsed().as_micros() as f32 / 1_000.0;
	if super::topology_generation() != topology_generation {
		super::reactivate_cells(std::mem::take(&mut *PANIC_RETRY_TURFS.write()));
		snapshot.release_values();
		return TurfProcessResult {
			generation: TURF_GENERATION.fetch_add(1, Ordering::AcqRel) + 1,
			total_cost_ms: total_start.elapsed().as_micros() as f32 / 1_000.0,
			seed_turfs,
			seed_limit,
			selection_ms,
			snapshot_ms,
			cancelled: true,
			pressure_urgency_kpa,
			..Default::default()
		};
	}
	let transaction_components =
		with_turf_gases_read(|arena| transaction_components(arena, &active_nodes, &active_nodes));
	let closed_components = with_turf_gases_read(|arena| {
		closed_component_mixtures(arena, &active_nodes, &active_nodes)
	});
	let conservation_baselines = closed_components
		.iter()
		.map(|component| conservation_signature(component, snapshot))
		.collect::<Vec<_>>();
	//this will block until process_turfs is called
	let (
		low_pressure_turfs,
		high_pressure_turfs,
		pressure_events,
		measured_pressure_urgency,
		turf_cost_ms,
	) = {
		let start_time = Instant::now();
		let fdm_budget = Duration::from_millis(request.target_worker_ms.max(2.0) as u64);
		let (low_pressure_turfs, high_pressure_turfs, pressure_events, measured_pressure_urgency) =
			fdm(
				(&start_time, fdm_budget),
				if pressure_urgency_kpa >= 20.0 {
					request.fdm_max_steps.max(12)
				} else {
					request.fdm_max_steps
				},
				true,
				snapshot,
				&active_nodes,
			);
		let bench = start_time.elapsed().as_micros() as f32 / 1_000.0;
		(
			low_pressure_turfs,
			high_pressure_turfs,
			pressure_events,
			measured_pressure_urgency,
			bench,
		)
	};
	if super::topology_generation() != topology_generation {
		super::reactivate_cells(std::mem::take(&mut *PANIC_RETRY_TURFS.write()));
		snapshot.release_values();
		let elapsed = total_start.elapsed().as_micros() as f32 / 1_000.0;
		super::adapt_turf_seed_limit(elapsed, request.target_worker_ms);
		return TurfProcessResult {
			generation: TURF_GENERATION.fetch_add(1, Ordering::AcqRel) + 1,
			total_cost_ms: elapsed,
			seed_turfs,
			seed_limit,
			selection_ms,
			snapshot_ms,
			cancelled: true,
			pressure_urgency_kpa,
			..Default::default()
		};
	}
	planet_process(request.planet_share_ratio, snapshot, &active_nodes);
	// High-pressure equalization is part of the same private-snapshot FDM
	// transaction. The former katmos tail pass mutated the authoritative arena
	// after publication and could block synchronous DM gas reads for hundreds of
	// milliseconds. One solver, one conservation check, one publication removes
	// that contention and the intermediate state entirely.
	let (group_turfs, group_cost_ms) = (high_pressure_turfs.len(), 0.0);
	for (component, baseline) in closed_components.iter().zip(&conservation_baselines) {
		project_closed_conservation(component, baseline, snapshot);
	}
	let conservation_violations = closed_components
		.iter()
		.zip(&conservation_baselines)
		.filter_map(|(component, before)| {
			conservation_violation(
				component,
				before,
				&conservation_signature(component, snapshot),
			)
		})
		.collect::<Vec<_>>();
	let conservation_diagnostic = format_conservation_violations(&conservation_violations);
	if !conservation_violations.is_empty() {
		TURF_CONSERVATION_REJECTIONS.fetch_add(1, Ordering::AcqRel);
		report_conservation_violations(&conservation_violations, &conservation_diagnostic);
	}
	let conservation_worst_component_mixtures = conservation_violations
		.iter()
		.map(|violation| violation.component_size)
		.max()
		.unwrap_or_default();
	let conservation_max_gas_delta = conservation_violations
		.iter()
		.flat_map(|violation| violation.gas_deltas.iter())
		.map(|entry| entry.3.abs() as f32)
		.fold(0.0_f32, f32::max);
	let conservation_max_energy_delta = conservation_violations
		.iter()
		.map(|violation| (violation.energy_after - violation.energy_before).abs() as f32)
		.fold(0.0_f32, f32::max);
	let next_active = with_turf_gases_read(|arena| {
		active_nodes
			.par_iter()
			.filter(|&&node| {
				arena
					.get(node)
					.is_some_and(|mixture| should_process(node, mixture, snapshot, arena))
			})
			.filter_map(|&node| arena.get(node).map(TurfMixture::handle))
			.collect::<rustc_hash::FxHashSet<_>>()
	});
	let pending_boundary = with_turf_gases_read(|arena| {
		boundary_handles
			.iter()
			.copied()
			.filter(|handle| {
				arena
					.get_handle(*handle)
					.and_then(|node| arena.get(node).map(|mixture| (node, mixture)))
					.is_some_and(|(node, mixture)| should_process(node, mixture, snapshot, arena))
			})
			.collect::<Vec<_>>()
	});
	// Conservation is a test-failing invariant and a production error signal,
	// not a publication gate. Rejecting a generation here permanently freezes
	// diffusion by requeueing the same cells without ever applying progress.
	let publication_start = Instant::now();
	let publication = if super::topology_generation() == topology_generation {
		GasArena::publish_snapshot_components(&transaction_components, snapshot)
	} else {
		crate::gas::SnapshotPublication {
			changed: Vec::new(),
			published: rustc_hash::FxHashSet::default(),
			rejected: transaction_components.iter().flatten().copied().collect(),
		}
	};
	let publication_ms = publication_start.elapsed().as_micros() as f32 / 1_000.0;
	drop(single_writer);
	let had_rejection = !publication.rejected.is_empty();
	if had_rejection {
		TURF_REJECTED_GENERATIONS.fetch_add(1, Ordering::AcqRel);
		// Retry only rejected components. Concurrent writes already promote their
		// exact cells to the fresh queue; this frontier retry preserves the other
		// endpoints needed for a conservative pairwise transfer.
		super::reactivate_cells(with_turf_gases_read(|arena| {
			active_nodes
				.iter()
				.filter_map(|&node| {
					let mixture = arena.get(node)?;
					publication
						.rejected
						.contains(&mixture.mix)
						.then(|| mixture.handle())
				})
				.collect::<Vec<_>>()
		}));
	}
	// Cross-shard edges with a material residual remain explicitly pending.
	// Settled boundary edges are omitted so large stable rooms still reach zero work.
	super::reactivate_cells(pending_boundary.iter().copied());
	let published_nodes = with_turf_gases_read(|arena| {
		active_nodes
			.iter()
			.copied()
			.filter(|&node| {
				arena
					.get(node)
					.is_some_and(|mixture| publication.published.contains(&mixture.mix))
			})
			.collect::<rustc_hash::FxHashSet<_>>()
	});
	let retained_handles = with_turf_gases_read(|arena| {
		next_active
			.into_iter()
			.filter(|handle| {
				arena
					.get_handle(*handle)
					.and_then(|node| arena.get(node))
					.is_some_and(|mixture| publication.published.contains(&mixture.mix))
			})
			.collect::<Vec<_>>()
	});
	let retained_turfs = retained_handles.len();
	let (retained_temperature_turfs, retained_mole_turfs) = with_turf_gases_read(|arena| {
		retained_handles
			.iter()
			.fold((0, 0), |(temperature, moles), handle| {
				let Some(node) = arena.get_handle(*handle) else {
					return (temperature, moles);
				};
				let Some(mixture) = arena.get(node) else {
					return (temperature, moles);
				};
				let (temperature_residual, mole_residual) =
					process_reasons(node, mixture, snapshot, arena);
				(
					temperature + usize::from(temperature_residual),
					moles + usize::from(mole_residual),
				)
			})
	});
	let retained_set = retained_handles
		.iter()
		.copied()
		.collect::<rustc_hash::FxHashSet<_>>();
	super::reactivate_cells(retained_handles);
	// Solver-discovered gradients must drive both the priority queue and SSair's
	// 10 Hz cadence; relying only on synchronous writes starves blast-created work.
	// A breached compartment must retain queue priority until it is genuinely
	// near vacuum. Dropping it back into the routine frontier at 20 kPa lets a
	// large post-explosion backlog delay each subsequent aperture transaction by
	// seconds, making a small one-face room appear frozen despite correct flux.
	// This changes scheduling only; aperture/volume physics remain unchanged.
	if measured_pressure_urgency > 5.0 {
		super::reactivate_urgent_cells(
			with_turf_gases_read(|arena| {
				high_pressure_turfs
					.iter()
					.filter_map(|id| arena.get_from_id(*id).map(TurfMixture::handle))
					.filter(|handle| retained_set.contains(handle))
					.collect::<Vec<_>>()
			}),
			measured_pressure_urgency,
		);
		super::reactivate_urgent_cells(pending_boundary.iter().copied(), measured_pressure_urgency);
	}
	PANIC_RETRY_TURFS.write().clear();
	let (post_process_cost_ms, semantic_events, reaction_events, overlay_events) = {
		let start_time = Instant::now();
		let event_counts = if !published_nodes.is_empty() {
			post_process(&published_nodes)
		} else {
			(0, 0, 0)
		};
		(
			start_time.elapsed().as_micros() as f32 / 1_000.0,
			event_counts.0,
			event_counts.1,
			event_counts.2,
		)
	};
	let (published_low_pressure_turfs, published_high_pressure_turfs) =
		with_turf_gases_read(|arena| {
			let filter = |ids: &BTreeSet<TurfID>| {
				ids.iter()
					.copied()
					.filter(|id| {
						arena
							.get_from_id(*id)
							.is_some_and(|mixture| publication.published.contains(&mixture.mix))
					})
					.collect::<BTreeSet<_>>()
			};
			(filter(&low_pressure_turfs), filter(&high_pressure_turfs))
		});
	if !published_nodes.is_empty() {
		let published_handles = with_turf_gases_read(|arena| {
			published_nodes
				.iter()
				.filter_map(|&node| arena.get(node).map(TurfMixture::handle))
				.collect::<rustc_hash::FxHashSet<_>>()
		});
		dispatch_pressure_events(
			pressure_events
				.into_iter()
				.filter(|(handle, _)| published_handles.contains(handle))
				.collect(),
		);
	}
	// The snapshot vector stays indexed by arena ID, but completed mixtures must
	// not retain their heap-backed gas arrays. The first generation snapshots the
	// whole station; keeping those clones would permanently duplicate the gas arena
	// even after the active frontier shrinks to a few hundred mixtures.
	snapshot.release_values();
	let total_cost_ms = total_start.elapsed().as_micros() as f32 / 1_000.0;
	let reaction_callback_ms = REACTION_CALLBACK_MICROS.swap(0, Ordering::AcqRel) as f32 / 1_000.0;
	let overlay_callback_ms = OVERLAY_CALLBACK_MICROS.swap(0, Ordering::AcqRel) as f32 / 1_000.0;
	super::adapt_turf_seed_limit(total_cost_ms, request.target_worker_ms);
	let (pending_urgent_turfs, pending_fresh_turfs, pending_frontier_turfs) =
		super::pending_active_turf_queue_counts();
	TurfProcessResult {
		generation: TURF_GENERATION.fetch_add(1, Ordering::AcqRel) + 1,
		turf_cost_ms,
		post_process_cost_ms,
		total_cost_ms,
		low_pressure_turfs: published_low_pressure_turfs.len(),
		high_pressure_turfs: published_high_pressure_turfs.len(),
		active_turfs: active_nodes.len(),
		seed_turfs,
		retained_turfs,
		retained_temperature_turfs,
		retained_mole_turfs,
		pending_turfs: super::pending_active_turfs(),
		pending_urgent_turfs,
		pending_fresh_turfs,
		pending_frontier_turfs,
		snapshot_mixtures: snapshot_mix_ids.len(),
		published_mixtures: publication.changed.len(),
		rejected_generations: TURF_REJECTED_GENERATIONS.load(Ordering::Acquire),
		conservation_rejections: TURF_CONSERVATION_REJECTIONS.load(Ordering::Acquire),
		closed_components: closed_components.len(),
		conservation_violation_components: conservation_violations.len(),
		conservation_worst_component_mixtures,
		conservation_max_gas_delta,
		conservation_max_energy_delta,
		conservation_diagnostic,
		group_cost_ms,
		group_turfs,
		seed_limit,
		selection_ms,
		snapshot_ms,
		fdm_ms: turf_cost_ms,
		equalize_ms: group_cost_ms,
		publication_ms,
		semantic_events,
		reaction_events,
		overlay_events,
		reaction_callback_ms,
		overlay_callback_ms,
		cancelled: false,
		pressure_urgency_kpa: pressure_urgency_kpa.max(measured_pressure_urgency),
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
	let (temperature, moles) = process_reasons(index, mixture, all_mixtures, arena);
	temperature || moles
}

fn process_reasons(
	index: NodeIndex,
	mixture: &TurfMixture,
	all_mixtures: &MixtureSnapshot,
	arena: &TurfGases,
) -> (bool, bool) {
	if !mixture.enabled() || arena.adjacent_node_ids(index).next().is_none() {
		return (false, false);
	}
	let Some(gas) = all_mixtures.get(mixture.mix).and_then(RwLock::try_read) else {
		return (false, false);
	};
	let mut temperature = false;
	let mut moles = false;
	for entry in arena.adjacent_mixes(index, all_mixtures) {
		let Some(mix) = entry.try_read() else {
			return (false, false);
		};
		temperature |= gas.temperature_compare(&mix);
		moles |= gas.compare_with(&mix, MINIMUM_MOLES_DELTA_TO_MOVE);
	}
	(temperature, moles)
	/*
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
	*/
}

#[derive(Clone, Debug)]
struct ConservedCellState {
	moles: Vec<f64>,
	energy: f64,
	pressure: f32,
	volume: f64,
}

#[derive(Clone, Debug)]
enum ConservativeEdgeTarget {
	Mutable(usize),
	External {
		moles: Vec<f64>,
		energy: f64,
		handle: CellHandle,
		vacuum: bool,
	},
}

#[derive(Clone, Debug)]
struct ConservativeEdge {
	a: usize,
	target: ConservativeEdgeTarget,
}

/// Conductance of one fully open turf face per 100 ms physical step. The
/// exponential mass-flow equation handles arbitrary aperture counts without an
/// artificial gameplay cap; this coefficient controls the calibrated rate.
const EXPLOSIVE_DECOMPRESSION_FACE_CONDUCTANCE: f64 = 0.35;
const STANDARD_TURF_VOLUME: f64 = 2500.0;

fn explosive_decompression_fraction(total_volume: f64, vacuum_faces: usize, pressure: f64) -> f64 {
	if total_volume <= 0.0 || vacuum_faces == 0 {
		return 0.0;
	}
	let pressure_factor = (pressure / 101.325).max(0.05).sqrt();
	let aperture_volume =
		vacuum_faces as f64 * STANDARD_TURF_VOLUME * EXPLOSIVE_DECOMPRESSION_FACE_CONDUCTANCE;
	(1.0 - (-aperture_volume * pressure_factor / total_volume).exp()).clamp(0.0, 0.99)
}

/// Build a deterministic list of undirected physical faces. Mutable/mutable
/// faces occur exactly once and always update both endpoints. Immutable faces
/// are explicit external reservoirs (normally space) and therefore have a
/// measurable mass/energy ledger rather than an unmatched half-transfer.
fn conservative_solver_inputs(
	all_mixtures: &MixtureSnapshot,
	active_nodes: &rustc_hash::FxHashSet<NodeIndex>,
) -> (
	Vec<NodeIndex>,
	Vec<CellHandle>,
	Vec<ConservedCellState>,
	Vec<ConservativeEdge>,
) {
	with_turf_gases_read(|arena| {
		let mut nodes = active_nodes.iter().copied().collect::<Vec<_>>();
		nodes.sort_unstable_by_key(|node| node.index());
		let slots = nodes
			.iter()
			.copied()
			.enumerate()
			.map(|(slot, node)| (node, slot))
			.collect::<rustc_hash::FxHashMap<_, _>>();
		let mut handles = Vec::with_capacity(nodes.len());
		let mut states = Vec::with_capacity(nodes.len());
		for &node in &nodes {
			let mixture = arena
				.get(node)
				.expect("active turf disappeared while topology was stable");
			let gas = all_mixtures
				.get(mixture.mix)
				.expect("active turf gas was omitted from the transaction snapshot")
				.read();
			handles.push(mixture.handle());
			states.push(ConservedCellState {
				moles: gas.composition_moles().into_iter().map(f64::from).collect(),
				energy: f64::from(gas.thermal_energy()),
				pressure: gas.return_pressure(),
				volume: f64::from(gas.volume),
			});
		}

		let mut edges = Vec::new();
		for (a, &node) in nodes.iter().enumerate() {
			for neighbor in arena.adjacent_node_ids(node) {
				if !solver_edge_enabled(arena, node, neighbor, active_nodes) {
					continue;
				}
				let Some(neighbor_mixture) = arena.get(neighbor) else {
					continue;
				};
				if neighbor_mixture.is_immutable() {
					let Some(gas) = all_mixtures
						.get(neighbor_mixture.mix)
						.and_then(RwLock::try_read)
					else {
						continue;
					};
					edges.push(ConservativeEdge {
						a,
						target: ConservativeEdgeTarget::External {
							moles: gas.composition_moles().into_iter().map(f64::from).collect(),
							energy: f64::from(gas.thermal_energy()),
							handle: neighbor_mixture.handle(),
							vacuum: gas.return_pressure() < 1.0,
						},
					});
				} else if let Some(&b) = slots.get(&neighbor) {
					if a < b {
						edges.push(ConservativeEdge {
							a,
							target: ConservativeEdgeTarget::Mutable(b),
						});
					}
				}
			}
		}

		let gas_count = states
			.iter()
			.map(|state| state.moles.len())
			.chain(edges.iter().filter_map(|edge| match &edge.target {
				ConservativeEdgeTarget::External { moles, .. } => Some(moles.len()),
				ConservativeEdgeTarget::Mutable(_) => None,
			}))
			.max()
			.unwrap_or_default();
		for state in &mut states {
			state.moles.resize(gas_count, 0.0);
		}
		for edge in &mut edges {
			if let ConservativeEdgeTarget::External { moles, .. } = &mut edge.target {
				moles.resize(gas_count, 0.0);
			}
		}
		(nodes, handles, states, edges)
	})
}

/// Solving diffusion as a conservative edge-flux transaction. Each physical
/// face is evaluated from one immutable substep state and contributes equal and
/// opposite f64 mole/energy deltas. This removes the cell-order dependence,
/// partial-stencil pressure sawtooth, and repeated f32 temperature reconstruction
/// of the former neighbor-merge implementation.
#[cfg_attr(not(target_feature = "avx2"), auxmacros::generate_simd_functions)]
#[cfg_attr(feature = "tracy", tracing::instrument(skip_all))]
fn fdm(
	(start_time, remaining_time): (&Instant, Duration),
	fdm_max_steps: i32,
	explosive_decompression: bool,
	all_mixtures: &MixtureSnapshot,
	active_nodes: &rustc_hash::FxHashSet<NodeIndex>,
) -> (
	BTreeSet<TurfID>,
	BTreeSet<TurfID>,
	Vec<(CellHandle, TinyVec<[(CellHandle, f32); 6]>)>,
	f32,
) {
	let mut low_pressure_turfs: BTreeSet<TurfID> = Default::default();
	let mut high_pressure_turfs: BTreeSet<TurfID> = Default::default();
	let mut pressure_events: rustc_hash::FxHashMap<CellHandle, TinyVec<[(CellHandle, f32); 6]>> =
		Default::default();
	let mut measured_pressure_urgency = 0.0_f32;
	let (nodes, handles, mut states, edges) =
		conservative_solver_inputs(all_mixtures, active_nodes);
	if states.is_empty() {
		return (low_pressure_turfs, high_pressure_turfs, Vec::new(), 0.0);
	}
	let gas_count = states.first().map_or(0, |state| state.moles.len());
	let mut decompressed = vec![false; states.len()];

	// Port the useful part of Auxmos MonsterMOS explosive decompression into the
	// detached transaction: flood from immutable vacuum faces, establish a path
	// toward space for pressure movement, and evacuate a bounded fraction of that
	// connected mutable component each 10 Hz generation. No BYOND call or
	// authoritative arena mutation occurs on the worker thread.
	if explosive_decompression {
		let mut vacuum_faces = vec![0_usize; states.len()];
		let mut target = vec![None; states.len()];
		let mut mutable_adjacency = vec![Vec::new(); states.len()];
		for edge in &edges {
			match &edge.target {
				ConservativeEdgeTarget::Mutable(b) => {
					mutable_adjacency[edge.a].push(*b);
					mutable_adjacency[*b].push(edge.a);
				}
				ConservativeEdgeTarget::External { handle, vacuum, .. } => {
					if !vacuum {
						continue;
					}
					vacuum_faces[edge.a] += 1;
					decompressed[edge.a] = true;
					target[edge.a] = Some(*handle);
				}
			}
		}
		// A connected room behaves as one compressible reservoir during explosive
		// decompression. Applying outflow only to aperture tiles creates artificial
		// high-pressure islands whose evacuation speed depends on graph distance and
		// shard order. Flood the transaction's physical component, derive one flow
		// fraction from its total volume and aperture count, and remove that same
		// fraction from every member. Composition and temperature are preserved and
		// aperture area still controls the total mass loss.
		let mut visited = vec![false; states.len()];
		for start in 0..states.len() {
			if visited[start] {
				continue;
			}
			let mut stack = vec![start];
			let mut component = Vec::new();
			let mut component_faces = 0_usize;
			let mut component_volume = 0.0_f64;
			let mut pressure_volume = 0.0_f64;
			visited[start] = true;
			while let Some(slot) = stack.pop() {
				component.push(slot);
				component_faces += vacuum_faces[slot];
				component_volume += states[slot].volume;
				pressure_volume += f64::from(states[slot].pressure) * states[slot].volume;
				for &neighbor in &mutable_adjacency[slot] {
					if !visited[neighbor] {
						visited[neighbor] = true;
						stack.push(neighbor);
					}
				}
			}
			if component_faces == 0 || component_volume <= 0.0 {
				continue;
			}
			let component_pressure = pressure_volume / component_volume;
			let fraction = explosive_decompression_fraction(
				component_volume,
				component_faces,
				component_pressure,
			);
			measured_pressure_urgency = measured_pressure_urgency.max(component_pressure as f32);
			for slot in component {
				decompressed[slot] = true;
				high_pressure_turfs.insert(handles[slot].id);
				if vacuum_faces[slot] > 0 {
					if let Some(target_handle) = target[slot] {
						pressure_events
							.entry(handles[slot])
							.or_default()
							.push((target_handle, states[slot].pressure * fraction as f32));
					}
				}
				for amount in &mut states[slot].moles {
					*amount *= 1.0 - fraction;
				}
				states[slot].energy *= 1.0 - fraction;
			}
		}
	}

	let coefficient = f64::from(GAS_DIFFUSION_CONSTANT);
	let mut mole_deltas = vec![0.0_f64; states.len().saturating_mul(gas_count)];
	let mut energy_deltas = vec![0.0_f64; states.len()];
	let mut cur_count = 0;
	while cur_count < fdm_max_steps && start_time.elapsed() < remaining_time {
		mole_deltas.fill(0.0);
		energy_deltas.fill(0.0);
		let mut did_work = false;
		for edge in &edges {
			match &edge.target {
				ConservativeEdgeTarget::Mutable(b) => {
					did_work = true;
					let raw_pressure_diff = states[edge.a].pressure - states[*b].pressure;
					let moved_pressure = raw_pressure_diff * GAS_DIFFUSION_CONSTANT;
					measured_pressure_urgency =
						measured_pressure_urgency.max(raw_pressure_diff.abs());
					if cur_count == 0 {
						pressure_events
							.entry(handles[edge.a])
							.or_default()
							.push((handles[*b], moved_pressure));
					}
					if moved_pressure.abs() > 5.0 {
						high_pressure_turfs.insert(handles[edge.a].id);
						high_pressure_turfs.insert(handles[*b].id);
					} else {
						low_pressure_turfs.insert(handles[edge.a].id);
						low_pressure_turfs.insert(handles[*b].id);
					}
					for gas in 0..gas_count {
						let flux =
							coefficient * (states[*b].moles[gas] - states[edge.a].moles[gas]);
						mole_deltas[edge.a * gas_count + gas] += flux;
						mole_deltas[*b * gas_count + gas] -= flux;
					}
					let energy_flux = coefficient * (states[*b].energy - states[edge.a].energy);
					energy_deltas[edge.a] += energy_flux;
					energy_deltas[*b] -= energy_flux;
				}
				ConservativeEdgeTarget::External {
					moles,
					energy,
					handle,
					..
				} => {
					did_work = true;
					let raw_pressure_diff = states[edge.a].pressure;
					let moved_pressure = raw_pressure_diff * GAS_DIFFUSION_CONSTANT;
					measured_pressure_urgency = measured_pressure_urgency.max(raw_pressure_diff);
					if cur_count == 0 {
						pressure_events
							.entry(handles[edge.a])
							.or_default()
							.push((*handle, moved_pressure));
					}
					high_pressure_turfs.insert(handles[edge.a].id);
					for gas in 0..gas_count {
						mole_deltas[edge.a * gas_count + gas] +=
							coefficient * (moles[gas] - states[edge.a].moles[gas]);
					}
					energy_deltas[edge.a] += coefficient * (*energy - states[edge.a].energy);
				}
			}
		}
		if !did_work {
			break;
		}
		for (slot, state) in states.iter_mut().enumerate() {
			for gas in 0..gas_count {
				state.moles[gas] =
					(state.moles[gas] + mole_deltas[slot * gas_count + gas]).max(0.0);
			}
			state.energy = (state.energy + energy_deltas[slot]).max(0.0);
		}
		cur_count += 1;
	}

	with_turf_gases_read(|arena| {
		for (slot, &node) in nodes.iter().enumerate() {
			let Some(turf_mix) = arena.get(node) else {
				continue;
			};
			if let Some(entry) = all_mixtures.get(turf_mix.mix) {
				entry
					.write()
					.replace_conserved(&states[slot].moles, states[slot].energy);
			}
		}
	});
	(
		low_pressure_turfs,
		high_pressure_turfs,
		pressure_events.into_iter().collect(),
		measured_pressure_urgency,
	)
}

fn dispatch_pressure_events(events: Vec<(CellHandle, TinyVec<[(CellHandle, f32); 6]>)>) {
	events.into_par_iter().for_each(|(handle, diffs)| {
		let sender = byond_callback_sender();
		drop(sender.try_send(Box::new(move || {
			if !with_turf_gases_read(|arena| arena.get_handle(handle).is_some()) {
				return Ok(());
			}
			let turf = ByondValue::new_ref(ValueType::Turf, handle.id);
			for (other_handle, diff) in diffs.iter().copied() {
				if other_handle.id == 0
					|| !with_turf_gases_read(|arena| arena.get_handle(other_handle).is_some())
				{
					continue;
				}
				let other_turf = ByondValue::new_ref(ValueType::Turf, other_handle.id);
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

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn decompression_scales_with_aperture_and_compartment_volume() {
		let closet = explosive_decompression_fraction(9.0 * STANDARD_TURF_VOLUME, 1, 101.325);
		let hangar = explosive_decompression_fraction(100.0 * STANDARD_TURF_VOLUME, 1, 101.325);
		let breached_hangar =
			explosive_decompression_fraction(100.0 * STANDARD_TURF_VOLUME, 4, 101.325);
		assert!(closet > hangar * 5.0);
		assert!(breached_hangar > hangar * 3.0);
		assert!(closet < 1.0 && breached_hangar < 1.0);
	}

	#[test]
	fn decompression_pressure_increases_flow_without_atomic_emptying() {
		let normal = explosive_decompression_fraction(25.0 * STANDARD_TURF_VOLUME, 1, 101.325);
		let high = explosive_decompression_fraction(25.0 * STANDARD_TURF_VOLUME, 1, 1013.25);
		assert!(high > normal);
		assert!(high <= 0.99);
		assert_eq!(explosive_decompression_fraction(0.0, 1, 101.325), 0.0);
		assert_eq!(
			explosive_decompression_fraction(STANDARD_TURF_VOLUME, 0, 101.325),
			0.0
		);
	}

	#[test]
	fn publication_components_match_the_solver_edge_transaction() {
		let mut arena = TurfGases {
			graph: StableDiGraph::default(),
			map: IndexMap::default(),
			generations: FxHashMap::default(),
		};
		for id in 1..=4 {
			arena.insert_turf(TurfMixture {
				mix: (id - 1) as usize,
				id,
				flags: SimulationFlags::SIMULATION_ALL,
				..Default::default()
			});
		}
		arena.link(1, 2);
		arena.link(2, 1);
		arena.link(2, 3);
		arena.link(3, 2);
		arena.link(3, 4);
		arena.link(4, 3);
		let active_nodes = (1..=4)
			.map(|id| arena.get_id(id).unwrap())
			.collect::<rustc_hash::FxHashSet<_>>();
		let mut components = transaction_components(&arena, &active_nodes, &active_nodes)
			.into_iter()
			.map(|component| component.into_iter().collect::<BTreeSet<_>>())
			.collect::<Vec<_>>();
		components.sort();
		assert_eq!(components, vec![BTreeSet::from([0, 1, 2, 3])]);
	}

	#[test]
	fn decompression_region_is_not_limited_to_solver_shard_size() {
		let mut arena = TurfGases {
			graph: StableDiGraph::default(),
			map: IndexMap::default(),
			generations: FxHashMap::default(),
		};
		let region_size = MAX_MICROTRANSACTION_TURFS + 257;
		for id in 1..=region_size as u32 {
			arena.insert_turf(TurfMixture {
				mix: (id - 1) as usize,
				id,
				flags: SimulationFlags::SIMULATION_ALL,
				..Default::default()
			});
		}
		for id in 1..=region_size as u32 {
			let mut adjacent = Vec::with_capacity(2);
			if id > 1 {
				adjacent.push((id - 1, 0));
			}
			if id < region_size as u32 {
				adjacent.push((id + 1, 0));
			}
			for (other, _) in adjacent {
				arena.link(id, other);
			}
		}
		let start = arena.get_id(1).unwrap();
		let region = connected_mutable_region(&arena, start);
		assert_eq!(region.len(), region_size);
	}

	#[test]
	fn decompression_region_stops_at_non_simulating_boundary() {
		let mut arena = TurfGases {
			graph: StableDiGraph::default(),
			map: IndexMap::default(),
			generations: FxHashMap::default(),
		};
		for id in 1..=3 {
			arena.insert_turf(TurfMixture {
				mix: (id - 1) as usize,
				id,
				flags: if id == 2 {
					SimulationFlags::empty()
				} else {
					SimulationFlags::SIMULATION_ALL
				},
				..Default::default()
			});
		}
		arena.link(1, 2);
		arena.link(2, 1);
		arena.link(2, 3);
		arena.link(3, 2);
		let region = connected_mutable_region(&arena, arena.get_id(1).unwrap());
		assert_eq!(region.len(), 1);
	}

	#[test]
	fn conservation_gate_rejects_material_loss() {
		let mut before = ConservationSignature::default();
		before.gases.insert(0, 440.0);
		before.gases.insert(1, 1_650.0);
		before.energy = 50_000.0;
		let mut after = ConservationSignature::default();
		after.gases.insert(0, 123.0);
		after.gases.insert(1, 459.0);
		after.energy = 16_000.0;
		assert!(!conserves(&before, &after));
	}

	#[test]
	fn conservation_gate_allows_float_noise() {
		let mut before = ConservationSignature::default();
		before.gases.insert(0, 440.0);
		before.energy = 50_000.0;
		let mut after = ConservationSignature::default();
		after.gases.insert(0, 440.000_4);
		after.energy = 50_000.4;
		assert!(conserves(&before, &after));
	}

	#[test]
	fn conservation_gate_rejects_substantive_fractional_loss() {
		let mut before = ConservationSignature::default();
		before.gases.insert(0, 1_000.0);
		before.energy = 1_000_000.0;
		let mut after = ConservationSignature::default();
		after.gases.insert(0, 995.0);
		after.energy = 995_000.0;
		assert!(!conserves(&before, &after));
	}

	#[test]
	fn conservation_gate_detects_created_gas() {
		let before = ConservationSignature::default();
		let mut after = ConservationSignature::default();
		after.gases.insert(7, 10.0);
		assert!(!conserves(&before, &after));
	}

	#[test]
	fn shared_mixtures_coalesce_node_components() {
		let mut components = coalesce_overlapping_mixture_components(vec![
			vec![1, 2, 2],
			vec![3, 4],
			vec![2, 3],
			vec![8],
		]);
		for component in &mut components {
			component.sort_unstable();
		}
		components.sort();
		assert_eq!(components, vec![vec![1, 2, 3, 4], vec![8]]);
	}

	#[test]
	fn disabled_mutable_neighbor_is_not_a_solver_edge() {
		let mut arena = TurfGases {
			graph: StableDiGraph::default(),
			map: IndexMap::default(),
			generations: FxHashMap::default(),
		};
		arena.insert_turf(TurfMixture {
			mix: 0,
			id: 1,
			flags: SimulationFlags::SIMULATION_ALL,
			..Default::default()
		});
		arena.insert_turf(TurfMixture {
			mix: 1,
			id: 2,
			flags: SimulationFlags::empty(),
			..Default::default()
		});
		arena.link(1, 2);
		arena.link(2, 1);
		let enabled = arena.get_id(1).unwrap();
		let disabled = arena.get_id(2).unwrap();
		let seeds = [enabled].into_iter().collect::<rustc_hash::FxHashSet<_>>();
		assert!(!solver_edge_enabled(&arena, enabled, disabled, &seeds));
		assert!(!solver_edge_enabled(&arena, disabled, enabled, &seeds));
	}

	#[test]
	fn transient_half_edges_cannot_transfer_gas() {
		let mut arena = TurfGases {
			graph: StableDiGraph::default(),
			map: IndexMap::default(),
			generations: FxHashMap::default(),
		};
		for id in 1..=2 {
			arena.insert_turf(TurfMixture {
				mix: (id - 1) as usize,
				id,
				flags: SimulationFlags::SIMULATION_ALL,
				..Default::default()
			});
		}
		let first = arena.get_id(1).unwrap();
		let second = arena.get_id(2).unwrap();
		arena.graph.add_edge(first, second, ());
		let participants = [first, second]
			.into_iter()
			.collect::<rustc_hash::FxHashSet<_>>();
		assert!(!solver_edge_enabled(&arena, first, second, &participants));
		arena.graph.add_edge(second, first, ());
		assert!(solver_edge_enabled(&arena, first, second, &participants));
		assert!(solver_edge_enabled(&arena, second, first, &participants));
	}

	#[test]
	#[should_panic(expected = "atmos conservation failure")]
	fn conservation_is_a_hard_failure_in_tests() {
		let violations = [ConservationViolation {
			component_size: 2,
			mixture_ids: vec![1, 2],
			gas_deltas: vec![(0, 10.0, 5.0, -5.0)],
			energy_before: 1000.0,
			energy_after: 500.0,
		}];
		let diagnostic = format_conservation_violations(&violations);
		report_conservation_violations(&violations, &diagnostic);
	}
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
fn post_process(active_nodes: &rustc_hash::FxHashSet<NodeIndex>) -> (usize, usize, usize) {
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
		let events = processables
			.into_iter()
			.map(|(tmix, should_update_vis, should_react)| {
				(tmix.id, should_update_vis, should_react)
			})
			.collect::<Vec<_>>();
		let event_count = events.len();
		let reaction_count = events.iter().filter(|event| event.2).count();
		let overlay_count = events.iter().filter(|event| event.1).count();
		if !events.is_empty() {
			let sender = byond_callback_sender();
			drop(sender.try_send(Box::new(move || {
				for (id, should_update_vis, should_react) in events {
					let turf = ByondValue::new_ref(ValueType::Turf, id);
					if should_react {
						let reaction_start = Instant::now();
						if let Ok(air) = turf.read_var_id(byond_string!("air")) {
							if !air.is_null() {
								react_hook(air, turf).wrap_err("Reacting")?;
							}
						}
						REACTION_CALLBACK_MICROS.fetch_add(
							reaction_start.elapsed().as_micros() as u64,
							Ordering::Relaxed,
						);
					}
					if should_update_vis {
						let overlay_start = Instant::now();
						update_visuals(turf).wrap_err("Updating Visuals")?;
						OVERLAY_CALLBACK_MICROS.fetch_add(
							overlay_start.elapsed().as_micros() as u64,
							Ordering::Relaxed,
						);
					}
				}
				Ok(())
			})));
		}
		(event_count, reaction_count, overlay_count)
	})
}
