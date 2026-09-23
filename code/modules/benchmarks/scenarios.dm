// Benchmark scenarios. Add a scenario by subtyping /datum/benchmark with an
// `id`; options are read with param() from `bench_<name>` world parameters
// (the runner passes `--arg name=value`).

/// Records the Rust atmos arena counters as metrics under `prefix`.
/datum/benchmark/proc/record_atmos_arena(prefix)
	// Layout of vg_auxmos_diagnostics() (verdigris/atmos/src/lib.rs):
	// gas slots, gas capacity, free gas slots, baselines, baseline capacity, dirty,
	// turf map len, turf map capacity, graph nodes, graph edges, pending turfs,
	// pending callbacks, heat state x3, node capacity, edge capacity.
	var/list/arena = vg_auxmos_diagnostics()
	if(!islist(arena) || length(arena) < 10)
		return
	metric("[prefix]_gas_mixtures", arena[1] - arena[3], "mixtures")
	metric("[prefix]_gas_slots", arena[2], "slots")
	metric("[prefix]_atmos_turfs", arena[7], "turfs")
	metric("[prefix]_atmos_edges", arena[10], "edges")
	detail("[prefix]_atmos_arena", arena)

/// Boot memory: what a freshly booted world holds, where the memory goes.
/datum/benchmark/boot_memory
	id = "boot_memory"
	description = "Memory and instance census of a freshly booted world"
	default_scenario = TRUE

