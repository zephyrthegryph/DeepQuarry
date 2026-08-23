use super::*;
use coarsetime::{Duration, Instant};
use parking_lot::{const_mutex, Mutex};
use std::collections::{BTreeSet, HashSet, VecDeque};

static GROUPS_CHANNEL: Mutex<Option<BTreeSet<TurfID>>> = const_mutex(None);
const GROUP_PROCESS_BUDGET: Duration = Duration::from_millis(50);
const MAX_GROUP_TURFS_PER_GENERATION: usize = 8_192;

pub fn flush_groups_channel() {
	*GROUPS_CHANNEL.lock() = None;
}

pub fn retire_turf(id: TurfID) {
	if let Some(group) = GROUPS_CHANNEL.lock().as_mut() {
		group.remove(&id);
	}
}

fn with_groups<T>(f: impl Fn(Option<BTreeSet<TurfID>>) -> T) -> T {
	f(GROUPS_CHANNEL.lock().take())
}

pub fn send_to_groups(sent: BTreeSet<TurfID>) {
	GROUPS_CHANNEL.try_lock().map(|mut opt| opt.replace(sent));
}

pub(super) fn process_groups(
	group_pressure_goal: f32,
	low_pressure_turfs: BTreeSet<TurfID>,
) -> (usize, f32) {
	let start_time = Instant::now();
	let (processed, _) = excited_group_processing(
		group_pressure_goal,
		low_pressure_turfs,
		(&start_time, GROUP_PROCESS_BUDGET),
	);
	(processed, start_time.elapsed().as_millis() as f32)
}
/// Returns: If this cycle is interrupted by overtiming or not. Starts a processing excited groups cycle, does nothing if process_turfs isn't ran.
#[byondapi::bind("/datum/controller/subsystem/air/proc/process_excited_groups_auxtools")]
#[auxmacros::panic_safe]
fn groups_hook(mut src: ByondValue, remaining: ByondValue) -> Result<ByondValue> {
	let group_pressure_goal = src
		.read_number_id(byond_string!("excited_group_pressure_goal"))
		.unwrap_or(0.5);
	let remaining_time = Duration::from_millis(remaining.get_number().unwrap_or(50.0) as u64);
	let start_time = Instant::now();
	let (num_eq, is_cancelled) = with_groups(|thing| {
		if let Some(high_pressure_turfs) = thing {
			excited_group_processing(
				group_pressure_goal,
				high_pressure_turfs,
				(&start_time, remaining_time),
			)
		} else {
			(0, false)
		}
	});

	let bench = start_time.elapsed().as_millis();
	let prev_cost = src
		.read_number_id(byond_string!("cost_groups"))
		.map_err(|_| eyre::eyre!("Attempt to interpret non-number value as number"))?;
	src.write_var_id(
		byond_string!("cost_groups"),
		&(0.8 * prev_cost + 0.2 * (bench as f32)).into(),
	)?;
	src.write_var_id(
		byond_string!("num_group_turfs_processed"),
		&(num_eq as f32).into(),
	)?;
	Ok(is_cancelled.into())
}

// Finds small differences in turf pressures and equalizes them.
#[cfg_attr(not(target_feature = "avx2"), auxmacros::generate_simd_functions)]
#[cfg_attr(feature = "tracy", tracing::instrument(skip_all))]
fn excited_group_processing(
	pressure_goal: f32,
	low_pressure_turfs: BTreeSet<TurfID>,
	(start_time, remaining_time): (&Instant, Duration),
) -> (usize, bool) {
	let mut found_turfs: HashSet<TurfID, FxBuildHasher> = Default::default();
	let mut is_cancelled = false;
	for &initial_turf in &low_pressure_turfs {
		if found_turfs.len() >= MAX_GROUP_TURFS_PER_GENERATION {
			is_cancelled = true;
			break;
		}
		if found_turfs.contains(&initial_turf) {
			continue;
		}

		if start_time.elapsed() >= remaining_time {
			is_cancelled = true;
			break;
		}

		let changes = with_turf_gases_read(|arena| {
			let Some(initial_mix_ref) = arena.get_from_id(initial_turf) else {
				return Vec::new();
			};
			if !initial_mix_ref.enabled() {
				return Vec::new();
			}

			let mut border_turfs: VecDeque<TurfID> = VecDeque::with_capacity(40);
			let mut turfs: Vec<&TurfMixture> = Vec::with_capacity(200);
			let mut min_pressure = initial_mix_ref.return_pressure();
			let mut max_pressure = min_pressure;
			let mut fully_mixed = Mixture::new();

			border_turfs.push_back(initial_turf);
			found_turfs.insert(initial_turf);
			GasArena::with_all_mixtures(|all_mixtures| {
				loop {
					if turfs.len() >= 2500
						|| found_turfs.len() >= MAX_GROUP_TURFS_PER_GENERATION
						|| start_time.elapsed() >= remaining_time
					{
						is_cancelled = true;
						break;
					}
					if let Some(idx) = border_turfs.pop_front() {
						let Some(tmix) = arena.get_from_id(idx) else {
							break;
						};
						if let Some(lock) = all_mixtures.get(tmix.mix) {
							let mix = lock.read();
							let pressure = mix.return_pressure();
							let this_max = max_pressure.max(pressure);
							let this_min = min_pressure.min(pressure);
							if (this_max - this_min).abs() >= pressure_goal {
								continue;
							}
							min_pressure = this_min;
							max_pressure = this_max;
							turfs.push(tmix);
							fully_mixed.merge(&mix);
							fully_mixed.volume += mix.volume;
							arena
								.adjacent_turf_ids(arena.get_id(idx).unwrap())
								.filter(|&loc| found_turfs.insert(loc))
								.filter(|&loc| {
									arena.get_from_id(loc).filter(|b| b.enabled()).is_some()
								})
								.for_each(|loc| border_turfs.push_back(loc));
						}
					} else {
						break;
					}
				}
				fully_mixed.multiply(1.0 / turfs.len() as f32);
				if !fully_mixed.is_corrupt() {
					turfs
						.par_iter()
						.filter_map(|turf| {
							let mix_lock = all_mixtures.get(turf.mix)?;
							let mut mixture = mix_lock.write();
							let before = GasArena::change_signature(&mixture);
							mixture.copy_from_mutable(&fully_mixed);
							let after = GasArena::change_signature(&mixture);
							Some((turf.mix, before, after))
						})
						.collect()
				} else {
					Vec::new()
				}
			})
		});
		for (mix, before, after) in changes {
			if GasArena::signature_changed(&before, &after) {
				GasArena::bump_revision(mix);
				GasArena::mark_dirty_if_changed(mix, before, after);
			}
		}
	}
	// A budget interruption must defer work, never discard it. Requeue the
	// generation's pressure candidates so the ordinary active-turf pipeline
	// revisits both the unfinished component and the edge of any partial mix.
	if is_cancelled {
		for turf in low_pressure_turfs {
			mark_turf_active(turf);
		}
	}
	(found_turfs.len(), is_cancelled)
}
