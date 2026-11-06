// What building one simple mob costs, the first of a type apart from the later ones: a spawner builds its mob in one timer
// callback, so a one-time per-type cost lands as a single heavy tick. The first build of each type is timed before the
// window opens, so a --profile dump of the window shows the warm per-instance cost alone.
//   tools/build/build.sh bench --scenario=mob_make_cost [--arg=count=40] [--profile]

/datum/benchmark/mob_make_cost
	id = "mob_make_cost"
	description = "Cost of make() for a mouse and a cockroach: the first of each type, then the warm builds"

/datum/benchmark/mob_make_cost/Run()
	wait_for_assets()
	var/turf/T = locate(world.maxx / 2, world.maxy / 2, 1)
	if(!isturf(T))
		fail("no turf to build the mobs on")
	var/count = param("count", 40)
	var/list/types = list(/mob/living/simple_mob/animal/passive/mouse, /mob/living/simple_mob/animal/passive/cockroach)
	var/list/made = list()
	for(var/path in types)
		var/stamp = TICK_USAGE_REAL
		made += make(path, at = T)
		metric("first_[replacetext("[path]", "/mob/living/simple_mob/animal/passive/", "")]_ms", TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp), "ms")
		stoplag()
	begin_window()
	for(var/path in types)
		var/warm = 0
		for(var/n in 1 to count)
			var/stamp = TICK_USAGE_REAL
			var/mob/living/L = make(path, at = T)
			warm += TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
			made += L
			stoplag()
		metric("warm_[replacetext("[path]", "/mob/living/simple_mob/animal/passive/", "")]_ms", warm / count, "ms")
	end_window("make")
	for(var/mob/living/L as anything in made)
		qdel(L)
