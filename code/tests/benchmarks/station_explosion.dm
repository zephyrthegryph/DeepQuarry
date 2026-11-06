// A large explosion (the admin bomb, 8/16/24) in a hallway of the real station (full map): the pipes, cables and machines around it are what the epoch's
// closing commits (pipenets, power, contracts) have to settle, which the bare-floor fixture of major_events does not have.
//   tools/build/build.sh bench --scenario=station_explosion -DCITESTING_FULL_MAP [--profile] [--arg=power=8]

/datum/benchmark/station_explosion
	id = "station_explosion"
	description = "A large explosion at the station engine: wall time to settle, the worst tick, and what closing the epoch cost"

/datum/benchmark/station_explosion/Run()
	wait_for_assets()
	var/area_name = param("area", "Central Hallway")
	var/turf/center
	for(var/area/A in world)
		if(findtext(A.name, area_name))
			var/list/turfs = list()
			for(var/turf/T in A)
				turfs += T
			if(length(turfs))
				center = turfs[round(length(turfs) / 2) + 1]
				break
	if(!center)
		fail("the station has no area named '[area_name]' to centre the explosion on")
	var/power = param("power", 8)
	begin_window()
	var/start = REALTIMEOFDAY
	explosion(center, power, power * 2, power * 3, power * 4, FALSE, 0)
	var/deadline = REALTIMEOFDAY + 300 SECONDS
	stoplag()
	while(explosions_awake() && REALTIMEOFDAY < deadline)
		stoplag()
	metric("settle_wall_ms", (REALTIMEOFDAY - start) * 100, "ms")
	metric("settled", explosions_awake() ? 0 : 1, "", "none", "count")
	end_window("explosion")
	detail("explosion_profile", SSexplosions.performance_diagnostics())
