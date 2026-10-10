// The DX refresh engine's cost (review 2 H3): periodic machines that draw, stepping every tick-ish
// cadence, each step marking the machine changed; plus a burst of marks (an explosion's worth).
// Run: tools/build/build.sh bench --scenario=dx_refresh [--bench_count=2000]

/obj/machinery/dx_bench_drawer
	name = "refresh benchmark machine"
	periodic_cadence = CADENCE_SECOND
	var/bench_level = 0

/obj/machinery/dx_bench_drawer/should_run()
	return TRUE

/obj/machinery/dx_bench_drawer/periodic_step(delta)
	bench_level = (bench_level + 1) % 20   // a plain var: the step marks the machine, draw() re-runs

/obj/machinery/dx_bench_drawer/draw(datum/look/look)
	..()
	look.state("drawer")
	look.gauge("drawer_level", level = bench_level / 20, levels = 4)   // changes a key only every 5 steps

/datum/benchmark/dx_refresh
	id = "dx_refresh"
	description = "DX refresh engine: N drawing periodic machines for 20 s, then a burst of 5N marks"

/datum/benchmark/dx_refresh/Run()
	var/count = param("count", 2000)
	var/list/made = list()
	var/turf/origin = locate(10, 10, 1)
	for(var/i in 1 to count)
		made += new /obj/machinery/dx_bench_drawer(locate(origin.x + (i % 60), origin.y + round(i / 60) % 60, origin.z))
	refresh_flush()
	begin_window()
	var/drains_before = GLOB.refresh_bench_drained
	sleep(20 SECONDS)
	end_window("steady")
	count_metric("refreshes_per_second", (GLOB.refresh_bench_drained - drains_before) / 20, "refreshes/s", "none")
	begin_window()
	var/start = REALTIMEOFDAY
	for(var/repeat in 1 to 5)
		for(var/obj/machinery/dx_bench_drawer/M as anything in made)
			changed(M)
	refresh_flush()
	metric("burst_ms", REALTIMEOFDAY - start, "ms")
	end_window("burst")
	for(var/obj/machinery/dx_bench_drawer/M as anything in made)
		qdel(M)
