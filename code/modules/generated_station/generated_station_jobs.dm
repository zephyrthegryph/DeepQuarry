#define GENERATED_STATION_TICK_BUDGET_NORMAL 40
#define GENERATED_STATION_TICK_BUDGET_FAST 80

/// Resumable orchestration state for one station materialization: lane work
/// (job_cursor(), code/engine/kernel/jobs.dm). The materializer's phases run a
/// slice at a time and return a cursor when checkpoint() says the slice's budget
/// is spent, so nothing sleeps and a partially built z-level is never exposed to
/// players. The normal budget deliberately leaves most of a 25 ms tick to the live game.
/datum/generated_station_materialization_job
	var/tmp/datum/generated_station_materializer/materializer
	var/tmp/datum/flight_plan/flight_plan
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
	var/tmp/datum/generated_station_materialization/materialization
	/// Runs every phase at once (materialize()), or as lane work (materialize_async()).
	var/now = TRUE
	/// The materializer's phases, the one running and where it resumes.
	var/list/phases
	var/phase_index = 1
	var/phase_cursor
	/// materialize_async(): at the end, after(then_owner, 0, then, with = then_with + the materialization (or null)) runs; the caller made it.
	var/then
	var/datum/then_owner
	var/list/then_with

CAPABILITIES(/datum/generated_station_materialization_job)
	ref_one(nameof(then_owner))

/datum/generated_station_materialization_job/New(datum/generated_station_materializer/new_materializer, datum/flight_plan/new_flight_plan, fast_mode = FALSE)
	..()
	rel_set(src, nameof(materializer), new_materializer)
	rel_set(src, nameof(flight_plan), new_flight_plan)
	if(fast_mode)
		tick_budget = GENERATED_STATION_TICK_BUDGET_FAST
	var/static/next_timer_id = 0
	next_timer_id = (next_timer_id % 1000000) + 1
	timer_id = "generated-station-materialization-[next_timer_id]"
	rustg_time_reset(timer_id)

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
	if(flight_plan() && !QDELETED(flight_plan()))
		flight_plan().generation_stage = phase
		flight_plan().generation_progress = max(flight_plan().generation_progress, progress)
	if(now)
		return FALSE
	if(force_yield || slice_usage >= tick_budget || om_scheduler().out_of_budget())
		// The phase returns its cursor and carries on in the next slice.
		yield_count++
		rustg_time_reset(timer_id)
		last_checkpoint_microseconds = 0
		return TRUE
	return FALSE

/// Materializes at once; returns the materialization or null.
/datum/generated_station_materialization_job/proc/execute(datum/generated_station_spec/spec, z_level, origin_x, origin_y)
	now = TRUE
	if(start(spec, z_level, origin_x, origin_y))
		job_cursor(src, PROC_REF(run_slice), 1, null, TRUE)
	return end_run()

/// Materializes as lane work; then, owner and with are run with the materialization (or null) as after() does.
/datum/generated_station_materialization_job/proc/execute_async(datum/generated_station_spec/spec, z_level, origin_x, origin_y, new_then, datum/new_then_owner, list/new_then_with)
	now = FALSE
	then = new_then
	if(new_then_owner)
		rel_set(src, nameof(then_owner), new_then_owner)
	then_with = new_then_with
	if(!start(spec, z_level, origin_x, origin_y))
		finish_async()
		return
	job_cursor(src, PROC_REF(run_slice), 1, PROC_REF(finish_async))

/datum/generated_station_materialization_job/proc/start(datum/generated_station_spec/spec, z_level, origin_x, origin_y)
	started_at = REALTIMEOFDAY
	checkpoint("Preparing station plan", 22)
	// Do not attribute planner/decoder work from the caller's tick to this job.
	peak_tick_usage = 0
	rustg_time_reset(timer_id)
	last_checkpoint_microseconds = 0
	phases = TYPE_TABLE_GET(materializer(), materialize_phases)
	if(!materializer().prepare_materialization(spec, z_level, origin_x, origin_y, src))
		failed = TRUE
		return FALSE
	return TRUE

/// One slice: the current phase from its cursor. The next cursor for job_cursor(), or null
/// when every phase is done (or one failed).
/datum/generated_station_materialization_job/proc/run_slice(cursor)
	if(!now)
		// A slice's budget counts from its own start, not across the ticks between slices.
		rustg_time_reset(timer_id)
		last_checkpoint_microseconds = 0
	var/phase = phases[phase_index]
	var/resume = call(materializer(), phase)(phase_cursor)
	if(resume == GENERATED_STATION_PHASE_FAILED)
		failed = TRUE
		return null
	if(!isnull(resume))
		phase_cursor = resume
		return phase_index
	phase_cursor = null
	phase_index++
	return phase_index <= length(phases) ? phase_index : null

/datum/generated_station_materialization_job/proc/end_run()
	finished_at = REALTIMEOFDAY
	if(failed || !materializer().result)
		failed = TRUE
		failure_reason = materializer().last_failure_details || phase
		rel_clear(src, nameof(materialization))
		return null
	// Hand-off: the materializer owns its result only while building it, so it lets go here
	// (deleting the materializer afterwards must not delete the station it built). The expedition
	// site adopts it (rel_set) when it is published.
	var/datum/generated_station_materialization/done = rel_take(materializer(), nameof(/datum/generated_station_materializer::result))
	rel_set(src, nameof(materialization), done)
	checkpoint("Station materialization complete", 62)
	return done

/datum/generated_station_materialization_job/proc/finish_async()
	var/datum/generated_station_materialization/result = end_run()
	materializer().record_job_telemetry(src)
	var/callback = then
	var/datum/callback_owner = then_owner
	var/list/callback_with = then_with
	spent(src)
	if(callback)
		after(callback_owner, 0, callback, with = (callback_with || list()) + list(result))

#undef GENERATED_STATION_TICK_BUDGET_NORMAL
#undef GENERATED_STATION_TICK_BUDGET_FAST

/// Accessor for the materializer var.
/datum/generated_station_materialization_job/proc/materializer() as /datum/generated_station_materializer
	return materializer

/// Accessor for the flight_plan var.
/datum/generated_station_materialization_job/proc/flight_plan() as /datum/flight_plan
	return flight_plan

/// Accessor for the materialization var.
/datum/generated_station_materialization_job/proc/materialization() as /datum/generated_station_materialization
	return materialization



