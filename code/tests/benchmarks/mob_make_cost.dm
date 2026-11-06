// What building one simple mob costs, the first of a type apart from the later ones: a spawner builds its mob in one timer
// callback, so a one-time per-type cost lands as a single heavy tick.
//   tools/build/build.sh bench --scenario=mob_make_cost [--arg=count=6] [--profile]

/datum/benchmark/mob_make_cost
	id = "mob_make_cost"
	description = "Cost of make() for a mouse and a cockroach: the first of each type apart from the rest"

/datum/benchmark/mob_make_cost/Run()
	wait_for_assets()
	var/turf/T = locate(world.maxx / 2, world.maxy / 2, 1)
	if(!isturf(T))
		fail("no turf to build the mobs on")
	var/count = param("count", 6)
	var/list/made = list()
	begin_window()
	for(var/path in list(/mob/living/simple_mob/animal/passive/mouse, /mob/living/simple_mob/animal/passive/cockroach))
		var/key = replacetext("[path]", "/mob/living/simple_mob/animal/passive/", "")
		var/warm = 0
		for(var/n in 1 to count)
			var/stamp = TICK_USAGE_REAL
			var/mob/living/L = make(path, at = T)
			var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
			if(n == 1)
				metric("first_[key]_ms", ms, "ms")
			else
				warm += ms
			made += L
			stoplag()
		metric("warm_[key]_ms", warm / max(1, count - 1), "ms")
	end_window("make")
	for(var/mob/living/L as anything in made)
		qdel(L)
