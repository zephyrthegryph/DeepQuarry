// Lighting object rebuild over the loaded world: the lazy build (lighting_build_overlay makes an object only for a lit turf)
// against the old eager one (an object on every dynamic turf), each followed by the light pass that draws them.
// Times are wall clock (the build yields with CHECK_TICK).
//   tools/build/build.sh bench --scenario=lighting_rebuild

/datum/benchmark/lighting_rebuild
	id = "lighting_rebuild"
	description = "Lighting objects: lazy build vs an object on every dynamic turf"

/datum/benchmark/lighting_rebuild/proc/clear_all(list/all_turfs)
	for(var/turf/T as anything in all_turfs)
		if(T.lighting_object)
			T.lighting_clear_overlay()
	SSlighting.light_step(0, TRUE)

// Live objects only: a cleared one is deleted later (spent), so a world loop over the type would count it too.
/datum/benchmark/lighting_rebuild/proc/count_objects(list/all_turfs)
	. = 0
	for(var/turf/T as anything in all_turfs)
		if(T.lighting_object)
			.++

/datum/benchmark/lighting_rebuild/Run()
	var/list/all_turfs = block(locate(1, 1, 1), locate(world.maxx, world.maxy, world.maxz))
	var/dynamic = 0
	for(var/turf/T as anything in all_turfs)
		if(T.has_dynamic_lighting())
			dynamic++

	clear_all(all_turfs)
	var/start = REALTIMEOFDAY
	for(var/turf/T as anything in all_turfs)
		if(T.has_dynamic_lighting())
			T.lighting_clear_overlay()
			new /datum/lighting_object(T)
	SSlighting.light_step(0, TRUE)
	var/eager_ms = (REALTIMEOFDAY - start) * 100
	var/eager_objects = count_objects(all_turfs)

	clear_all(all_turfs)
	start = REALTIMEOFDAY
	create_all_lighting_objects()
	SSlighting.light_step(0, TRUE)
	var/lazy_ms = (REALTIMEOFDAY - start) * 100
	var/lazy_objects = count_objects(all_turfs)

	metric("lighting_dynamic_turfs", dynamic, "turfs", "none")
	metric("lighting_eager_ms", eager_ms, "ms")
	metric("lighting_lazy_ms", lazy_ms, "ms")
	metric("lighting_eager_objects", eager_objects, "objects", "none")
	metric("lighting_lazy_objects", lazy_objects, "objects", "none")
