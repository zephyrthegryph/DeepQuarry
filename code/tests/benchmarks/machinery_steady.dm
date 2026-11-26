// machinery_steady: the steady-state server cost of the machinery and the power grid on the mapped station with a few live humans (no input):
// one window of `seconds`, with the machine system's step cost and, under --profile, the whole run's proc profile (the machine, APC, SMES,
// door, light and console procs are read from it).
//   tools/build/build.sh bench -DCITESTING_FULL_MAP --scenario=machinery_steady [--arg=humans=10] [--arg=seconds=600] [--profile]

/datum/benchmark/machinery_steady
	id = "machinery_steady"
	description = "Steady-state machinery and power cost with a few humans on the station"

/datum/benchmark/machinery_steady/Run()
	wait_for_assets()
	wait_fires(SSair, 5)
	var/list/floors = list()
	for(var/turf/simulated/floor/F in world)
		if(F.z <= 3 && !F.density)
			floors += F
		CHECK_TICK
	for(var/i in 1 to param("humans", 10))
		if(!length(floors))
			break
		new /mob/living/carbon/human(pick(floors))
	wait_seconds(10)
	var/machines_before = kernel().work_cost_of(/datum/system/machines)["total_ms"]
	begin_window()
	var/seconds = param("seconds", 600)
	wait_seconds(seconds)
	if(profiling) // read before end_window() hands the profile to the profiler's dump
		detail("machinery_steady_proc_profile", benchmark_profile_summary(benchmark_proc_profile(), 200))
	end_window("machinery_steady")
	metric("ms_machines_step_per_s", (kernel().work_cost_of(/datum/system/machines)["total_ms"] - machines_before) / seconds, "ms/s")