/datum/benchmark/boot_memory/Run()
	wait_for_assets()
	// Let the first atmos generations and deferred init settle before measuring.
	wait_fires(SSair, 10)
	mark("booted")
	record_atmos_arena("booted")
	var/list/census = benchmark_census(param("top", 40))
	metric("instances_total", census["total"], "instances")
	for(var/root in census["by_root"])
		metric("instances_[root]", census["by_root"][root], "instances")
	detail("census_top_types", census["top_types"])
	var/list/var_lists = benchmark_var_lists(param("list_top", 60))
	metric("var_lists_total", var_lists["total"], "lists")
	metric("var_lists_empty", var_lists["empty"], "lists")
	metric("var_list_entries", var_lists["entries"], "entries")
	detail("var_lists_top", var_lists["top"])
	var/list/types = benchmark_type_counts()
	for(var/kind in types)
		metric("types_[kind]", types[kind], "types")
	metric("init_seconds", Master.initializations_seconds, "s")
	// Weakrefs never get cleaned up while their target lives, so count them by target type.
	var/list/weakref_targets = list()
	var/weakrefs = 0
	var/dead_weakrefs = 0
	for(var/datum/weakref/ref)
		weakrefs++
		var/datum/target = ref.resolve()
		if(target)
			weakref_targets["[target.type]"]++
		else
			dead_weakrefs++
		CHECK_TICK
	metric("weakrefs_total", weakrefs, "instances")
	metric("weakrefs_dead", dead_weakrefs, "instances")
	weakref_targets = sortTim(weakref_targets, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	if(length(weakref_targets) > 20)
		weakref_targets.Cut(21)
	detail("weakref_targets", weakref_targets)

/// A quiet round: steady-state tick cost with nobody playing.
/datum/benchmark/idle
	id = "idle"
	description = "Idle round tick cost and overruns"
	default_scenario = TRUE

/datum/benchmark/idle/Run()
	wait_for_assets()
	begin_window()
	wait_seconds(param("seconds", 60))
	end_window("idle")
	mark("idle_end")

/// Atmospherics baseline: 120 SSair cycles of the mapped station, recording
/// Rust worker pressure alongside tick cost.
/datum/benchmark/atmos_idle
	id = "atmos_idle"
	description = "Atmospherics cost on the mapped station at rest"

/datum/benchmark/atmos_idle/Run()
	wait_for_assets()
	measure_atmos_cycles("atmos_idle", param("cycles", 120))

/// Runs `cycles` SSair cycles inside a window and records worker maxima.
/datum/benchmark/proc/measure_atmos_cycles(prefix, cycles)
	begin_window()
	var/start_cycle = SSair.times_fired
	var/list/maxima = list(
		"active_turfs" = 0,
		"seed_turfs" = 0,
		"retained_turfs" = 0,
		"pending_turfs" = 0,
		"snapshot_mixtures" = 0,
		"published_mixtures" = 0,
		"compute_ms" = 0,
		"high_pressure_turfs" = 0,
		"equalized_turfs" = 0,
	)
	var/deadline = REALTIMEOFDAY + 3000
	while(SSair.times_fired < start_cycle + cycles)
		if(REALTIMEOFDAY > deadline)
			fail("SSair ran [SSair.times_fired - start_cycle]/[cycles] cycles in 300s")
		stoplag()
		maxima["active_turfs"] = max(maxima["active_turfs"], SSair.async_active_turfs)
		maxima["seed_turfs"] = max(maxima["seed_turfs"], SSair.async_seed_turfs)
		maxima["retained_turfs"] = max(maxima["retained_turfs"], SSair.async_retained_turfs)
		maxima["pending_turfs"] = max(maxima["pending_turfs"], SSair.async_pending_turfs)
		maxima["snapshot_mixtures"] = max(maxima["snapshot_mixtures"], SSair.async_snapshot_mixtures)
		maxima["published_mixtures"] = max(maxima["published_mixtures"], SSair.async_published_mixtures)
		maxima["compute_ms"] = max(maxima["compute_ms"], SSair.async_compute_cost)
		maxima["high_pressure_turfs"] = max(maxima["high_pressure_turfs"], SSair.high_pressure_turfs)
		maxima["equalized_turfs"] = max(maxima["equalized_turfs"], SSair.num_equalize_processed)
	end_window(prefix)
	metric("[prefix]_cycles", SSair.times_fired - start_cycle, "cycles", "none")
	for(var/key in maxima)
		metric("[prefix]_max_[key]", maxima[key], key == "compute_ms" ? "ms" : "count")
	record_atmos_arena(prefix)

/// Builds a walled width x width floor fixture on a fresh z-level and returns
/// its floor turfs. The wall ring keeps gas from venting into the level's space.
/datum/benchmark/proc/build_floor_fixture(width)
	var/fixture_z = world.maxz + 1
	world.maxz = fixture_z
	var/list/turf/open/turfs = list()
	for(var/x in 1 to width + 2)
		for(var/y in 1 to width + 2)
			var/turf/fixture_turf = locate(x, y, fixture_z)
			if(x == 1 || y == 1 || x == width + 2 || y == width + 2)
				fixture_turf.ChangeTurf(/turf/simulated/wall)
			else
				turfs += fixture_turf.ChangeTurf(/turf/simulated/floor)
			CHECK_TICK
	return turfs

/// Large atmospherics workload: a checkerboard of gas that has to equalize.
/datum/benchmark/atmos_large
	id = "atmos_large"
	description = "Checkerboard gas equalization over a large floor (bench_size, default 48; 0 = whole level)"

/datum/benchmark/atmos_large/Run()
	wait_for_assets()
	var/size = param("size", 48)
	if(size <= 0)
		size = min(world.maxx - 2, world.maxy - 2)
	var/list/turf/open/turfs = build_floor_fixture(size)
	for(var/turf/open/fixture_turf as anything in turfs)
		for(var/datum/gas/gas as anything in fixture_turf.air.get_gases())
			fixture_turf.air.set_moles(gas, 0)
		if((fixture_turf.x + fixture_turf.y) % 2)
			fixture_turf.air.set_moles(/datum/gas/oxygen, 500)
			fixture_turf.air.set_temperature(T20C)
		fixture_turf.air_update_turf(FALSE, FALSE)
	metric("atmos_large_turfs", length(turfs), "turfs", "none")
	measure_atmos_cycles("atmos_large", param("cycles", 120))
	mark("atmos_large_end")

/// Major events: explosions, supermatter, mass fire and decompression on a
/// fresh 64x64 fixture each. `bench_events` picks a comma-separated subset.
/datum/benchmark/major_events
	id = "major_events"
	description = "Tick cost of explosions, supermatter, mass fire and decompression"
	var/turf/open/event_center
	var/list/turf/open/event_turfs

/datum/benchmark/major_events/Destroy()
	event_center = null
	event_turfs = null
	return ..()

/datum/benchmark/major_events/Run()
	wait_for_assets()
	var/list/events = splittext(param("events", "large_explosion,supermatter,mass_fire,decompression"), ",")
	for(var/event_name in events)
		event_turfs = build_floor_fixture(64)
		var/turf/corner = event_turfs[1]
		event_center = locate(33, 33, corner.z)
		stoplag()
		switch(event_name)
			if("large_explosion")
				measure_event(event_name, CALLBACK(src, PROC_REF(trigger_large_explosion)))
			if("supermatter")
				measure_event(event_name, CALLBACK(src, PROC_REF(trigger_supermatter)))
			if("mass_fire")
				for(var/turf/open/T as anything in event_turfs)
					T.air.set_moles(/datum/gas/oxygen, 300)
					T.air.set_moles(/datum/gas/plasma, 100)
					T.air.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 100)
					T.air_update_turf(FALSE, FALSE)
				measure_event(event_name, CALLBACK(src, PROC_REF(trigger_mass_fire)))
			if("decompression")
				for(var/turf/open/T as anything in event_turfs)
					T.air.set_moles(/datum/gas/oxygen, 500)
					T.air.set_temperature(T20C)
					T.air_update_turf(FALSE, FALSE)
				measure_event(event_name, CALLBACK(src, PROC_REF(trigger_decompression)))
			else
				fail("unknown event '[event_name]'")

