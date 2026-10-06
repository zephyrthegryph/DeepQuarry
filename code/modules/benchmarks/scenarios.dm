// Benchmark scenarios. Add a scenario by subtyping /datum/benchmark with an
// `id`; options are read with param() from `bench_<name>` world parameters
// (the runner passes `--arg name=value`).

/// Records the Rust atmos arena counters as metrics under `prefix`.
/datum/benchmark/proc/record_atmos_arena(prefix)
	// Layout of vg_auxmos_diagnostics() (verdigris/domains/gas/src/lib.rs):
	// main mixtures live, main slots, pipe regions, pipe ports, registered turf
	// cells, gas frames, pending callbacks, heat frames, heat bodies, heat frame us.
	var/list/arena = vg_auxmos_diagnostics()
	if(!islist(arena) || length(arena) < 10)
		return
	count_metric("[prefix]_gas_mixtures", arena[1], "mixtures")
	count_metric("[prefix]_gas_slots", arena[2], "slots")
	count_metric("[prefix]_atmos_turfs", arena[5], "turfs")
	count_metric("[prefix]_pipe_regions", arena[3], "regions")
	detail("[prefix]_atmos_arena", arena)
	detail("[prefix]_gas_field", vg_gas_stats())

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
	benchmark_rust_mark("boot_memory settled")
	detail("rust_memory_marks", GLOB.benchmark_rust_marks)
	var/list/census = benchmark_census(param("top", 40))
	count_metric("instances_total", census["total"], "instances")
	for(var/root in census["by_root"])
		count_metric("instances_[root]", census["by_root"][root], "instances")
	detail("census_top_types", census["top_types"])
	// The full list walk visits every var of every datum; off unless asked
	// (--arg=var_lists=1), the sampled type estimate below covers it.
	if(param("var_lists", 0))
		var/list/var_lists = benchmark_var_lists(param("list_top", 60))
		count_metric("var_lists_total", var_lists["total"], "lists")
		count_metric("var_lists_empty", var_lists["empty"], "lists")
		count_metric("var_list_entries", var_lists["entries"], "entries")
		detail("var_lists_top", var_lists["top"])
	if(param("type_memory", 1))
		var/list/type_memory = benchmark_type_memory(param("memory_top", 20))
		metric("dm_estimated_mb", type_memory["total_est_mb"], "MB")
		detail("type_memory_top", type_memory["top"])
	var/list/types = benchmark_type_counts()
	for(var/kind in types)
		count_metric("types_[kind]", types[kind], "types")
	metric("init_seconds", Kernel.initializations_seconds, "s")
	metric("init_atmos_ms", SSair.init_time_ms, "ms")
	count_metric("booted_ffi_calls", __verdigris_ffi_calls, "calls")
	// Per-instance composition lists. Blueprints are per type; an item owns a list only
	// for an arbitrary mix (its build record's mix). Override lists are interned and shared.
	var/items = 0
	var/matter_lists = 0
	var/matter_entries = 0
	var/list/matter_owners = list()
	for(var/obj/item/I in world)
		items++
		var/list/mix = material_build_of(I)?.mix
		if(mix)
			matter_lists++
			matter_entries += length(mix)
			matter_owners["[I.type]"]++
		CHECK_TICK
	var/override_refs = 0
	var/list/override_lists = list()
	for(var/obj/O in world)
		var/list/overrides = material_build_of(O)?.overrides
		if(overrides)
			override_refs++
			if(!(overrides in override_lists))
				override_lists += list(overrides)
		CHECK_TICK
	count_metric("items_total", items, "instances")
	count_metric("item_matter_lists", matter_lists, "lists")
	count_metric("item_matter_entries", matter_entries, "entries")
	count_metric("material_override_refs", override_refs, "instances")
	count_metric("material_override_lists", length(override_lists), "lists")
	matter_owners = sortTim(matter_owners, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	if(length(matter_owners) > 20)
		matter_owners.Cut(21)
	detail("item_matter_owner_types", matter_owners)
	// OM handle slots: one per datum that was ever handed out a handle, freed when it is
	// deleted (or found collected on resolve). Count the live ones by target type.
	var/list/handle_targets = list()
	var/handle_slots = length(GLOB.om_handle_slots)
	var/live_handles = 0
	for(var/id in 1 to handle_slots)
		var/ref = GLOB.om_handle_slots[id]
		if(!ref)
			continue
		var/datum/target = locate(ref)
		if(isdatum(target) && target.om_hid == id)
			live_handles++
			handle_targets["[target.type]"]++
		CHECK_TICK
	count_metric("om_handle_slots", handle_slots, "slots")
	count_metric("om_handles_live", live_handles, "instances")
	handle_targets = sortTim(handle_targets, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	if(length(handle_targets) > 20)
		handle_targets.Cut(21)
	detail("om_handle_targets", handle_targets)

/// A quiet round: steady-state tick cost with nobody playing.
/datum/benchmark/idle
	id = "idle"
	description = "Idle round tick cost and overruns"
	default_scenario = TRUE

/datum/benchmark/idle/Run()
	wait_for_assets()
	begin_window()
	// Pure wait: no synthetic input, so idle compares like for like with builds from before the input record.
	// Input latency has its own scenario (`input`).
	wait_seconds(param("seconds", 60))
	end_window("idle")
	mark("idle_end")

/// Input latency on a quiet round: synthetic clicks and queued verbs every tick, so the input record (input_p99,
/// click/verb waits) has data on a world with no clients. Kept apart from `idle` so idle stays a pure wait.
/datum/benchmark/input
	id = "input"
	description = "Input latency with synthetic clicks and verbs every tick on an idle round"
	default_scenario = TRUE

/datum/benchmark/input/Run()
	wait_for_assets()
	begin_window()
	wait_seconds_with_input(param("seconds", 30), param("clicks", 2), param("verbs", 2))
	end_window("input")
	mark("input_end")

/// Atmospherics baseline: 120 SSair cycles of the mapped station, recording
/// Rust worker pressure alongside tick cost.
/datum/benchmark/atmos_idle
	id = "atmos_idle"
	description = "Atmospherics cost on the mapped station at rest"

/datum/benchmark/atmos_idle/Run()
	wait_for_assets()
	measure_atmos_cycles("atmos_idle", param("cycles", 120))

/// Runs `cycles` SSair cycles inside a window and records the gas field's
/// maxima and SSair's main-thread time.
/datum/benchmark/proc/measure_atmos_cycles(prefix, cycles)
	begin_window()
	var/start_cycle = SSair.times_fired
	var/list/stats_before = vg_gas_stats()
	var/list/maxima = list(
		"events" = 0,
		"reactions" = 0,
		"visuals" = 0,
		"pressure_pushes" = 0,
	)
	var/deadline = REALTIMEOFDAY + 3000
	while(SSair.times_fired < start_cycle + cycles)
		if(REALTIMEOFDAY > deadline)
			fail("SSair ran [SSair.times_fired - start_cycle]/[cycles] cycles in 300s")
		stoplag()
		maxima["events"] = max(maxima["events"], SSair.gas_events_last)
		maxima["reactions"] = max(maxima["reactions"], SSair.gas_reactions_last)
		maxima["visuals"] = max(maxima["visuals"], SSair.gas_visuals_last)
		maxima["pressure_pushes"] = max(maxima["pressure_pushes"], SSair.gas_pressure_last)
	end_window(prefix)
	var/list/stats_after = vg_gas_stats()
	count_metric("[prefix]_cycles", SSair.times_fired - start_cycle, "cycles", "none")
	count_metric("[prefix]_gas_commands", stats_after[2] - stats_before[2], "commands")
	count_metric("[prefix]_gas_frames_skipped", stats_after[13] - stats_before[13], "frames")
	metric("[prefix]_gas_last_frame_ms", stats_after[9] / 1000, "ms")
	for(var/key in maxima)
		count_metric("[prefix]_max_[key]", maxima[key], "count")
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
			heat_set(fixture_turf.air, T20C)
		fixture_turf.air_update_turf(FALSE, FALSE)
	count_metric("atmos_large_turfs", length(turfs), "turfs", "none")
	measure_atmos_cycles("atmos_large", param("cycles", 120))
	mark("atmos_large_end")

/// Major events: explosions, supermatter, mass fire and decompression on a
/// fresh 64x64 fixture each. `bench_events` picks a comma-separated subset.
/datum/benchmark/major_events
	id = "major_events"
	description = "Tick cost of explosions, supermatter, mass fire and decompression"
	var/tmp/turf/open/event_center
	/// The fixture floor: a turf relation list view (z release clears it).
	var/list/turf/open/event_turfs

/datum/benchmark/major_events/Run()
	wait_for_assets()
	var/list/events = splittext(param("events", "large_explosion,supermatter,mass_fire,decompression"), ",")
	for(var/event_name in events)
		rel_clear(src, nameof(event_turfs))
		for(var/turf/open/T as anything in build_floor_fixture(64))
			rel_add(src, nameof(event_turfs), T)
		var/turf/corner = event_turfs[1]
		rel_set(src, nameof(event_center), locate(33, 33, corner.z))
		stoplag()
		switch(event_name)
			if("large_explosion")
				measure_event(event_name, om_callable(src, PROC_REF(trigger_large_explosion)))
			if("supermatter")
				measure_event(event_name, om_callable(src, PROC_REF(trigger_supermatter)))
			if("mass_fire")
				for(var/turf/open/T as anything in event_turfs)
					T.air.set_moles(/datum/gas/oxygen, 300)
					T.air.set_moles(/datum/gas/plasma, 100)
					heat_set(T.air, PLASMA_MINIMUM_BURN_TEMPERATURE + 100)
					T.air_update_turf(FALSE, FALSE)
				measure_event(event_name, om_callable(src, PROC_REF(trigger_mass_fire)))
			if("decompression")
				for(var/turf/open/T as anything in event_turfs)
					T.air.set_moles(/datum/gas/oxygen, 500)
					heat_set(T.air, T20C)
					T.air_update_turf(FALSE, FALSE)
				measure_event(event_name, om_callable(src, PROC_REF(trigger_decompression)))
			else
				fail("unknown event '[event_name]'")

/datum/benchmark/major_events/proc/measure_event(event_name, list/trigger, atmos_cycles = 60)
	begin_window()
	var/start_cycle = SSair.times_fired
	om_run(trigger)
	wait_fires(SSair, atmos_cycles - (SSair.times_fired - start_cycle))
	end_window(event_name)

/datum/benchmark/major_events/proc/trigger_large_explosion()
	explosion(event_center(), 8, 16, 24, 32, FALSE, 0)

/datum/benchmark/major_events/proc/trigger_supermatter()
	var/obj/machinery/power/supermatter/crystal = new(event_center())
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
	var/tmp/datum/expedition_site/generated_site
	var/generation_done = FALSE

/datum/benchmark/generation/proc/generate(seed, list/diagnostics)
	try
		rel_set(src, nameof(generated_site), SSexpedition.generate_debug_station(seed, diagnostics))
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
		rel_clear(src, nameof(generated_site))
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
		if(!generated_site())
			fail("generation returned no site on cycle [cycle]: [diagnostics["error"] || "no error"]")
		mark("cycle[cycle]_generated")
		SSexpedition.release_site(generated_site(), "generation benchmark")
		rel_clear(src, nameof(generated_site))
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
	detail("drain_samples", drains)
	detail("garbage", SSgarbage.performance_diagnostics())

/// Blows up the supermatter if there is one, else bombs a station area.
/// Returns the epicenter as list(x, y, z, area).
/datum/benchmark/sm_soak/proc/detonate()
	for(var/obj/machinery/power/supermatter/crystal in world)
		var/turf/epicenter = get_turf(crystal)
		if(!epicenter)
			continue
		var/list/site = list("x" = epicenter.x, "y" = epicenter.y, "z" = epicenter.z, "area" = get_area(crystal))
		crystal.explode()
		return site
	var/list/station_areas = get_station_areas(list())
	while(length(station_areas))
		var/area/target_area = pick_n_take(station_areas)
		var/list/open_turfs = list()
		for(var/turf/open/T in area_contents_of_type(target_area, /turf/open))
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
	var/list/frontier = list(epicenter)
	var/list/connected = list()
	connected[epicenter] = TRUE
	// Breadth-first over Rust's adjacency, one batched read per ring.
	while(length(frontier))
		var/list/neighbor_lists = atmos_adjacent_turfs_bulk(frontier)
		frontier = list()
		for(var/list/neighbors as anything in neighbor_lists)
			for(var/turf/open/neighbor as anything in neighbors)
				if(get_area(neighbor) != affected_area || connected[neighbor])
					continue
				connected[neighbor] = TRUE
				frontier += neighbor
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
	var/static/hash_fn = load_ext(RUST_G, "hash_string")
	var/static/json_fn = load_ext(RUST_G, "json_is_valid")
	var/static/log_fn = load_ext(RUST_G, "log_write")
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
			call_ext(hash_fn)(RUSTG_HASH_XXH64, text)
		best["hash_string_cached_us"] = min(best["hash_string_cached_us"] || INFINITY, rustg_time_microseconds("rustg_dispatch") / calls)
		stoplag()
		rustg_time_reset("rustg_dispatch")
		for(var/i in 1 to calls)
			RUSTG_CALL(RUST_G, "json_is_valid")(json)
		best["json_is_valid_by_name_us"] = min(best["json_is_valid_by_name_us"] || INFINITY, rustg_time_microseconds("rustg_dispatch") / calls)
		stoplag()
		rustg_time_reset("rustg_dispatch")
		for(var/i in 1 to calls)
			call_ext(json_fn)(json)
		best["json_is_valid_cached_us"] = min(best["json_is_valid_cached_us"] || INFINITY, rustg_time_microseconds("rustg_dispatch") / calls)
		stoplag()
		rustg_time_reset("rustg_dispatch")
		for(var/i in 1 to calls)
			RUSTG_CALL(RUST_G, "log_write")(log_file, text, "false")
		best["log_write_by_name_us"] = min(best["log_write_by_name_us"] || INFINITY, rustg_time_microseconds("rustg_dispatch") / calls)
		stoplag()
		rustg_time_reset("rustg_dispatch")
		for(var/i in 1 to calls)
			call_ext(log_fn)(log_file, text, "false")
		best["log_write_cached_us"] = min(best["log_write_cached_us"] || INFINITY, rustg_time_microseconds("rustg_dispatch") / calls)
		fdel(log_file)
	for(var/name in best)
		metric(name, best[name], "us/call")
	if(call_ext(hash_fn)(RUSTG_HASH_XXH64, text) != RUSTG_CALL(RUST_G, "hash_string")(RUSTG_HASH_XXH64, text))
		fail("cached and by-name hash_string disagree")

/// Idle mob Life cost with parking off, then on (doc/rewrite/life_sequences.md §5).
/// Spawns idle mice (every step has a should_run, so they park) and humans on a fixture,
/// then measures the Life sequence with GLOB.seq_parking_enabled FALSE and TRUE.
/datum/benchmark/idle_mobs
	id = "idle_mobs"
	description = "Idle mob Life cost with mob hibernation off and on"

/datum/benchmark/idle_mobs/Run()
	wait_for_assets()
	var/list/turf/open/turfs = build_floor_fixture(param("width", 20))
	var/list/mob/living/mobs = list()
	var/mice = param("mice", 300)
	var/humans = param("humans", 40)
	var/cycles = param("cycles", 10)
	for(var/i in 1 to mice)
		var/mob/living/simple_mob/animal/passive/mouse/M = new(pick(turfs))
		benchmark_quiet_simple_mob(M)
		mobs += M
		CHECK_TICK
	for(var/i in 1 to humans)
		mobs += new /mob/living/carbon/human(pick(turfs))
		CHECK_TICK
	count_metric("idle_mobs_spawned", length(mobs), "mobs", "none")
	var/was_enabled = GLOB.seq_parking_enabled

	GLOB.seq_parking_enabled = FALSE
	for(var/mob/living/L as anything in mobs)
		seq_wake(L, /datum/sequence/life)
	wait_seconds(LIFE_CYCLE_SECONDS * 2)
	var/list/before = benchmark_life_totals(mobs)
	begin_window()
	wait_seconds(LIFE_CYCLE_SECONDS * cycles)
	end_window("hibernation_off")
	benchmark_life_metrics("hibernation_off", before, mobs)
	count_metric("hibernation_off_hibernating", benchmark_count_hibernating(mobs), "mobs", "none")

	GLOB.seq_parking_enabled = TRUE
	wait_seconds(LIFE_CYCLE_SECONDS * 4)
	before = benchmark_life_totals(mobs)
	begin_window()
	wait_seconds(LIFE_CYCLE_SECONDS * cycles)
	end_window("hibernation_on")
	benchmark_life_metrics("hibernation_on", before, mobs)
	count_metric("hibernation_on_hibernating", benchmark_count_hibernating(mobs), "mobs", "higher")
	var/list/awake = list()
	for(var/mob/living/L as anything in mobs)
		if(!seq_parked(L, /datum/sequence/life))
			awake["[L.type]"]++
	detail("hibernation_on_awake_by_type", awake)

	GLOB.seq_parking_enabled = was_enabled
	for(var/mob/living/L as anything in mobs)
		qdel(L)
		CHECK_TICK

/// The Life sequence's cumulative totals: its sweep's ms, the frames these mobs ran.
/proc/benchmark_life_totals(list/mobs)
	var/datum/sequence/S = sequence_def(/datum/sequence/life)
	return list(S.work.total_ms, seq_frames(mobs, /datum/sequence/life))

/// Life cost and delivered frames since `before` (benchmark_life_totals()).
/datum/benchmark/proc/benchmark_life_metrics(prefix, list/before, list/mobs)
	var/list/after = benchmark_life_totals(mobs)
	var/ms = after[1] - before[1]
	var/frames = after[2] - before[2]
	metric("[prefix]_life_ms", ms, "ms")
	metric("[prefix]_life_frames", frames, "frames", "none")
	metric("[prefix]_life_us_per_frame", frames ? ms * 1000 / frames : 0, "us")

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

/// How many of `mobs` are parked on the Life sequence.
/proc/benchmark_count_hibernating(list/mobs)
	. = 0
	for(var/mob/living/L as anything in mobs)
		if(seq_parked(L, /datum/sequence/life))
			.++

/// Radiation: pulses from many sources over a walled fixture full of mobs and
/// insulating objects. Reports the time the radiation service spent inside pulses.
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
	count_metric("radiation_pulses", pulses, "pulses", "none")
	metric("radiation_pulse_ms_total", cost_after - cost_before, "ms")
	metric("radiation_pulse_ms_each", pulses ? (cost_after - cost_before) / pulses : 0, "ms")
	detail("radiation_diagnostics", SSradiation.performance_diagnostics())

/// Where the memory outside DM objects goes (init_and_turfs.md §0.4). Counts
/// unique appearances (atoms' own and their overlay/underlay entries), icons,
/// images and mutable appearances.
/datum/benchmark/memory_breakdown
	id = "memory_breakdown"
	description = "Appearance counts and staged private-memory drops"

/datum/benchmark/memory_breakdown/proc/private_mb()
	var/list/process = benchmark_process_memory()
	return islist(process) ? process["private_mb"] : 0

/// Waits for the external sampler and BYOND's collector, then records.
/datum/benchmark/memory_breakdown/proc/stage(name)
	wait_seconds(param("settle", 8))
	var/mb = private_mb()
	metric("private_mb_[name]", mb, "MB")
	return mb

/datum/benchmark/memory_breakdown/Run()
	wait_for_assets()
	wait_fires(SSair, 5)
	var/base = stage("booted")
	var/list/own = list()
	var/list/overlay = list()
	var/atoms = 0
	var/overlay_refs = 0
	for(var/atom/A in world)
		atoms++
		own[ref(A.appearance)] = TRUE
		for(var/entry in A.overlays)
			overlay_refs++
			overlay[ref(entry)] = TRUE
		for(var/entry in A.underlays)
			overlay_refs++
			overlay[ref(entry)] = TRUE
		CHECK_TICK
	metric("atoms", atoms, "atoms", "none")
	metric("unique_atom_appearances", length(own), "appearances", "none")
	metric("overlay_underlay_refs", overlay_refs, "refs", "none")
	metric("unique_overlay_appearances", length(overlay), "appearances", "none")
	own = null
	overlay = null
	var/icons = 0
	for(var/icon/I)
		icons++
		CHECK_TICK
	var/images = 0
	for(var/image/I)
		images++
		CHECK_TICK
	var/mutables = 0
	for(var/mutable_appearance/M)
		mutables++
		CHECK_TICK
	metric("icon_objects", icons, "icons", "none")
	metric("image_objects", images, "images", "none")
	metric("mutable_appearances", mutables, "objects", "none")
	global_sizes()
	pool_probe()

	// Freeing things and watching private memory does not work: BYOND keeps
	// freed memory in its own pools (clearing every overlay and all
	// lighting moved private memory by +5 MB each). The growth through boot
	// is measured instead, from the per-subsystem marks (boot_profile).

/// Deep size of each GLOB var: list entries and datums reachable through
/// lists and datum list vars, each counted once across all globals, in
/// descending order. Private memory before world/New is mostly these.
/datum/benchmark/memory_breakdown/proc/global_sizes(top = 40)
	var/list/seen = list()
	var/list/sizes = list()
	for(var/name in GLOB.vars)
		var/value = GLOB.vars[name]
		if(!islist(value) && !istype(value, /datum))
			continue
		var/list/counts = list(0, 0)
		var/list/stack = list(value)
		while(length(stack))
			var/thing = stack[length(stack)]
			stack.len--
			var/key = ref(thing)
			if(seen[key])
				continue
			seen[key] = TRUE
			if(islist(thing))
				var/list/L = thing
				counts[1] += length(L)
				for(var/entry in L)
					if(islist(entry) || (istype(entry, /datum) && !isatom(entry)))
						stack += list(entry)
					if(!isnum(entry) && !isnull(entry))
						var/assoc = L[entry]
						if(islist(assoc) || (istype(assoc, /datum) && !isatom(assoc)))
							stack += list(assoc)
			else if(istype(thing, /datum) && !isatom(thing))
				var/datum/D = thing
				counts[2]++
				for(var/var_name in D.vars)
					var/v = D.vars[var_name]
					if(islist(v) && var_name != "vars")
						stack += list(v)
			CHECK_TICK
		if(counts[1] + counts[2] > 1000)
			sizes[name] = counts[1] * 12 + counts[2] * 64
			sizes["[name]:detail"] = "[counts[1]] entries, [counts[2]] datums"
	var/list/order = list()
	for(var/name in sizes)
		if(!findtext(name, ":detail"))
			order[name] = sizes[name]
	order = sortTim(order, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	var/list/out = list()
	var/total = 0
	for(var/name in order)
		total += order[name]
		if(length(out) < top)
			out[name] = "[round(order[name] / 1048576, 0.1)] MB est ([sizes["[name]:detail"]])"
	metric("globals_est_mb", total / 1048576, "MB", "none")
	detail("globals_top", out)

/// How much of private memory is free space inside BYOND's own pools:
/// allocates `count` lists of 20 numbers (about 180 bytes each, ~180 MB for a
/// million) and records how much private memory grew. Growth well under the
/// allocation means the pools already held that much free, reusable memory
/// (BYOND never returns freed memory to the OS, so private memory is a
/// high-water mark, not what is live).
/datum/benchmark/memory_breakdown/proc/pool_probe()
	var/count = param("probe_lists", 1000000)
	var/before = stage("probe_before")
	var/list/hold = new /list(count)
	for(var/i in 1 to count)
		hold[i] = list(1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20)
		if(!(i % 50000))
			CHECK_TICK
	var/after = stage("probe_after")
	metric("probe_allocated_mb_est", count * 184 / 1048576, "MB", "none")
	metric("probe_private_growth_mb", after - before, "MB", "none")
	hold = null

// Bisect aid (init_and_turfs.md §0.5): -DBISECT_EXTRA_PROCS adds 1,000 empty
// procs on /datum, to measure the per-type proc table cost on this codebase.
#ifdef BISECT_EXTRA_PROCS
#include "../../../tools/bisect/extra_procs.dm"
#endif

/// The event_center (a relation view).
/datum/benchmark/major_events/proc/event_center() as /turf/open
	return event_center

/// The generated_site (a relation view).
/datum/benchmark/generation/proc/generated_site() as /datum/expedition_site
	return generated_site

/// The fixture floor, rebuilt per event by Run().
// turfs, never freed

/// Compare actual research-console cache allocation before and after lazy-list changes.
/// Run separately on each revision: bench --scenario=rdconsole_id_cache --arg=consoles=200 --arg=ids=20 --arg=lookups=100.
/datum/benchmark/rdconsole_id_cache
	id = "rdconsole_id_cache"
	description = "Research consoles: untouched ID-cache allocation and actual payload deduplication"

/datum/benchmark/rdconsole_id_cache/Run()
	var/consoles_n = max(1, param("consoles", 200))
	var/ids_n = max(1, param("ids", 20))
	var/lookups_n = max(1, param("lookups", 100))
	var/list/consoles = list()
	var/list/ids = list()
	for(var/i in 1 to ids_n)
		ids += "benchmark-id-[i]"
	var/turf/T = locate(10, 10, 1)
	mark("before_consoles")
	begin_window()
	var/start = REALTIMEOFDAY
	for(var/i in 1 to consoles_n)
		consoles += new /obj/machinery/computer/rdconsole_tg(T)
	metric("console_allocation_ms", (REALTIMEOFDAY - start) * 100, "ms")
	end_window("console_allocation")
	mark("untouched_consoles")
	var/untouched_lists = 0
	var/untouched_entries = 0
	for(var/obj/machinery/computer/rdconsole_tg/console as anything in consoles)
		if(islist(console.id_cache))
			untouched_lists++
		untouched_entries += length(console.id_cache)
	count_metric("untouched_id_cache_lists", untouched_lists, "lists")
	count_metric("untouched_id_cache_entries", untouched_entries, "entries")
	begin_window()
	start = REALTIMEOFDAY
	var/mapping_errors = 0
	for(var/obj/machinery/computer/rdconsole_tg/console as anything in consoles)
		for(var/round in 1 to lookups_n)
			for(var/i in 1 to ids_n)
				if(console.compress_id(ids[i]) != i)
					mapping_errors++
	metric("deduplication_ms", (REALTIMEOFDAY - start) * 100, "ms")
	end_window("deduplication")
	mark("populated_consoles")
	var/populated_lists = 0
	var/populated_entries = 0
	for(var/obj/machinery/computer/rdconsole_tg/console as anything in consoles)
		if(islist(console.id_cache))
			populated_lists++
		populated_entries += length(console.id_cache)
	count_metric("populated_id_cache_lists", populated_lists, "lists")
	count_metric("populated_id_cache_entries", populated_entries, "entries")
	count_metric("deduplication_mapping_errors", mapping_errors, "errors")
	count_metric("consoles", consoles_n, "consoles")
	count_metric("distinct_ids_per_console", ids_n, "IDs")
	count_metric("compression_calls", consoles_n * lookups_n * ids_n, "calls")
	for(var/obj/machinery/computer/rdconsole_tg/console as anything in consoles)
		qdel(console)
	mark("after_console_cleanup")

/// Actual airlock histories before and after the lazy-list change. Run both revisions with identical parameters.
/datum/benchmark/airlock_history_lists
	id = "airlock_history_lists"
	description = "Actual airlocks: untouched history-list allocation and repeated ambient electrification"

/datum/benchmark/airlock_history_lists/Run()
	var/doors_n = max(1, param("doors", 200))
	var/entries_n = max(1, param("entries", 5))
	var/list/doors = list()
	var/turf/T = locate(10, 10, 1)
	mark("before_airlocks")
	begin_window()
	var/start = REALTIMEOFDAY
	for(var/i in 1 to doors_n)
		var/obj/machinery/door/airlock/door = new(T)
		door.set_stat(0)
		doors += door
	metric("airlock_allocation_ms", (REALTIMEOFDAY - start) * 100, "ms")
	end_window("airlock_allocation")
	mark("untouched_airlocks")
	var/untouched_lists = 0
	var/untouched_entries = 0
	for(var/obj/machinery/door/airlock/door as anything in doors)
		if(islist(door.shockedby))
			untouched_lists++
		untouched_entries += length(door.shockedby)
	count_metric("untouched_history_lists", untouched_lists, "lists")
	count_metric("untouched_history_entries", untouched_entries, "entries")
	begin_window()
	start = REALTIMEOFDAY
	for(var/obj/machinery/door/airlock/door as anything in doors)
		for(var/i in 1 to entries_n)
			door.electrify((2 SECONDS) / (1 SECOND))
	metric("electrification_history_ms", (REALTIMEOFDAY - start) * 100, "ms")
	end_window("electrification_history")
	mark("populated_airlocks")
	var/populated_lists = 0
	var/populated_entries = 0
	for(var/obj/machinery/door/airlock/door as anything in doors)
		if(islist(door.shockedby))
			populated_lists++
		populated_entries += length(door.shockedby)
	count_metric("populated_history_lists", populated_lists, "lists")
	count_metric("populated_history_entries", populated_entries, "entries")
	count_metric("expected_history_entries", doors_n * entries_n, "entries")
	count_metric("airlocks", doors_n, "airlocks")
	for(var/obj/machinery/door/airlock/door as anything in doors)
		qdel(door)
	mark("after_airlock_cleanup")

/// Actual living mobs and real incoming aim relationships, before/after lazy-list changes.
/datum/benchmark/aimed_relation_lists
	id = "aimed_relation_lists"
	description = "Living mobs: untouched incoming-aim lists and actual aim/cancel relationships"

/datum/benchmark/aimed_relation_lists/Run()
	var/mobs_n = max(1, param("mobs", 200))
	var/list/mobs = list()
	var/turf/T = locate(10, 10, 1)
	mark("before_mobs")
	begin_window()
	var/start = REALTIMEOFDAY
	for(var/i in 1 to mobs_n)
		mobs += new /mob/living/carbon/human(T)
	metric("mob_allocation_ms", (REALTIMEOFDAY - start) * 100, "ms")
	end_window("mob_allocation")
	mark("untouched_mobs")
	var/untouched_lists = 0
	var/untouched_entries = 0
	for(var/mob/living/M as anything in mobs)
		if(islist(M.aimed))
			untouched_lists++
		untouched_entries += length(M.aimed)
	count_metric("untouched_aimed_lists", untouched_lists, "lists")
	count_metric("untouched_aimed_entries", untouched_entries, "entries")
	var/mob/living/carbon/human/actor = new(T)
	var/obj/item/binoculars/tool = new(T)
	var/relationship_errors = 0
	if(!actor.put_in_active_hand(tool))
		relationship_errors++
	rel_set(actor, nameof(actor.aiming), new /obj/aiming_overlay(actor))
	var/obj/aiming_overlay/aim = actor.aiming
	begin_window()
	start = REALTIMEOFDAY
	var/populated_entries = 0
	for(var/mob/living/M as anything in mobs)
		aim.aim_at(M, tool)
		populated_entries += length(M.aimed)
		if(aim.aiming_at != M || !(aim in M.aimed))
			relationship_errors++
		actor.stop_aiming(tool, TRUE)
		if(length(M.aimed) || aim.aiming_at || aim.aiming_with())
			relationship_errors++
	metric("aim_cancel_ms", (REALTIMEOFDAY - start) * 100, "ms")
	end_window("aim_cancel")
	count_metric("observed_aim_entries", populated_entries, "entries")
	count_metric("expected_aim_entries", mobs_n, "entries")
	count_metric("relationship_errors", relationship_errors, "errors")
	mark("after_aim_cancel")
	qdel(actor)
	for(var/mob/living/M as anything in mobs)
		qdel(M)
	mark("after_mob_cleanup")

/// Actual cartridges and vendors before/after optional exception-list allocation.
/datum/benchmark/refill_exception_lists
	id = "refill_exception_lists"
	description = "Refill cartridges: unused exception lists and actual vendor compatibility"

/datum/benchmark/refill_exception_lists/Run()
	var/cartridges_n = max(1, param("cartridges", 200))
	var/lookups_n = max(1, param("lookups", 100))
	var/list/cartridges = list()
	var/turf/T = locate(10, 10, 1)
	mark("before_cartridges")
	begin_window()
	var/start = REALTIMEOFDAY
	for(var/i in 1 to cartridges_n)
		cartridges += new /obj/item/refill_cartridge/multitype/technical(T)
	metric("cartridge_allocation_ms", (REALTIMEOFDAY - start) * 100, "ms")
	end_window("cartridge_allocation")
	mark("untouched_cartridges")
	var/unused_lists = 0
	for(var/obj/item/refill_cartridge/multitype/C as anything in cartridges)
		if(islist(C.refill_exceptions))
			unused_lists++
	count_metric("unused_exception_lists", unused_lists, "lists")
	var/obj/item/refill_cartridge/multitype/clothing/clothing = new(T)
	var/obj/machinery/vending/tool/tools = new(T)
	var/obj/machinery/vending/wardrobe/wardrobe = new(T)
	var/obj/machinery/vending/loadout/gadget/gadget = new(T)
	var/matching_errors = 0
	begin_window()
	start = REALTIMEOFDAY
	for(var/obj/item/refill_cartridge/multitype/C as anything in cartridges)
		for(var/i in 1 to lookups_n)
			if(!C.can_refill(tools) || !C.can_refill(gadget) || C.can_refill(wardrobe))
				matching_errors++
			if(!clothing.can_refill(wardrobe) || clothing.can_refill(gadget) || clothing.can_refill(tools))
				matching_errors++
	metric("vendor_matching_ms", (REALTIMEOFDAY - start) * 100, "ms")
	end_window("vendor_matching")
	count_metric("matching_errors", matching_errors, "errors")
	count_metric("clothing_exception_entries", length(clothing.refill_exceptions), "entries")
	count_metric("cartridges", cartridges_n, "cartridges")
	count_metric("compatibility_checks", cartridges_n * lookups_n * 6, "checks")
	qdel(clothing)
	qdel(tools)
	qdel(wardrobe)
	qdel(gadget)
	for(var/obj/item/refill_cartridge/multitype/C as anything in cartridges)
		qdel(C)
	mark("after_cartridge_cleanup")

/// Untouched actual guest passes and the public list-alias contract on first read.
/datum/benchmark/guest_access_lists
	id = "guest_access_lists"
	description = "Guest passes: deferred empty access lists and stable access aliases"

/datum/benchmark/guest_access_lists/Run()
	var/passes_n = max(1, param("passes", 200))
	var/list/passes = list()
	var/turf/T = locate(10, 10, 1)
	mark("before_passes")
	begin_window()
	var/start = REALTIMEOFDAY
	for(var/i in 1 to passes_n)
		passes += new /obj/item/card/id/guest(T)
	metric("pass_allocation_ms", (REALTIMEOFDAY - start) * 100, "ms")
	end_window("pass_allocation")
	mark("untouched_passes")
	var/unused_lists = 0
	for(var/obj/item/card/id/guest/P as anything in passes)
		if(islist(P.temp_access))
			unused_lists++
	count_metric("untouched_temp_access_lists", unused_lists, "lists")
	var/alias_errors = 0
	var/read_lists = 0
	begin_window()
	start = REALTIMEOFDAY
	for(var/obj/item/card/id/guest/P as anything in passes)
		EXPIRY_SET(P, expiration_time, 1 MINUTE, CLOCK_WORLD)
		var/list/access = P.GetAccess()
		if(!islist(access) || !access || length(access))
			alias_errors++
		access += ACCESS_ENGINE
		if(P.GetAccess() != access || !(ACCESS_ENGINE in P.GetAccess()))
			alias_errors++
		if(islist(P.temp_access))
			read_lists++
	metric("access_alias_ms", (REALTIMEOFDAY - start) * 100, "ms")
	end_window("access_alias")
	count_metric("read_temp_access_lists", read_lists, "lists")
	count_metric("access_alias_errors", alias_errors, "errors")
	mark("after_access_reads")
	for(var/obj/item/card/id/guest/P as anything in passes)
		qdel(P)
	mark("after_pass_cleanup")

/// Actual shadekin variants: distinct constant tables and real ability grants.
/datum/benchmark/shadekin_ability_tables
	id = "shadekin_ability_tables"
	description = "Shadekin variant ability tables and actual source grants"

/datum/benchmark/shadekin_ability_tables/Run()
	var/mobs_n = max(1, param("mobs", 90))
	var/list/mobs = list()
	var/list/tables = list()
	var/list/variants = list(/datum/shadekin, /datum/shadekin/phase_only, /datum/shadekin/full)
	var/turf/T = locate(10, 10, 1)
	var/grant_errors = 0
	var/granted_entries = 0
	mark("before_shadekin")
	begin_window()
	var/start = REALTIMEOFDAY
	for(var/i in 1 to mobs_n)
		var/mob/living/carbon/human/H = new(T)
		mobs += H
		var/datum/shadekin/SK = H.add_shadekin(variants[((i - 1) % length(variants)) + 1])
		var/list/ids = SK.granted_ability_ids()
		var/table_seen = FALSE
		for(var/list/table as anything in tables)
			if(table == ids)
				table_seen = TRUE
		if(!table_seen)
			tables += list(ids)
		for(var/id in ids)
			granted_entries++
			if(!H.has_ability(id))
				grant_errors++
	metric("shadekin_allocation_ms", (REALTIMEOFDAY - start) * 100, "ms")
	end_window("shadekin_allocation")
	mark("populated_shadekin")
	count_metric("distinct_ability_tables", length(tables), "lists")
	count_metric("actual_granted_entries", granted_entries, "grants")
	count_metric("grant_errors", grant_errors, "errors")
	for(var/mob/living/carbon/human/H as anything in mobs)
		qdel(H)
	mark("after_shadekin_cleanup")
