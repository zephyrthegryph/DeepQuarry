// A player arriving where nobody has looked yet (a login, a teleport): the first draws the boot parked in view are owed at once. Reports the tick the
// arrival happens in and how long until nothing in view is owed.
//   tools/build/build.sh bench --scenario=arrival_draws [--arg=viewers=4]

/datum/benchmark/arrival_draws
	id = "arrival_draws"
	description = "First draws owed when a viewer arrives on an unseen part of the station: the arrival tick and the frames until all are drawn"

/datum/benchmark/arrival_draws/Run()
	wait_for_assets()
	set_global_benchmark_defer(TRUE)
	// Park every first draw still owed (the boot's park ran in a test build with deferral off), as a server's boot leaves them.
	var/parked = refresh_park_backlog()
	count_metric("arrival_parked_at_start", parked, "draws", "none")
	var/list/turf/spots = list()
	for(var/obj/effect/landmark/start/L in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		var/turf/T = get_turf(L)
		if(T && !(T in spots))
			spots += T
	shuffle_inplace(spots)
	var/viewers = min(param("viewers", 4), length(spots))
	if(!viewers)
		fail("no start landmarks to arrive at")
	var/worst_ms = 0
	var/total_ms = 0
	var/total_frames = 0
	var/total_owed = 0
	var/total_owing = 0
	var/skipped_before = GLOB.interest_unperceivable_skipped
	var/total_parked_left = 0
	begin_window()
	for(var/n in 1 to viewers)
		var/turf/T = spots[n]
		var/owed_before = GLOB.interest_drawn_now
		// Everything in view owes a draw, as the boot's park leaves a station nobody has looked at: a mark of an unobserved lazy atom parks it.
		var/parked_before = GLOB.refresh_deferred
		for(var/turf/seen in range(world.view, T))
			refresh_mark(seen, DEP_ALL)
			for(var/atom/movable/thing in seen)
				refresh_mark(thing, DEP_ALL)
		count_metric("arrival[n]_parked", GLOB.refresh_deferred - parked_before, "draws", "none")
		stoplag()
		var/stamp = TICK_USAGE_REAL
		GLOB.interest_test_coverable += "bench-arrival-[n]" // a player arriving: covered while its view is drawn
		interest_view_set("bench-arrival-[n]", T, null, world.view)
		var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
		worst_ms = max(worst_ms, ms)
		total_ms += ms
		var/frames = 0
		while(benchmark_arrivals_left() && frames < 600)
			stoplag()
			frames++
		total_frames += frames
		total_owed += GLOB.interest_drawn_now - owed_before
		// Draws skipped would show here: what the viewer can see that still owes a draw once its arrival is done (must be 0).
		var/owing = length(interest_view_owing("bench-arrival-[n]"))
		var/parked_left = 0
		for(var/turf/seen in range(world.view, T))
			if(seen.refresh_queued & DEP_PARKED)
				parked_left++
			for(var/atom/movable/thing in seen)
				if(thing.refresh_queued & DEP_PARKED)
					parked_left++
		total_owing += owing
		total_parked_left += parked_left
	end_window("arrival")
	metric("arrival_tick_ms_worst", worst_ms, "ms")
	metric("arrival_tick_ms_mean", total_ms / viewers, "ms")
	metric("arrival_frames_mean", total_frames / viewers, "frames", "none")
	count_metric("arrival_owed_drawn_after", total_owed, "draws", "none")
	count_metric("arrival_owing_in_view_after", total_owing, "atoms")
	count_metric("arrival_unperceivable_skipped", GLOB.interest_unperceivable_skipped - skipped_before, "draws", "none")
	count_metric("arrival_parked_in_range_after", total_parked_left, "atoms")
	for(var/n in 1 to viewers)
		interest_hold_set("bench-arrival-[n]", null)
	set_global_benchmark_defer(FALSE)

/// Turns first-draw deferral on or off for a benchmark (a test build keeps it off).
/proc/set_global_benchmark_defer(on)
	GLOB.interest_defer_marks = on

/// Owed draws still waiting behind a cover or in the prefetch.
/proc/benchmark_arrivals_left()
	return length(GLOB.interest_covered) + length(GLOB.interest_prefetched)
