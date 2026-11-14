#define PROFILE_STAGE_NATIVES 1
#define PROFILE_STAGE_SYSTEMS 2
#define PROFILE_STAGE_ATTRIBUTION 3
#define PROFILE_STAGE_LEDGER 4
#define PROFILE_STAGE_ENCODE 5
#define PROFILE_STAGE_WRITE 6
/// Ms of a table walk in one turn of a sample.
#define PROFILE_WALK_SLICE_MS 1.5
/// A turn of a sample longer than this is counted and named in the sample's summary line (a native call or one section's JSON cannot be cut).
#define PROFILE_TURN_CAP_MS 5
/// A turn is put off to the next tick, up to this many times a sample, when the tick it would run in is already over the kernel's budget.
#define PROFILE_MAX_DEFERRALS 40

SYSTEM_DEF(profiler)
	name = "Profiler"
	phase = KERNEL_PHASE_K
	latency_class = LATENCY_L0
	init_stage = INITSTAGE_FIRST
	periodic_runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY
	wait = 1 MINUTES
	var/fetch_cost = 0
	var/write_cost = 0
	/// Monotonic identifier for compact diagnostic snapshots. This profiler is
	/// intentionally independent of BYOND's expensive full proc serializer.
	var/diagnostic_sequence = 0
	/// The sample being built across ticks (sample_advance()).
	var/datum/profile_sample/building
	/// The last finished sample's record (the JSON of PERF_PROFILE) and how many turns it took.
	var/last_record
	var/last_turns = 0

/datum/system/profiler/stat_entry(msg)
	msg += "F:[round(fetch_cost,1)]ms"
	msg += "|W:[round(write_cost,1)]ms"
	return msg

/datum/system/profiler/initialize()
	#ifdef BENCHMARK
	// `bench --profile`: profile the rest of boot too (Profiler initializes in
	// INITSTAGE_FIRST, before map load); boot_profile dumps it.
	var/bench_profile = text2num(world.params?["bench_profile"] || "0")
	#else
	var/bench_profile = FALSE
	#endif
	#ifdef UNIT_TESTS
	// `-params boot_profile=1`: profile the rest of boot; the unit-test suite dumps it to <log dir>/boot_profile.json when it starts.
	if(text2num(world.params?["boot_profile"] || "0"))
		bench_profile = TRUE
	#endif
	if(CONFIG_GET(flag/auto_profile) || bench_profile)
		StartProfiling()
	else
		StopProfiling() //Stop the early start profiler
	apply_interval()
	// AUTO_PROFILE controls full world.Profile collection only. Compact subsystem
	// diagnostics are cheap, bounded, and must continue even when it is disabled.
	set_can_fire(TRUE)
	return

/datum/system/profiler/OnConfigLoad()
	if(CONFIG_GET(flag/auto_profile))
		StartProfiling()
	else
		StopProfiling()
	set_can_fire(TRUE)
	apply_interval()

/// The compact diagnostics record (phase K, one run per `wait`: the item is declared at the default and takes the configured
/// interval at boot and on a config reload).
/datum/system/profiler/reactions()
	. = ..()
	. += every(1 MINUTES, PROC_REF(sample), phase = KERNEL_PHASE_K, when = PROC_REF(work_ready), lane = LANE_URGENT)

/// Applies the configured sample interval to the work item.
/datum/system/profiler/proc/apply_interval()
	wait = CONFIG_GET(number/profiler_interval)
	set_work_interval(PROC_REF(sample), wait)

/// One sample being built. A sample is the compact diagnostics record (PERF_PROFILE): reading the natives, the systems' counters, the attribution table and the
/// ledger, then the JSON of each section. The whole of it held one tick for 80-500 ms every minute (debug.log PROFILER SAMPLE, 2026-11-13), so each stage runs
/// in its own tick and the two table walks take a few ms a tick (km_attr.walk_step(), km_ledger.walk_step()).
/datum/profile_sample
	var/stage = PROFILE_STAGE_NATIVES
	var/started_real = 0
	/// Ms spent in the turns added up, the dearest single turn, and how many turns there were.
	var/build_ms = 0
	var/max_turn_ms = 0
	var/turns = 0
	var/list/atmos_arena
	var/list/rust_allocator
	var/list/rust_metrics
	var/list/subsystems
	var/datum/km_attr_walk/attr_walk
	var/datum/km_ledger_walk/ledger_walk
	var/list/attribution
	var/list/ledger
	/// The sections still to encode (key -> value), and the JSON pieces so far ("key":<json>).
	var/list/sections
	var/list/encoded
	var/atmos_json
	var/alloc_json
	var/sequence = 0
	var/native_ms = 0
	var/walk_ms = 0
	var/write_ms = 0
	var/encode_ms = 0
	/// The turns past PROFILE_TURN_CAP_MS (and the stage of the dearest), the turns put off to a calmer tick, and the part of a stage already done (a stage of several native calls runs one a turn).
	var/over_cap_turns = 0
	var/max_turn_stage = 0
	var/deferrals = 0
	var/substep = 1

