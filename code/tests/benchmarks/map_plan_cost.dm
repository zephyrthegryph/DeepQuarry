// What option 2 of the boot work (load the station map from a parsed plan instead of BYOND's compiled-in map) would cost DM: the
// atoms of a slice of the station are listed as a plan (type, offset; no var overrides), then made again from it on an empty
// stretch of the world with init held back (map_loader_begin(), as a map load does), timed per atom. The compiled map's own cost is
// the boot's globals-to-world/New step (server_phases: startup_globals_to_world_new_s), against an empty-map control.
//   tools/build/build.sh bench --scenario=map_plan_cost -DCITESTING_FULL_MAP [--arg=size=48]

/datum/benchmark/map_plan_cost
	id = "map_plan_cost"
	description = "DM's cost to make a slice of the station's atoms from a plan (option 2 of the boot work), per atom"

/datum/benchmark/map_plan_cost/Run()
	var/size = param("size", 48)
	var/z = using_map.station_levels[1]
	var/cx = round(world.maxx / 2)
	var/cy = round(world.maxy / 2)
	// The plan: per turf of the slice, its type and the types of the movables directly on it.
	var/list/plan = list()
	var/turfs = 0
	var/movables = 0
	for(var/turf/T in block(locate(cx - size / 2, cy - size / 2, z), locate(cx + size / 2 - 1, cy + size / 2 - 1, z)))
		var/list/row = list(T.type, T.x - (cx - size / 2), T.y - (cy - size / 2))
		for(var/atom/movable/AM in T)
			if(ismob(AM) || AM.loc != T)
				continue
			row += AM.type
			movables++
		plan += list(row)
		turfs++
	count_metric("plan_turfs", turfs, "turfs")
	count_metric("plan_movables", movables, "atoms")
	// Where to make it: the bottom-left of the emptiest level other than the station's.
	var/target_z = 0
	for(var/level in 1 to world.maxz)
		if(level in using_map.station_levels)
			continue
		var/turf/corner = locate(1, 1, level)
		if(corner && istype(corner, /turf/space))
			target_z = level
			break
	if(!target_z)
		fail("no empty level to make the slice on")
	var/list/made = list()
	SSatoms.map_loader_begin()
	var/started = TICK_USAGE_REAL
	var/turf_ms = 0
	for(var/list/row in plan)
		var/turf/at = locate(row[2] + 2, row[3] + 2, target_z)
		var/turf_started = TICK_USAGE_REAL
		at = new row[1](at)
		turf_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - turf_started)
		for(var/i in 4 to length(row))
			var/type = row[i]
			made += new type(at)
	var/total_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	SSatoms.map_loader_stop()
	metric("plan_total_ms", total_ms, "ms")
	metric("plan_turf_ms", turf_ms, "ms")
	metric("plan_us_per_turf", turf_ms * 1000 / max(1, turfs), "us")
	metric("plan_us_per_movable", (total_ms - turf_ms) * 1000 / max(1, movables), "us")
	// The whole station at the same rates: every turf of the world, every movable on a turf.
	var/world_turfs = world.maxx * world.maxy * world.maxz
	var/world_movables = 0
	for(var/atom/movable/AM in world)
		if(isturf(AM.loc))
			world_movables++
	count_metric("world_movables_on_turfs", world_movables, "atoms")
	metric("plan_projected_world_s", (turf_ms / max(1, turfs) * world_turfs + (total_ms - turf_ms) / max(1, movables) * world_movables) / 1000, "s")
	for(var/atom/movable/AM as anything in made)
		qdel(AM)