/datum/benchmark/major_events/proc/measure_event(event_name, datum/callback/trigger, atmos_cycles = 60)
	begin_window()
	var/start_cycle = SSair.times_fired
	trigger.Invoke()
	wait_fires(SSair, atmos_cycles - (SSair.times_fired - start_cycle))
	end_window(event_name)

/datum/benchmark/major_events/proc/trigger_large_explosion()
	explosion(event_center, 8, 16, 24, 32, FALSE, 0)

/datum/benchmark/major_events/proc/trigger_supermatter()
	var/obj/machinery/power/supermatter/crystal = new(event_center)
	crystal.pull_time = 0
	crystal.power = 5000
	crystal.explode()

/datum/benchmark/major_events/proc/trigger_mass_fire()
	for(var/turf/open/T as anything in event_turfs)
		if(T.x % 2 || T.y % 2)
			continue
		T.hotspot_expose(PLASMA_MINIMUM_BURN_TEMPERATURE + 500, CELL_VOLUME, TRUE)

/datum/benchmark/major_events/proc/trigger_decompression()
	for(var/turf/open/T as anything in event_turfs)
		if(T.x == 2 || T.y == 2)
			T.ChangeTurf(/turf/space)

/// Expedition generation: builds and releases generated sites, recording tick
/// cost and memory at each stage. `bench_cycles` > 1 is a leak soak.
/datum/benchmark/generation
	id = "generation"
	description = "Expedition station generation and release (bench_cycles, default 1)"
	var/datum/expedition_site/generated_site
	var/generation_done = FALSE

/datum/benchmark/generation/Destroy()
	generated_site = null
	return ..()

/datum/benchmark/generation/proc/generate(seed, list/diagnostics)
	try
		generated_site = SSexpedition.generate_debug_station(seed, diagnostics)
	catch(var/exception/error)
		diagnostics["error"] = "[error]"
	generation_done = TRUE

