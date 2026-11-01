// The cost of the arrivals shuttle moving to and from the station dock: the move itself, and the work it leaves for the following ticks (the new
// turfs' after-init passes, lighting, atmos). Each leg is reported apart, the first from the others.
//   tools/build/build.sh bench --scenario=shuttle_landing [--profile] [--arg=legs=4]

/datum/benchmark/shuttle_landing
	id = "shuttle_landing"
	description = "Arrivals shuttle docking legs: the move and the ticks of follow-up work it causes"

/datum/benchmark/shuttle_landing/Run()
	wait_for_assets()
	var/datum/shuttle/autodock/ferry/arrivals/shuttle = shuttles_shuttles()["Arrivals"]
	if(!shuttle)
		fail("no Arrivals shuttle is registered")
	var/legs = param("legs", 4)
	begin_window()
	for(var/leg in 1 to legs)
		var/obj/effect/shuttle_landmark/target = (leg % 2) ? shuttle.landmark_station() : shuttle.landmark_offsite()
		var/stamp = TICK_USAGE_REAL
		var/moved = shuttle.attempt_move(target)
		var/move_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
		var/follow_start = REALTIMEOFDAY
		for(var/tick in 1 to 40)
			stoplag()
		metric("leg[leg]_moved", moved ? 1 : 0, "", "none", "count")
		metric("leg[leg]_move_ms", move_ms, "ms")
		metric("leg[leg]_follow_up_wall_ms", (REALTIMEOFDAY - follow_start) * 100, "ms")
	end_window("legs")
