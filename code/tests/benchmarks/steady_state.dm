// Steady state: the full map with `bench_humans` (20) live humans on station floors, measured over `bench_minutes` (10) in one window, so
// a --profile run dumps the procs of a quiet round in progress (no event, no player input).
//   tools/build/build.sh bench --scenario=steady_state -DCITESTING_FULL_MAP [--arg=minutes=10] [--arg=humans=20] [--profile]

/datum/benchmark/steady_state
	id = "steady_state"
	description = "Full map, 20 humans, 10 minutes: tick cost, top systems and procs of a quiet round"

/datum/benchmark/steady_state/Run()
	wait_for_assets()
	wait_fires(SSair, 10)
	var/list/floors = list()
	for(var/turf/simulated/floor/F in world)
		if(F.z <= 3 && !F.density)
			floors += F
		CHECK_TICK
	for(var/i in 1 to param("humans", 20))
		if(!length(floors))
			break
		var/mob/living/carbon/human/H = new(pick(floors))
		H.mind_initialize()
	wait_seconds(30) // the spawn's own settling is not the steady state
	mark("steady_before")
	var/list/work_before = work_counts()
	begin_window()
	wait_seconds(param("minutes", 10) * 60)
	end_window("steady")
	work_metrics("steady", work_before)
	mark("steady_after")
