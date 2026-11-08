// machinery_steady: the steady-state server cost of the machinery and the power grid on the mapped station with a few live humans (no input):
// one window of `seconds` with the crew kept awake, with the machine system's step cost and, under --profile, the whole run's proc profile (the machine, APC, SMES,
// door, light and console procs are read from it).
//   tools/build/build.sh bench -DCITESTING_FULL_MAP --scenario=machinery_steady [--arg=humans=10] [--arg=seconds=600] [--profile]

/datum/benchmark/machinery_steady
	id = "machinery_steady"
	description = "Steady-state machinery and power cost with a few humans on the station"

/datum/benchmark/machinery_steady/Run()
	wait_for_assets()
	wait_fires(SSair, 5)
	var/list/floors = active_play_station_floors() // open station floors with air, as active_play spawns its crew
	var/list/mob/living/carbon/human/crew = list()
	for(var/i in 1 to param("humans", 10))
		if(!length(floors))
			break
		crew += new /mob/living/carbon/human(pick(floors))
	wait_seconds(10)
	var/machines_before = kernel().work_cost_of(/datum/system/machines)["total_ms"]
	begin_window()
	var/seconds = param("seconds", 600)
	// Clientless humans fall asleep within seconds (life_status_update_status()'s SSD rule): the crew is woken every five seconds, as active_play
	// does, so the window prices awake mobs.
	var/waited = 0
	while(waited < seconds)
		for(var/mob/living/carbon/human/H as anything in crew)
			if(QDELETED(H) || H.stat == DEAD)
				crew -= H // a crewman who died is not woken (set_stat() refuses the dead)
		active_play_wake(crew)
		var/step = min(5, seconds - waited)
		wait_seconds(step)
		waited += step
	var/asleep = 0
	for(var/mob/living/carbon/human/H as anything in crew)
		if(!QDELETED(H) && H.stat != CONSCIOUS)
			asleep++
	count_metric("machinery_steady_crew_alive_at_end", length(crew), "mobs", "none")
	count_metric("machinery_steady_crew_not_conscious_at_end", asleep, "mobs", "none")
	if(profiling) // read before end_window() hands the profile to the profiler's dump
		detail("machinery_steady_proc_profile", benchmark_profile_summary(benchmark_proc_profile(), 200))
	end_window("machinery_steady")
	metric("ms_machines_step_per_s", (kernel().work_cost_of(/datum/system/machines)["total_ms"] - machines_before) / seconds, "ms/s")