/datum/benchmark/generation/Run()
	wait_for_assets()
	var/cycles = param("cycles", 1)
	var/seed = param("seed", 900252288)
	for(var/cycle in 1 to cycles)
		mark("cycle[cycle]_begin")
		var/list/diagnostics = list()
		generated_site = null
		generation_done = FALSE
		begin_window()
		INVOKE_ASYNC(src, PROC_REF(generate), seed, diagnostics)
		var/deadline = REALTIMEOFDAY + 6000
		while(!generation_done)
			if(REALTIMEOFDAY > deadline)
				fail("generation did not finish within 600s on cycle [cycle]")
			stoplag()
		end_window("cycle[cycle]_generate")
		detail("cycle[cycle]_diagnostics", diagnostics)
		if(!generated_site)
			fail("generation returned no site on cycle [cycle]: [diagnostics["error"] || "no error"]")
		mark("cycle[cycle]_generated")
		SSexpedition.release_site(generated_site, "generation benchmark")
		generated_site = null
		var/waited = 0
		while((length(SSexpedition.teardown_z) || !length(SSexpedition.free_z)) && waited++ < world.fps * 180)
			stoplag()
		if(waited >= world.fps * 180)
			fail("expedition teardown did not return its z-level to the pool")
		wait_fires(SSair, 60)
		mark("cycle[cycle]_released")
		detail("cycle[cycle]_garbage", SSgarbage.performance_diagnostics())

/// Supermatter-scale destruction soak: detonates the station supermatter (or a
/// large bomb in a random station area) `bench_blasts` times, a minute apart,
/// then watches recovery long enough for the GC check queue to turn over. Meant
/// for Southern Cross (-DCITESTING_FULL_MAP). `bench_profile_types=1` adds
/// per-type machine and explosion cost attribution.
/datum/benchmark/sm_soak
	id = "sm_soak"
	description = "Repeated supermatter-scale blasts and recovery (bench_blasts, default 4)"

/datum/benchmark/sm_soak/Run()
	wait_for_assets()
	if(param("profile_types", 0))
		SSmachines.profile_machine_types = TRUE
		SSexplosions.profile_atom_types = TRUE
	mark("before")
	var/blasts = param("blasts", 4)
	var/list/drains = list()
	for(var/blast in 1 to blasts)
		begin_window()
		var/list/site = detonate()
		if(!site)
			fail("no supermatter and no open station turf to bomb")
		wait_seconds(10)
		// Open the blast site to space so decompression is part of the load.
		var/turf/epicenter = locate(site["x"], site["y"], site["z"])
		if(epicenter && !istype(epicenter, /turf/space))
			epicenter.ChangeTurf(/turf/space)
		var/sampled_at = 0
		for(var/delay in list(1, 5, 15, 30))
			wait_seconds(delay - sampled_at)
			sampled_at = delay
			drains += list(sample_drain(site, "blast[blast]", delay))
		wait_seconds(20)
		end_window("blast[blast]")
		mark("blast[blast]")
	var/recovered_for = 0
	for(var/checkpoint in list(60, 180, 320))
		begin_window()
		wait_seconds(checkpoint - recovered_for)
		recovered_for = checkpoint
		end_window("recovery[checkpoint]")
		mark("recovery[checkpoint]")
		if(SSmachines.profile_machine_types)
			SSmachines.dump_machine_profile()
	detail("drain_samples", drains)
	detail("garbage", SSgarbage.performance_diagnostics())

/// Blows up the supermatter if there is one, else bombs a station area.
/// Returns the epicenter as list(x, y, z, area).
/datum/benchmark/sm_soak/proc/detonate()
	for(var/obj/machinery/power/supermatter/crystal in world)
		var/turf/epicenter = get_turf(crystal)
		var/list/site = list("x" = epicenter.x, "y" = epicenter.y, "z" = epicenter.z, "area" = get_area(crystal))
		crystal.explode()
		return site
	var/list/station_areas = get_station_areas(list())
	while(length(station_areas))
		var/area/target_area = pick_n_take(station_areas)
		var/list/open_turfs = list()
		for(var/turf/open/T in target_area)
			open_turfs += T
		if(!length(open_turfs))
			continue
		var/turf/open/epicenter = pick(open_turfs)
		var/list/site = list("x" = epicenter.x, "y" = epicenter.y, "z" = epicenter.z, "area" = target_area)
		explosion(epicenter, 8, 16, 24, 32, TRUE)
		return site
	return null

