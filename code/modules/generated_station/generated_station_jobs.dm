#define GENERATED_STATION_TICK_BUDGET_NORMAL 40
#define GENERATED_STATION_TICK_BUDGET_FAST 80

/// Resumable orchestration state for one station materialization. Individual
/// hot loops call checkpoint(), allowing the proc stack to sleep and resume on
/// the next tick without exposing a partially built z-level to players. The
/// normal budget deliberately leaves most of a 25 ms tick to the live game.
/datum/generated_station_materialization_job
	var/datum/generated_station_materializer/materializer
	var/datum/flight_plan/flight_plan
	var/phase = "queued"
	var/progress = 0
	var/tick_budget = GENERATED_STATION_TICK_BUDGET_NORMAL
	var/yield_count = 0
	var/peak_tick_usage = 0
	var/peak_phase
	var/timer_id
	var/last_checkpoint_microseconds = 0
	var/started_at
	var/finished_at
	var/failed = FALSE
	var/failure_reason
	var/datum/generated_station_materialization/materialization

/datum/generated_station_materialization_job/New(datum/generated_station_materializer/new_materializer, datum/flight_plan/new_flight_plan, fast_mode = FALSE)
	..()
	materializer = new_materializer
	flight_plan = new_flight_plan
	if(fast_mode)
		tick_budget = GENERATED_STATION_TICK_BUDGET_FAST
	var/static/next_timer_id = 0
	next_timer_id = (next_timer_id % 1000000) + 1
	timer_id = "generated-station-materialization-[next_timer_id]"
	rustg_time_reset(timer_id)

/datum/generated_station_materialization_job/Destroy()
	materializer = null
	flight_plan = null
	materialization = null
	timer_id = null
	return ..()

/datum/generated_station_materialization_job/proc/checkpoint(new_phase, new_progress, force_yield = FALSE)
	// Measure only uninterrupted generator work. world.tick_usage can reset or
	// include unrelated subsystems around a sleeping proc, so it cannot produce
	// a reliable per-job delta. The monotonic timer is reset after every yield.
	var/slice_microseconds = rustg_time_microseconds(timer_id)
	var/slice_usage = slice_microseconds / max(world.tick_lag * 1000, 1)
	var/checkpoint_usage = max(0, slice_microseconds - last_checkpoint_microseconds) / max(world.tick_lag * 1000, 1)
	var/measured_phase = phase
	last_checkpoint_microseconds = slice_microseconds
	if(checkpoint_usage > peak_tick_usage)
		peak_tick_usage = checkpoint_usage
		peak_phase = measured_phase
	if(new_phase)
		phase = new_phase
	progress = clamp(new_progress, progress, 100)
	if(flight_plan && !QDELETED(flight_plan))
		flight_plan.generation_stage = phase
		flight_plan.generation_progress = max(flight_plan.generation_progress, progress)
	if(force_yield || slice_usage >= tick_budget)
		yield_count++
		// A zero-duration sleep only moves this proc to the back of BYOND's current
		// scheduler queue. Under sustained generation it can immediately resume in
		// the same tick, starving the master controller and client map sending.
		// world.tick_lag is fractional (0.25 ds at 40 TPS). The generator normally
		// reaches sleep before the MC, so an equal-duration sleep also wakes it first
		// and makes background work delay every MC cycle. Wait for the MC iteration
		// to advance, then resume inside its sleep window instead.
		var/mc_iteration = Master?.iteration
		sleep(world.tick_lag)
		while(Master && Master.iteration == mc_iteration)
			sleep(world.tick_lag * 0.1)
		rustg_time_reset(timer_id)
		last_checkpoint_microseconds = 0

/datum/generated_station_materialization_job/proc/execute(datum/generated_station_spec/spec, z_level, origin_x, origin_y)
	started_at = REALTIMEOFDAY
	checkpoint("Preparing station plan", 22, TRUE)
	// Do not attribute planner/decoder work from the caller's tick to this job.
	peak_tick_usage = 0
	rustg_time_reset(timer_id)
	last_checkpoint_microseconds = 0
	materialization = materializer.materialize_incremental(spec, z_level, origin_x, origin_y, src)
	finished_at = REALTIMEOFDAY
	if(!materialization)
		failed = TRUE
		failure_reason = materializer.last_failure_details || phase
		return null
	checkpoint("Station materialization complete", 62)
	return materialization

#undef GENERATED_STATION_TICK_BUDGET_NORMAL
#undef GENERATED_STATION_TICK_BUDGET_FAST