CAPABILITIES(/datum/system/profiler)
	owns_one(nameof(building), /datum/profile_sample)

CAPABILITIES(/datum/profile_sample)
	owns_one(nameof(attr_walk), /datum/km_attr_walk)
	owns_one(nameof(ledger_walk), /datum/km_ledger_walk)

/datum/system/profiler/proc/sample(dt)
	// Full BYOND profile serialization is synchronous and can itself overrun a tick.
	// Periodic collection therefore records only the inexpensive native diagnostics;
	// profile dumps are requested explicitly or by the MC drift outlier detector.
	if(building)
		log_world("PROFILER SAMPLE: the sample before is still being built (stage [building.stage] after [building.turns] turn(s)); this one is skipped")
		return
	rel_set(src, nameof(building), new /datum/profile_sample)
	building.started_real = REALTIMEOFDAY
	sample_advance(FALSE)

/// A whole sample at once, for tests: every stage runs in this call.
/datum/system/profiler/proc/sample_now()
	rel_set(src, nameof(building), new /datum/profile_sample)
	building.started_real = REALTIMEOFDAY
	sample_advance(TRUE)

/// The next turn of the sample being built.
/datum/system/profiler/proc/sample_continue()
	if(building)
		sample_advance(FALSE)

/// Runs turns of the sample: one (a stage, or a slice of a table walk) per tick, or every one at once when `sync`.
/datum/system/profiler/proc/sample_advance(sync)
	var/datum/profile_sample/S = building
	// A tick already over its budget gets none of the sample: the turn waits for the next one (a bounded number of times, so a sample still finishes).
	if(!sync && S.deferrals < PROFILE_MAX_DEFERRALS && KERNEL_OVER_BUDGET)
		S.deferrals++
		after(src, 1 TICKS, PROC_REF(sample_continue), key = "profile_sample")
		return
	while(S.stage <= PROFILE_STAGE_WRITE)
		var/turn_started = TICK_USAGE_REAL
		var/turn_stage = S.stage
		var/done = sample_stage(S)
		var/turn_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - turn_started)
		S.build_ms += turn_ms
		S.turns++
		if(turn_ms > S.max_turn_ms)
			S.max_turn_ms = turn_ms
			S.max_turn_stage = turn_stage
		if(turn_ms > PROFILE_TURN_CAP_MS)
			S.over_cap_turns++
		if(done)
			S.stage++
		if(!sync && S.stage <= PROFILE_STAGE_WRITE)
			after(src, 1 TICKS, PROC_REF(sample_continue), key = "profile_sample")
			return
	rel_clear(src, nameof(building))

