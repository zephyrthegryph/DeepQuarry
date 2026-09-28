#define GENERATED_STATION_TICK_BUDGET_NORMAL 40
#define GENERATED_STATION_TICK_BUDGET_FAST 80

/// Resumable orchestration state for one station materialization: lane work
/// (om_lane_work(), object_model_core.md §4.11). The materializer's phases run a
/// slice at a time and return a cursor when checkpoint() says the slice's budget
/// is spent, so nothing sleeps and a partially built z-level is never exposed to
/// players. The normal budget deliberately leaves most of a 25 ms tick to the live game.
/datum/generated_station_materialization_job
	var/tmp/materializer_handle
	var/tmp/flight_plan_handle
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
	var/tmp/materialization_handle
	/// Runs every phase at once (materialize()), or as lane work (materialize_async()).
	var/now = TRUE
	/// The materializer's phases, the one running and where it resumes.
	var/list/phases
	var/phase_index = 1
	var/phase_cursor
	/// materialize_async(): list(callback) invoked with the materialization (or null) at the end.
	var/list/on_done_box

/datum/generated_station_materialization_job/New(datum/generated_station_materializer/new_materializer, datum/flight_plan/new_flight_plan, fast_mode = FALSE)
	..()
	materializer_handle = om_handle(new_materializer)
	flight_plan_handle = om_handle(new_flight_plan)
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
		om_lane_work(src, PROC_REF(run_slice), 1, null, TRUE)
	return end_run()

/// Materializes as lane work; `new_on_done` is invoked with the materialization (or null).
/datum/generated_station_materialization_job/proc/execute_async(datum/generated_station_spec/spec, z_level, origin_x, origin_y, datum/callback/new_on_done)
	now = FALSE
	on_done_box = list(new_on_done)
	if(!start(spec, z_level, origin_x, origin_y))
		finish_async()
		return
	om_lane_work(src, PROC_REF(run_slice), 1, PROC_REF(finish_async))

/datum/generated_station_materialization_job/proc/start(datum/generated_station_spec/spec, z_level, origin_x, origin_y)
	started_at = REALTIMEOFDAY
	checkpoint("Preparing station plan", 22)
	// Do not attribute planner/decoder work from the caller's tick to this job.
	peak_tick_usage = 0
	rustg_time_reset(timer_id)
	last_checkpoint_microseconds = 0
	phases = materializer().materialize_phases()
	if(!materializer().prepare_materialization(spec, z_level, origin_x, origin_y, src))
		failed = TRUE
		return FALSE
	return TRUE

/// One slice: the current phase from its cursor. The next cursor for om_lane_work(), or null
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
		materialization_handle = null
		return null
	var/datum/generated_station_materialization/done = materializer().result
	// Hand-off: the materializer owns its result (REF_OWNED) only while building it, so
	// deleting the materializer afterwards must not delete the station it built.
	materializer().result = null
	materialization_handle = om_handle(done)
	checkpoint("Station materialization complete", 62)
	return done

/datum/generated_station_materialization_job/proc/finish_async()
	var/datum/generated_station_materialization/result = end_run()
	materializer().record_job_telemetry(src)
	var/datum/callback/callback = on_done_box?[1]
	qdel(src)
	callback?.Invoke(result)

#undef GENERATED_STATION_TICK_BUDGET_NORMAL
#undef GENERATED_STATION_TICK_BUDGET_FAST

/// LC-refs: the materializer this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/generated_station_materialization_job/proc/materializer() as /datum/generated_station_materializer
	return om_resolve(materializer_handle)

/// LC-refs: the flight_plan this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/generated_station_materialization_job/proc/flight_plan() as /datum/flight_plan
	return om_resolve(flight_plan_handle)

/// LC-refs: the materialization this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/generated_station_materialization_job/proc/materialization() as /datum/generated_station_materialization
	return om_resolve(materialization_handle)
