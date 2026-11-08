// A large explosion (the admin bomb, 8/16/24) or a supermatter delamination in the real station (full map): the pipes, cables and
// machines around it are what the epoch's closing commits (pipenets, power, contracts) have to settle, which the bare-floor fixture of
// major_events does not have. Two windows: `explosion` (trigger to settled) and `aftermath` (the 60 s after: repressurisation, GC,
// lighting and draw catch-up, network rebuilds), with memory marks before and after and a per-type ex_act cost sample.
//   tools/build/build.sh bench --scenario=station_explosion -DCITESTING_FULL_MAP [--profile] [--arg=power=8] [--arg=trigger=supermatter]
//   --arg=after=60 sets the aftermath seconds.

/datum/benchmark/station_explosion
	id = "station_explosion"
	description = "A large explosion or SM delamination on the station: worst/mean tick during and 60 s after, per-system cost, memory before and after"

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
	var/trigger = param("trigger", "explosion")
	var/after_seconds = param("after", 60)
	// Settle the boot first so the windows measure the blast, not the tail of init.
	wait_seconds(10)
	SSexplosions.enable_atom_type_profiling()
	var/list/garbage_before = SSgarbage.performance_diagnostics()
	count_metric("before_atoms", length(world.contents), "atoms", "none")
	mark("before")
	var/list/work_before = work_counts()
	begin_window()
	var/start = REALTIMEOFDAY
	switch(trigger)
		if("explosion")
			explosion(center, power, power * 2, power * 3, power * 4, FALSE, 0)
		if("supermatter")
			var/obj/machinery/power/supermatter/crystal = new(center)
			crystal.pull_time = 0
			crystal.power = 5000
			crystal.explode()
		else
			fail("unknown trigger '[trigger]' (explosion or supermatter)")
	var/deadline = REALTIMEOFDAY + 300 SECONDS
	stoplag()
	// The supermatter's blast is queued by a timer after the pull; wait for its epoch to start before waiting for it to end.
	while(!explosions_awake() && trigger == "supermatter" && REALTIMEOFDAY < start + 30 SECONDS)
		stoplag()
	while(explosions_awake() && REALTIMEOFDAY < deadline)
		stoplag()
	metric("settle_wall_ms", (REALTIMEOFDAY - start) * 100, "ms")
	metric("settled", explosions_awake() ? 0 : 1, "", "none", "count")
	end_window("explosion")
	detail("explosion_profile", SSexplosions.performance_diagnostics())
	var/list/commit = SSexplosions.performance_diagnostics()["last_commit_ms"]
	for(var/part in commit)
		metric("commit_[part]_ms", commit[part], "ms")
	work_metrics("explosion", work_before)
	var/list/work_mid = work_counts()
	begin_window()
	wait_seconds(after_seconds)
	end_window("aftermath")
	work_metrics("aftermath", work_mid)
	mark("after")
	count_metric("after_atoms", length(world.contents), "atoms", "none")
	detail("garbage_before", garbage_before)
	detail("garbage_after", SSgarbage.performance_diagnostics())