/// Pressure across the atmosphere-connected component that contains the blast.
/// Area datums are shared by disconnected fragments, so a whole-area average
/// would make a spaced room look half pressurised.
/datum/benchmark/sm_soak/proc/sample_drain(list/site, label, delay)
	var/area/affected_area = site["area"]
	var/turf/open/epicenter = locate(site["x"], site["y"], site["z"])
	if(!istype(epicenter) || get_area(epicenter) != affected_area)
		return list("label" = label, "delay_s" = delay, "cells" = 0, "origin_missing" = TRUE)
	var/list/turfs_to_scan = list(epicenter)
	var/list/connected = list()
	connected[epicenter] = TRUE
	var/scan_index = 1
	while(scan_index <= length(turfs_to_scan))
		var/turf/open/current = turfs_to_scan[scan_index++]
		for(var/turf/open/neighbor as anything in current.atmos_adjacent_turfs)
			if(get_area(neighbor) != affected_area || connected[neighbor])
				continue
			connected[neighbor] = TRUE
			turfs_to_scan += neighbor
	var/count = 0
	var/vacuum = 0
	var/total = 0
	var/lowest = INFINITY
	var/highest = 0
	for(var/turf/open/cell as anything in connected)
		var/pressure = cell.return_air().return_pressure()
		count++
		total += pressure
		lowest = min(lowest, pressure)
		highest = max(highest, pressure)
		if(pressure < 5)
			vacuum++
	return list("label" = label, "delay_s" = delay, "area" = affected_area.name, "cells" = count, "avg_kpa" = count ? total / count : 0, "min_kpa" = count ? lowest : 0, "max_kpa" = highest, "vacuum_cells" = vacuum)

/// rust-g call dispatch: per-call cost of a cached load_ext() handle against
/// the by-name call_ext(RUST_G, "name") that code/__defines/rust_g.dm uses.
/// Both run in the same boot, alternating, five rounds each; the best round is
/// reported, because one busy tick on a loaded machine swamps the difference.
/// Run it before switching rust_g.dm to cached handles (see doc/testing.md).
/datum/benchmark/rustg_dispatch
	id = "rustg_dispatch"
	description = "Per-call cost of rust-g calls, cached handle vs by-name dispatch"