/// One turn of the sample's current stage. TRUE when the stage is complete.
/datum/system/profiler/proc/sample_stage(datum/profile_sample/S)
	switch(S.stage)
		if(PROFILE_STAGE_NATIVES)
			// Three native calls, one a turn (each is one call that cannot be cut).
			var/natives_started = TICK_USAGE_REAL
			switch(S.substep)
				if(1)
					S.atmos_arena = vg_auxmos_diagnostics()
				if(2)
					S.rust_allocator = vg_verdigris_allocator_diagnostics()
				else
					// Every Rust metric (allocator tags, jobs, ...) in one call.
					S.rust_metrics = verdigris_metrics_list()
			S.native_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - natives_started)
			if(S.substep++ < 3)
				return FALSE
			S.substep = 1
			return TRUE
		if(PROFILE_STAGE_SYSTEMS)
			S.subsystems = sample_subsystems()
			return TRUE
		if(PROFILE_STAGE_ATTRIBUTION)
			// Inside sched_core / appearance_drain: top 20 callbacks, top 20 redrawn types, and the post-init settle table (attribution.dm).
			var/datum/km_attr/attr = km_meter().attr
			if(!S.attr_walk)
				rel_set(S, nameof(S.attr_walk), attr.walk_begin(20))
			var/walk_started = TICK_USAGE_REAL
			var/walked = attr.walk_step(S.attr_walk, PROFILE_WALK_SLICE_MS)
			if(walked)
				S.attribution = attr.walk_result(S.attr_walk)
				rel_clear(S, nameof(S.attr_walk))
			S.walk_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - walk_started)
			return walked
		if(PROFILE_STAGE_LEDGER)
			// Every ms of the kernel's iteration by category with its heaviest names, and what BYOND spent outside it (measure/ledger.dm).
			var/datum/km_ledger/ledger = GLOB.km_ledger
			if(!S.ledger_walk)
				rel_set(S, nameof(S.ledger_walk), ledger.walk_begin(KM_LEDGER_TOP))
			var/walk_started = TICK_USAGE_REAL
			var/walked = ledger.walk_step(S.ledger_walk, PROFILE_WALK_SLICE_MS)
			if(walked)
				S.ledger = ledger.walk_result(S.ledger_walk)
				// "outside" is the mean since boot: this is the same section over the window since the sample before.
				var/list/outside = S.ledger["outside"]
				outside += ledger.outside_since_mark()
				rel_clear(S, nameof(S.ledger_walk))
			S.walk_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - walk_started)
			return walked
		if(PROFILE_STAGE_ENCODE)
			// The JSON of one section per turn: rust_metrics and the systems' counters are most of it.
			var/encode_started = TICK_USAGE_REAL
			if(!S.sections)
				S.sequence = ++diagnostic_sequence
				S.sections = list(
					"subsystems" = S.subsystems,
					"atmos_arena" = S.atmos_arena,
					"rust_allocator" = S.rust_allocator,
					"rust_metrics" = S.rust_metrics,
					"attribution" = S.attribution,
					"ledger" = S.ledger,
				)
				// world.cpu / world.tick_usage are the whole server tick (DM code). The map
				// send cost (appearance/turf/obj changes pushed to clients) is world.map_cpu
				// only; with no clients it is ~0. Earlier profiles logged world.cpu and
				// world.tick_usage under the map_* names, which read as idle map churn.
				LAZYADD(S.encoded, "\"sequence\":[S.sequence]")
				LAZYADD(S.encoded, "\"world_time_ds\":[json_encode(TIME_NOW(CLOCK_WORLD))]")
				LAZYADD(S.encoded, "\"players\":[length(GLOB.clients)]")
				LAZYADD(S.encoded, "\"cpu\":[json_encode(world.cpu)]")
				LAZYADD(S.encoded, "\"tick_usage\":[json_encode(world.tick_usage)]")
				LAZYADD(S.encoded, "\"map_cpu\":[json_encode(world.map_cpu)]")
				LAZYADD(S.encoded, "\"initialized\":[json_encode(Kernel.initializations_seconds > 0)]")
				LAZYADD(S.encoded, "\"sleep_offline\":[json_encode(world.sleep_offline)]")
				S.encode_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - encode_started)
				return FALSE
			var/key = S.sections[1]
			var/json = json_encode(S.sections[key])
			S.sections.Cut(1, 2)
			LAZYADD(S.encoded, "\"[key]\":[json]")
			if(key == "atmos_arena")
				S.atmos_json = json
			else if(key == "rust_allocator")
				S.alloc_json = json
			S.encode_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - encode_started)
			return !length(S.sections)
		if(PROFILE_STAGE_WRITE)
			// The three log lines, one a turn; the summary goes with the last.
			var/write_started = TICK_USAGE_REAL
			switch(S.substep)
				if(1)
					last_record = "{[jointext(S.encoded, ",")]}"
					last_turns = S.turns + 1
					log_runtime("PERF_PROFILE [last_record]")
				if(2)
					// Keep the stable specialized records consumed by existing benchmark tools.
					log_runtime("ATMOS_PROFILE [S.atmos_json]")
				else
					log_runtime("RUST_ALLOC_PROFILE [S.alloc_json]")
			S.write_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - write_started)
			if(S.substep++ < 3)
				return FALSE
			logger.Log(LOG_CATEGORY_DEBUG, "PROFILER SAMPLE: native reads [round(S.native_ms, 0.1)] ms, systems and tables [round(S.build_ms - S.native_ms - S.encode_ms - S.write_ms, 0.1)] ms (the attribution and ledger walks [round(S.walk_ms, 0.1)] of them), encode [round(S.encode_ms, 0.1)] ms, write [round(S.write_ms, 0.1)] ms, in [S.turns] turn(s) over [round((REALTIMEOFDAY - S.started_real) / 10, 0.1)] s, the dearest turn [round(S.max_turn_ms, 0.1)] ms (stage [S.max_turn_stage]), [S.over_cap_turns] turn(s) past [PROFILE_TURN_CAP_MS] ms, [S.deferrals] put off to a calmer tick")
			return TRUE
	return TRUE

