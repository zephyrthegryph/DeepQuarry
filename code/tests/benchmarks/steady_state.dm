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
		// Breathable floors only: a human dropped on an airless floor spends the window taking pressure injuries, which is not a quiet round.
		if(F.z <= 3 && !F.density && F.turf_air()?.return_pressure() > 80)
			floors += F
		CHECK_TICK
	var/list/mob/living/carbon/human/crew = list()
	for(var/i in 1 to param("humans", 20))
		if(!length(floors))
			break
		var/mob/living/carbon/human/H = new(pick(floors))
		H.mind_initialize()
		crew += H
	wait_seconds(30) // the spawn's own settling is not the steady state
	mark("steady_before")
	var/list/work_before = work_counts()
	begin_window()
	// The crew have no clients, so Life puts them to sleep as SSD; a round's players are awake. awake=1 (default) wakes them every 2 s, so the
	// window is the cost of conscious crew (awake=0: the old window of sleepers).
	var/window_s = param("minutes", 10) * 60
	if(param("awake", 1))
		for(var/elapsed in 0 to window_s - 1 step 2)
			active_play_wake(crew)
			wait_seconds(2)
	else
		wait_seconds(window_s)
	end_window("steady")
	work_metrics("steady", work_before)
	mark("steady_after")
