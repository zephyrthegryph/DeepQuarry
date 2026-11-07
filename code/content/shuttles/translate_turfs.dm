/proc/translate_turfs(list/translation, area/base_area = null, turf/base_turf)
	var/list/changed_turfs = list()
	var/profile_start = TICK_USAGE_REAL
	var/translated = 0
	var/worst_turf_ms = 0
	var/worst_turf_type
	var/turf_loop_ms = 0
	// The neighbourhood work of every ChangeTurf (starlight, edge masks) runs once per turf when the move ends.
	var/outer_open = GLOB.turf_move_open
	GLOB.turf_move_open = TRUE
	var/calls_before = GLOB.turf_move_calls
	var/new_ms_before = GLOB.turf_move_new_ms
	for(var/turf/source in translation)

		var/turf/target = translation[source]

		if(target)
			var/turf_start = TICK_USAGE_REAL
			if(base_area) ChangeArea(target, get_area(source))
			var/leave_turf = base_turf ? base_turf : get_base_turf_by_area(base_area ? base_area : source)
			var/source_x = source.x
			var/source_y = source.y
			var/source_z = source.z
			var/turf/new_destination = translate_turf(source, target, leave_turf)
			if(new_destination)
				changed_turfs |= new_destination
			changed_turfs |= locate(source_x, source_y, source_z)
			if(base_area) ChangeArea(source, base_area)
			var/this_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - turf_start)
			translated++
			turf_loop_ms += this_ms
			if(this_ms > worst_turf_ms)
				worst_turf_ms = this_ms
				worst_turf_type = "[source.type]"

	var/flush_start = TICK_USAGE_REAL
	var/flushed = length(GLOB.turf_move_changed)
	var/flushed_edges = length(GLOB.turf_move_edges)
	if(!outer_open) // a move inside a move: the outer one flushes
		GLOB.turf_move_open = FALSE
		turf_move_flush()
		GLOB.turf_move_changed.Cut()
	var/flush_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - flush_start)

	// ChangeTurf initially sees each destination before the shuttle's blocking
	// objects have been relocated onto it. Republish every moved turf's air-block
	// mask only after every wall, window, and door is in its final location.
	// Rust derives each face from the masks on both sides, so the stationary
	// neighbours need no update of their own.
	var/air_start = TICK_USAGE_REAL
	for(var/turf/changed as anything in changed_turfs)
		changed.air_update_turf(TRUE, FALSE)
	// A shuttle move is one burst of work on the tick it happens in: say where it went (the PERF_PROFILE callback rows only name the mover).
	log_world("SHUTTLE_MOVE_PROFILE: [translated] turf(s) translated in [round(turf_loop_ms, 0.1)] ms (average [translated ? round(turf_loop_ms / translated, 0.01) : 0] ms, worst [round(worst_turf_ms, 0.1)] ms on [worst_turf_type || "none"]), [length(changed_turfs)] air mask(s) republished in [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - air_start), 0.1)] ms, [GLOB.turf_move_calls - calls_before] ChangeTurf call(s) of which `new` took [round(GLOB.turf_move_new_ms - new_ms_before, 0.1)] ms, neighbourhood flush of [flushed] turf(s) / [flushed_edges] edge mask(s) [round(flush_ms, 0.1)] ms, whole translate [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - profile_start), 0.1)] ms, [GLOB.turf_change_calls] ChangeTurf calls since boot")

	//change the old turfs (Currently done by translate_turf for us)
	//for(var/turf/source in translation)
	//	source.ChangeTurf(base_turf ? base_turf : get_base_turf_by_area(source), 1, 1)

