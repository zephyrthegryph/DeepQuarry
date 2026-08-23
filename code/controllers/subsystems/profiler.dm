SUBSYSTEM_DEF(profiler)
	name = "Profiler"
	init_stage = INITSTAGE_FIRST
	runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY
	wait = 30 SECONDS
	var/fetch_cost = 0
	var/write_cost = 0

/datum/controller/subsystem/profiler/stat_entry(msg)
	msg += "F:[round(fetch_cost,1)]ms"
	msg += "|W:[round(write_cost,1)]ms"
	return msg

/datum/controller/subsystem/profiler/Initialize()
	if(CONFIG_GET(flag/auto_profile))
		StartProfiling()
	else
		StopProfiling() //Stop the early start profiler
	wait = CONFIG_GET(number/profiler_interval)
	var/run_idle_benchmark = fexists("data/benchmark_idle")
	var/run_sm_benchmark = fexists("data/benchmark_sm")
	if(run_idle_benchmark)
		fdel("data/benchmark_idle")
	if(run_sm_benchmark)
		fdel("data/benchmark_sm")
	if(run_idle_benchmark || run_sm_benchmark)
		Master.sleep_offline_after_initializations = FALSE
		SSticker.start_immediately = TRUE
		SSmachines.profile_machine_types = TRUE
	if(run_sm_benchmark)
		SSticker.OnRoundstart(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(schedule_sm_benchmark)))
	return SS_INIT_SUCCESS

/proc/schedule_sm_benchmark()
	log_runtime("ATMOS_BENCHMARK scheduled supermatter explosion in 60 seconds")
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(run_sm_benchmark)), 60 SECONDS)

/proc/run_sm_benchmark()
	for(var/obj/machinery/power/supermatter/SM in world)
		log_runtime("ATMOS_BENCHMARK detonating [SM] at [SM.x],[SM.y],[SM.z]")
		SM.explode()
		return
	var/list/station_areas = get_station_areas(list())
	while(length(station_areas))
		var/area/target_area = pick_n_take(station_areas)
		var/list/open_turfs = list()
		for(var/turf/open/T in target_area)
			open_turfs += T
		if(!length(open_turfs))
			continue
		var/turf/open/epicenter = pick(open_turfs)
		log_runtime("ATMOS_BENCHMARK detonating fallback bomb at [epicenter.x],[epicenter.y],[epicenter.z]")
		explosion(epicenter, 8, 16, 24, 32, TRUE)
		return
	log_runtime("ATMOS_BENCHMARK could not find a valid station turf")

/datum/controller/subsystem/profiler/OnConfigLoad()
	if(CONFIG_GET(flag/auto_profile))
		StartProfiling()
		can_fire = TRUE
	else
		StopProfiling()
		can_fire = FALSE

/datum/controller/subsystem/profiler/fire()
	// Full BYOND profile serialization is synchronous and can itself overrun a tick.
	// Periodic collection therefore records only the inexpensive native diagnostics;
	// profile dumps are requested explicitly or by the MC drift outlier detector.
	log_runtime("ATMOS_PROFILE [json_encode(SSair.auxmos_diagnostics())]")
	log_runtime("RUST_ALLOC_PROFILE [json_encode(SSair.verdigris_allocator_diagnostics())]")

/datum/controller/subsystem/profiler/Shutdown()
	if(CONFIG_GET(flag/auto_profile))
		DumpFile(allow_yield = FALSE)
		world.Profile(PROFILE_CLEAR, type = "sendmaps")
	return ..()

/datum/controller/subsystem/profiler/proc/StartProfiling()
	world.Profile(PROFILE_START)
	world.Profile(PROFILE_START, type = "sendmaps")

/datum/controller/subsystem/profiler/proc/StopProfiling()
	world.Profile(PROFILE_STOP)
	world.Profile(PROFILE_STOP, type = "sendmaps")

/datum/controller/subsystem/profiler/proc/DumpFile(allow_yield = TRUE)
	var/timer = TICK_USAGE_REAL
	var/current_profile_data = world.Profile(PROFILE_REFRESH, format = "json")
	var/current_sendmaps_data = world.Profile(PROFILE_REFRESH, type = "sendmaps", format="json")
	fetch_cost = MC_AVERAGE(fetch_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))
	if(allow_yield)
		CHECK_TICK

	if(!length(current_profile_data)) //Would be nice to have explicit proc to check this
		stack_trace("Warning, profiling stopped manually before dump.")
	var/prof_file = file("[GLOB.log_directory]/profiler/profiler-[round(world.time * 0.1, 10)].json")
	if(fexists(prof_file))
		fdel(prof_file)
	if(!length(current_sendmaps_data)) //Would be nice to have explicit proc to check this
		stack_trace("Warning, sendmaps profiling stopped manually before dump.")
	var/sendmaps_file = file("[GLOB.log_directory]/profiler/sendmaps-[round(world.time * 0.1, 10)].json")
	if(fexists(sendmaps_file))
		fdel(sendmaps_file)

	timer = TICK_USAGE_REAL
	WRITE_FILE(prof_file, current_profile_data)
	WRITE_FILE(sendmaps_file, current_sendmaps_data)
	write_cost = MC_AVERAGE(write_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))