/// The systems' counters as the profile records them.
/datum/system/profiler/proc/sample_subsystems()
	var/list/subsystems = list(
		"atmos" = system_diagnostics(SSair),
		"machines" = system_diagnostics(SSmachines),
		"mobs" = system_diagnostics(SSmobs),
		"garbage" = system_diagnostics(SSgarbage),
		"shuttles" = system_diagnostics(SSshuttles),
		"radiation" = system_diagnostics(SSradiation),
		"explosions" = system_diagnostics(SSexplosions),
	)
	var/list/material_graphs = list()
	for(var/id in machines_power_material_overlays())
		var/datum/material_power_overlay/overlay = machines_power_material_overlays()[id]
		var/datum/material_power_graph/graph = overlay.material_graph
		if(graph)
			material_graphs += list(list("cables" = length(overlay.cables), "vertices" = length(graph.vertices), "core" = length(graph.core_vertices), "edges" = length(graph.edges), "iterations" = graph.iterations, "solve_ms" = graph.solve_ms, "deposit_ms" = graph.deposit_ms, "resistance_ms" = graph.resistance_ms))
	subsystems["machines"] += list("material_graphs" = material_graphs)
	subsystems["atmos"] += list(
		"dm_stage_average_ms" = list(
			"high_pressure" = air_profile_cost_highpressure(),
			"superconductivity" = air_profile_cost_superconductivity(),
			"pipenets" = air_profile_cost_pipenets(),
			"pipe_commit" = air_profile_cost_pipe_commit(),
			"pipe_devices" = air_profile_cost_pipe_devices(),
			"rebuilds" = air_profile_cost_rebuilds(),
			"gas_tick" = air_profile_cost_turfs(),
		),
		"gas_field" = vg_gas_stats(),
		"gas_last_fire" = list(
			"events" = air_profile_gas_events_last(),
			"reactions" = air_profile_gas_reactions_last(),
			"visuals" = air_profile_gas_visuals_last(),
			"pressure_pushes" = air_profile_gas_pressure_last(),
		),
		"queues" = list(
			"hotspots" = REGISTRY_COUNT(REGISTRY_HOTSPOTS),
			"pressure_deltas" = SSair.high_pressure_delta_count(),
			"pipenets" = SSair.pipenet_count(),
			"pipe_devices" = air_profile_rust_pipe_device_count(),
			"pipe_devices_reported" = native_system().pipe_devices_last,
			"rebuild" = SSair.rebuild_queue_count(),
			"expansion" = SSair.expansion_queue_count(),
		),
	)
	subsystems["machines"] += list(
		"stage_average_ms" = list("machinery" = machine_profile_cost_machinery(), "powernets" = machine_profile_cost_powernets()),
		"stage_last_logical_run_ms" = list("machinery" = machine_profile_last_cost_machinery(), "powernets" = machine_profile_last_cost_powernets()),
		"pump_commit" = list("active_ms" = machine_profile_last_pump_commit_ms(), "wall_ms" = machine_profile_last_pump_commit_wall_ms(), "suspended_ms" = machine_profile_last_pump_commit_suspended_ms(), "operations" = machine_profile_last_pump_commit_operations(), "turfs" = machine_profile_last_pump_commit_turfs()),
		"power" = list("regions" = length(machines_power_grids())),
		"counts" = list("all" = length(REGISTRY_MEMBERS(REGISTRY_MACHINES)), "powernets" = length(machines_power_grids())),
		"gas_wakes" = list("woken" = machine_profile_gas_woken_last()),
	)
	subsystems["mobs"] += list("counts" = list("world" = REGISTRY_COUNT(REGISTRY_MOBS), "parked" = members_total(sequence_def(/datum/sequence/life).parked_key), "deaths_pending" = length(mobs_death_list())))
	subsystems["garbage"] += SSgarbage.performance_diagnostics()
	subsystems["shuttles"] += SSshuttles.performance_diagnostics()
	subsystems["radiation"] += SSradiation.performance_diagnostics()
	subsystems["explosions"] += SSexplosions.performance_diagnostics()
	// Rust world wakes (timers, keys, rate crossings, native watches) on the scheduler.
	subsystems["world_step"] = world_diagnostics()
	return subsystems

/// The diagnostics readout of a missing subsystem or service (shared; only encoded).
GLOBAL_LIST_INIT(profiler_missing_diagnostics, list("missing" = TRUE))