/datum/benchmark/rustg_dispatch/Run()
	var/calls = param("calls", 20000)
	var/rounds = param("rounds", 5)
	var/text = "The quick brown fox jumps over the lazy dog"
	var/json = "{\"a\":\[1,2,3\],\"b\":\"c\"}"
	var/log_file = "data/bench/rustg_dispatch.log"
	var/static/hash_handle = load_ext(RUST_G, "hash_string")
	var/static/json_handle = load_ext(RUST_G, "json_is_valid")
	var/static/log_handle = load_ext(RUST_G, "log_write")
	var/list/best = list()
	for(var/round in 1 to rounds)
		stoplag() // start each round on a fresh tick
		rustg_time_reset("rustg_dispatch")
		for(var/i in 1 to calls)
			RUSTG_CALL(RUST_G, "hash_string")(RUSTG_HASH_XXH64, text)
		best["hash_string_by_name_us"] = min(best["hash_string_by_name_us"] || INFINITY, rustg_time_microseconds("rustg_dispatch") / calls)
		stoplag()
		rustg_time_reset("rustg_dispatch")
		for(var/i in 1 to calls)
			call_ext(hash_handle)(RUSTG_HASH_XXH64, text)
		best["hash_string_cached_us"] = min(best["hash_string_cached_us"] || INFINITY, rustg_time_microseconds("rustg_dispatch") / calls)
		stoplag()
		rustg_time_reset("rustg_dispatch")
		for(var/i in 1 to calls)
			RUSTG_CALL(RUST_G, "json_is_valid")(json)
		best["json_is_valid_by_name_us"] = min(best["json_is_valid_by_name_us"] || INFINITY, rustg_time_microseconds("rustg_dispatch") / calls)
		stoplag()
		rustg_time_reset("rustg_dispatch")
		for(var/i in 1 to calls)
			call_ext(json_handle)(json)
		best["json_is_valid_cached_us"] = min(best["json_is_valid_cached_us"] || INFINITY, rustg_time_microseconds("rustg_dispatch") / calls)
		stoplag()
		rustg_time_reset("rustg_dispatch")
		for(var/i in 1 to calls)
			RUSTG_CALL(RUST_G, "log_write")(log_file, text, "false")
		best["log_write_by_name_us"] = min(best["log_write_by_name_us"] || INFINITY, rustg_time_microseconds("rustg_dispatch") / calls)
		stoplag()
		rustg_time_reset("rustg_dispatch")
		for(var/i in 1 to calls)
			call_ext(log_handle)(log_file, text, "false")
		best["log_write_cached_us"] = min(best["log_write_cached_us"] || INFINITY, rustg_time_microseconds("rustg_dispatch") / calls)
		fdel(log_file)
	for(var/name in best)
		metric(name, best[name], "us/call")
	if(call_ext(hash_handle)(RUSTG_HASH_XXH64, text) != RUSTG_CALL(RUST_G, "hash_string")(RUSTG_HASH_XXH64, text))
		fail("cached and by-name hash_string disagree")

/// Idle mob Life cost with mob hibernation off, then on (doc/mob_life_architecture.md §4.9).
/// Spawns idle mice (every system has a sleep rule, so they hibernate) and humans (partly
/// asleep until the physiology systems gain sleep rules) on a fixture, then measures SSmobs
/// with GLOB.mob_hibernation_enabled FALSE and TRUE.
/datum/benchmark/idle_mobs
	id = "idle_mobs"
	description = "Idle mob Life cost with mob hibernation off and on"

/datum/benchmark/idle_mobs/Run()
	wait_for_assets()
	var/list/turf/open/turfs = build_floor_fixture(param("width", 20))
	var/list/mob/living/mobs = list()
	var/mice = param("mice", 300)
	var/humans = param("humans", 40)
	var/cycles = param("cycles", 30)
	for(var/i in 1 to mice)
		var/mob/living/simple_mob/animal/passive/mouse/M = new(pick(turfs))
		benchmark_quiet_simple_mob(M)
		mobs += M
		CHECK_TICK
	for(var/i in 1 to humans)
		mobs += new /mob/living/carbon/human(pick(turfs))
		CHECK_TICK
	metric("idle_mobs_spawned", length(mobs), "mobs", "none")
	var/was_enabled = GLOB.mob_hibernation_enabled

	GLOB.mob_hibernation_enabled = FALSE
	for(var/mob/living/L as anything in mobs)
		L.life_wake(LIFE_SYS_ALL, "benchmark")
	wait_fires(SSmobs, SSmobs.life_slices * 2)
	begin_window()
	wait_fires(SSmobs, SSmobs.life_slices * cycles)
	end_window("hibernation_off")
	metric("hibernation_off_ssmobs_cost_ms", SSmobs.cost, "ms")
	metric("hibernation_off_hibernating", benchmark_count_hibernating(mobs), "mobs", "none")

	GLOB.mob_hibernation_enabled = TRUE
	wait_fires(SSmobs, SSmobs.life_slices * 4)
	begin_window()
	wait_fires(SSmobs, SSmobs.life_slices * cycles)
	end_window("hibernation_on")
	metric("hibernation_on_ssmobs_cost_ms", SSmobs.cost, "ms")
	metric("hibernation_on_hibernating", benchmark_count_hibernating(mobs), "mobs", "higher")
	var/list/awake_bits = list()
	for(var/mob/living/L as anything in mobs)
		if(!L.life_hibernating)
			awake_bits["[L.type]"] |= L.life_awake
	detail("hibernation_on_awake_bits_by_type", awake_bits)

	GLOB.mob_hibernation_enabled = was_enabled
	for(var/mob/living/L as anything in mobs)
		qdel(L)
		CHECK_TICK

/// Puts a simple mob's AI to sleep and opens its environment limits, so it idles without
/// reacting to the fixture's air.
/proc/benchmark_quiet_simple_mob(mob/living/simple_mob/M)
	M.ai_brain?.go_sleep()
	M.min_oxy = 0
	M.max_oxy = 0
	M.min_tox = 0
	M.max_tox = 0
	M.min_n2 = 0
	M.max_n2 = 0
	M.min_co2 = 0
	M.max_co2 = 0
	M.min_ch4 = 0
	M.max_ch4 = 0
	M.minbodytemp = 0
	M.maxbodytemp = INFINITY
	M.temperature_range = INFINITY

/// How many of `mobs` are hibernating.
/proc/benchmark_count_hibernating(list/mobs)
	. = 0
	for(var/mob/living/L as anything in mobs)
		if(L.life_hibernating)
			.++

/// Radiation: pulses from many sources over a walled fixture full of mobs and
/// insulating objects. Reports the time SSradiation spent inside pulses.
/datum/benchmark/radiation
	id = "radiation"
	description = "Radiation pulse cost: rays from 20 sources to mobs through walls (bench_rounds, default 30)"

/datum/benchmark/radiation/Run()
	wait_for_assets()
	var/list/turf/floors = build_floor_fixture(48)
	var/turf/corner = floors[1]
	var/fixture_z = corner.z
	// Interior walls and windows so rays have shielding to cross.
	for(var/y in 4 to 46)
		if(y % 6)
			var/turf/wall_turf = locate(18, y, fixture_z)
			wall_turf.ChangeTurf(/turf/simulated/wall)
			new /obj/structure/window/reinforced/full(locate(34, y, fixture_z))
	var/list/sources = list()
	for(var/i in 1 to 20)
		sources += new /obj/item/stack/material/steel(locate(3 + (i * 7) % 46, 3 + (i * 13) % 46, fixture_z))
	for(var/i in 1 to 120)
		var/mob/living/simple_mob/animal/passive/mouse/white/mouse = new(locate(3 + (i * 11) % 46, 3 + (i * 17) % 46, fixture_z))
		mouse.ai_brain?.go_sleep()
	var/rounds = param("rounds", 30)
	stoplag()
	var/cost_before = 0
	for(var/key in SSradiation.profile_source_cost_ms)
		cost_before += SSradiation.profile_source_cost_ms[key]
	var/pulses_before = SSradiation.profile_pulses_completed
	begin_window()
	for(var/round in 1 to rounds)
		for(var/atom/source as anything in sources)
			radiation_pulse(source, 14, 0.05, 10, 0, 1)
		var/deadline = REALTIMEOFDAY + 600
		while(length(SSradiation.processing))
			if(REALTIMEOFDAY > deadline)
				fail("radiation pulses did not drain within 60s")
			stoplag()
	end_window("radiation")
	var/cost_after = 0
	for(var/key in SSradiation.profile_source_cost_ms)
		cost_after += SSradiation.profile_source_cost_ms[key]
	var/pulses = SSradiation.profile_pulses_completed - pulses_before
	metric("radiation_pulses", pulses, "pulses", "none")
	metric("radiation_pulse_ms_total", cost_after - cost_before, "ms")
	metric("radiation_pulse_ms_each", pulses ? (cost_after - cost_before) / pulses : 0, "ms")
	detail("radiation_diagnostics", SSradiation.performance_diagnostics())