/// The readout of a system that runs periodic work (the counters the kernel keeps for it; the rest read 0).
/datum/system/profiler/proc/system_diagnostics(datum/system/target)
	if(!target)
		return GLOB.profiler_missing_diagnostics
	return list(
		"name" = target.name,
		"active_ema_ms" = target.fire_cost,
		"wall_ema_ms" = target.fire_cost,
		"last_wall_ms" = target.run_ms,
		"last_active_ms" = target.run_ms,
		"last_suspended_ms" = 0,
		"last_slices" = target.ticks,
		"tick_usage" = 0,
		"tick_overrun" = target.tick_overrun,
		"allocation_last" = 0,
		"allocation_average" = 0,
		"completed_runs" = target.times_fired,
		"paused_ticks" = 0,
		"slept_count" = 0,
		"postponed_fires" = 0,
		"state" = null,
	)

/datum/system/profiler/on_shutdown()
	if(CONFIG_GET(flag/auto_profile))
		DumpFile(allow_yield = FALSE)
		world.Profile(PROFILE_CLEAR, type = "sendmaps")
	return ..()

/datum/system/profiler/proc/StartProfiling()
	world.Profile(PROFILE_START)
	world.Profile(PROFILE_START, type = "sendmaps")

/datum/system/profiler/proc/StopProfiling()
	world.Profile(PROFILE_STOP)
	world.Profile(PROFILE_STOP, type = "sendmaps")

/datum/system/profiler/proc/DumpFile(allow_yield = TRUE)
	var/timer = TICK_USAGE_REAL
	var/current_profile_data = world.Profile(PROFILE_REFRESH, format = "json")
	var/current_sendmaps_data = world.Profile(PROFILE_REFRESH, type = "sendmaps", format="json")
	fetch_cost = KERNEL_AVERAGE(fetch_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))
	if(allow_yield)
		CHECK_TICK

	if(!length(current_profile_data)) //Would be nice to have explicit proc to check this
		stack_trace("Warning, profiling stopped manually before dump.")
	var/prof_file = file("[GLOB.log_directory]/profiler/profiler-[round(world.time)].json")
	if(fexists(prof_file))
		fdel(prof_file)
	if(!length(current_sendmaps_data)) //Would be nice to have explicit proc to check this
		stack_trace("Warning, sendmaps profiling stopped manually before dump.")
	var/sendmaps_file = file("[GLOB.log_directory]/profiler/sendmaps-[round(world.time)].json")
	if(fexists(sendmaps_file))
		fdel(sendmaps_file)

	timer = TICK_USAGE_REAL
	WRITE_FILE(prof_file, current_profile_data)
	WRITE_FILE(sendmaps_file, current_sendmaps_data)
	write_cost = KERNEL_AVERAGE(write_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))

/// Every Rust metric (counters, gauges, histograms; see verdigris/ffi/src/metrics.rs)
/// from one verdigris call, decoded, or null if the library did not answer.
/// The Rust metrics whose names start with `prefix` (one family: "frame."), decoded, or null. No sampled gauge is refreshed and nothing DM-side
/// rides along: the cheap read for a report that runs inside a stalled tick.
/proc/verdigris_metrics_family(prefix)
	var/text = vg_verdigris_metrics_prefixed(prefix)
	if(!istext(text) || !length(text))
		return null
	var/list/decoded
	try
		decoded = json_decode(text)
	catch // ALLOW(silent_catch): malformed input is the expected failure; the caller handles null
		return null
	return decoded

/// The Rust metrics of every family in `prefixes`, after refreshing the sampled gauges (allocator, jobs, FFI counts, the world's laws and fields),
/// decoded, or null: the MC Health panel's read, about once a second while it is open.
/proc/verdigris_metrics_panel(list/prefixes)
	var/text = vg_verdigris_metrics_panel(jointext(prefixes, ","))
	if(!istext(text) || !length(text))
		return null
	return safe_json_decode(text)

/proc/verdigris_metrics_list()
	var/text = vg_verdigris_metrics()
	if(!istext(text) || !length(text))
		return null
	var/list/decoded
	try
		decoded = json_decode(text)
	catch // ALLOW(silent_catch): malformed input is the expected failure; the caller handles null
		return null
	// DM-side counters ride along: deliveries through native_changed() and errors per bind.
	if(islist(decoded))
		var/list/deliveries = native_delivery_stats()
		for(var/name in deliveries)
			decoded[name] = deliveries[name]
		for(var/bind in GLOB.vg_bind_errors)
			decoded["dm.errors.[bind]"] = GLOB.vg_bind_errors[bind]
	return decoded
