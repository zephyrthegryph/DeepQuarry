/**
 * The kernel's host state: the boot sequence (boot_systems(): the init DAG over the systems), the run level, the tick budget,
 * the performance record, the admin overview and the values the rest of the game reads off `Kernel` (iteration, last_run,
 * sleep_delta, tickdrift, current_ticklimit, current_runlevel, processing, init_stage_completed, ...), which the host loop
 * (loop.dm) keeps up to date. There is no Master Controller and no subsystem: the kernel is the one loop, and what it hosts
 * is systems (code/controllers/kernel/system.dm).
 **/

// See initialization order in /code/game/world.dm
GLOBAL_REAL(Kernel, /datum/controller/kernel)
/datum/controller/kernel
	name = "Kernel"

	/// Are we processing (higher values increase the processing delay by n ticks)
	var/processing = TRUE
	/// How many times have we ran
	var/iteration = 0
	/// world.time of last fire, for tracking lag outside of the mc
	var/last_run

	///Most recent init stage to complete init.
	var/static/init_stage_completed

	// Vars for keeping track of tick drift.
	var/init_timeofday
	var/init_time
	/// Wall-clock seconds the last full system initialization took.
	var/initializations_seconds = 0
	var/tickdrift = 0
	/// Tickdrift as of last tick, w no averaging going on
	var/olddrift = 0

	/// How long is the loop sleeping between runs, read only (set by the kernel loop off of anti-tick-contention heuristics)
	var/sleep_delta = 1
	/// Run only the phase K work for the next n ticks (a laggy map update is coming).
	var/skip_ticks = 0

	/// makes the mc main loop runtime
	var/make_runtime = FALSE

	var/initializations_finished_with_no_players_logged_in //I wonder what this could be?

	var/map_loading = FALSE //!Are we loading in a new map?
	/// Map loads placing right now (a sync load can run while a job load is between chunks).
	var/map_loading_depth = 0

	var/current_runlevel //!for scheduling different systems for different stages of the round
	var/sleep_offline_after_initializations = TRUE

	/// During initialization, the system that is currently initializing. Outside of initialization, null.
	var/datum/system/current_initializing = null

	/// The last decisecond we force dumped profiling information
	/// Used to avoid spamming profile reads since they can be expensive (string memes)
	var/last_profiled = 0

	var/static/random_seed

	///current tick limit, assigned before running a subsystem.
	///used by CHECK_TICK as well so that the procs subsystems call can obey that SS's tick limits
	var/static/current_ticklimit = TICK_LIMIT_RUNNING

	/// Whether the Overview UI will update as fast as possible for viewers.
	var/overview_fast_update = FALSE
	/// Enables rolling usage averaging
	var/use_rolling_usage = FALSE
	/// How long to run our rolling usage averaging
	var/rolling_usage_length = 5 SECONDS

	/// Bounded per-MC-tick history used by the admin performance dashboard.
	var/list/perf_tick_usage = list() // MC singleton, filled every tick
	var/list/perf_tick_realtime = list() // MC singleton, filled every tick
	var/list/perf_outliers = list() // MC singleton, filled every tick
	/// Breakdown for the highest-usage tick since the last explicit reset.
	var/list/perf_worst_tick
	var/perf_history_limit = 12000
	/// Names of one system dependency cycle found at boot, or null (boot_dependencies.dm).
	var/boot_dependency_cycle
	/// Boot DAG errors (a system's need that names no node), or null before boot (kernel/boot.dm).
	var/list/boot_errors
	/// Every sample ever recorded, so callers can hold a position that survives trimming.
	var/perf_samples_total = 0
	var/perf_tick_top_name = "None"
	var/perf_tick_top_usage = 0
	var/perf_tick_peak_usage = 0
	var/list/perf_tick_breakdown
	/// TICK_USAGE when this tick's MC iteration began: everything before it this tick ran outside the MC
	/// (resumed sleeping procs, verbs run on the spot, Topic, clicks).
	var/perf_tick_start_usage = 0
	/// TICK_USAGE when the MC iteration recorded the tick, and the world.time it did: /world/Tick reads them
	/// to tell what ran after the MC (tick_frame_end()).
	var/perf_tick_end_usage = 0
	var/perf_tick_end_time = -1

/// The boot step before the globals exist (world/New): the config, the random seed, every system created (so the SS<X>
/// globals exist before anything reads them: some globals read SSmapping and friends), and the globals themselves.
/datum/controller/kernel/proc/preboot()
	// Ensure usr is null, to prevent any potential weirdness resulting from the kernel having a usr.
	usr = null // ALLOW(sys_usr_outside_verb): the boot step clears usr: it runs no verb and no player's input

	if(!config)
		config = new

	if(!random_seed)
		#ifdef UNIT_TESTS
		random_seed = 29051994 // How about 22475?
		#else
		random_seed = rand(1, 1e9)
		#endif
		rand_seed(random_seed)

	kernel_create_systems()

	if(!GLOB)
		new /datum/controller/global_vars

/datum/controller/kernel/proc/shutdown_kernel()
	processing = FALSE
	kernel_shutdown_systems()
	log_world("Shutdown complete")

ADMIN_VERB(cmd_controller_view_ui, R_SERVER|R_DEBUG, "Controller Overview", "View the current states of the Subsystem Controllers.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	Kernel.tgui_interact(user.mob)

/datum/controller/kernel/tgui_status(mob/user, datum/tgui_state/state)
	if(!admin_can(user.client, R_SERVER|R_DEBUG))
		return STATUS_CLOSE
	return STATUS_INTERACTIVE

/datum/controller/kernel/ui_opening(mob/user, datum/tgui/ui)
	use_rolling_usage = TRUE

/datum/controller/kernel/tgui_close(mob/user)
	var/valid_found = FALSE
	for(var/datum/tgui/open_ui as anything in open_tguis)
		if(open_ui.user == user)
			continue
		valid_found = TRUE
	if(!valid_found)
		use_rolling_usage = FALSE
	return ..()

/datum/controller/kernel/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["fast_update"] = overview_fast_update
	data["rolling_length"] = rolling_usage_length
	var/list/merged_1 = ui_data_datum_controller_kernel(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/controller/kernel's window data.
/datum/controller/kernel/proc/ui_data_datum_controller_kernel(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/system_data = list()
	// Every system with its work items' cost (the kernel runs them).
	for(var/datum/system/system as anything in kernel_pure_systems())
		system_data += list(list(
			"name" = system.name,
			"ref" = REF(system),
			"init_order" = 0,
			"last_fire" = system.last_fire,
			"next_fire" = 0,
			"can_fire" = system.can_fire,
			"doesnt_fire" = !system.times_fired,
			"cost_ms" = system.fire_cost,
			"wall_cost_last_ms" = system.fire_cost,
			"cpu_cost_ms" = system.fire_cost,
			"cpu_cost_last_ms" = system.fire_cost,
			"suspended_cost_last_ms" = 0,
			"run_slices_last" = system.ticks,
			"tick_usage" = 0,
			"usage_per_tick" = 0,
			"tick_overrun" = system.tick_overrun,
			"initialized" = system.initialized,
			"initialization_failure_message" = null,
		))
	data["subsystems"] = system_data
	// ALLOW(sys_world_time_write): reports the current clock in the overview, not a stored time
	data["world_time"] = world.time
	data["map_cpu"] = world.map_cpu

	return data

/datum/controller/kernel/proc/ui_act_toggle_fast_update(datum/act/op/A)
	overview_fast_update = !overview_fast_update
	return TRUE

/datum/controller/kernel/proc/ui_act_set_rolling_length(datum/act/op/A, rolling_length)
	var/length = rolling_length
	if(!length || length < 0)
		return
	rolling_usage_length = length SECONDS
	return TRUE

/datum/controller/kernel/proc/ui_act_view_variables(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!check_rights_for(user.client, R_DEBUG))
		message_admins(
			"[key_name(user)] tried to view kernel variables while having improper rights, \
			this is potentially a malicious exploit and worth noting."
		)

	var/datum/system/system = ref
	if(isnull(system))
		to_chat(user, span_warning("Failed to locate system."))
		return
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/debug_variables, system)
	return TRUE

/datum/controller/kernel/proc/check_and_perform_fast_update()
	set waitfor = FALSE // ALLOW(scheduler): the master controller's own loop (its startup detaches on purpose), not gameplay code

	if(!overview_fast_update)
		return

	var/static/already_updating = FALSE
	if(already_updating)
		return
	already_updating = TRUE
	SStgui.update_uis(src)
	already_updating = FALSE

/// Boots the systems (world/New, once): the boot DAG over every system, one init stage at a time, then the members' first
/// evaluation. The host loop starts when the first stage is done, so the later stages' work items run while they initialize.
/// Please don't stuff random work here: make a system and do it in its initialize().
/datum/controller/kernel/proc/boot_systems(delay, tgs_prime)
	set waitfor = 0 // ALLOW(scheduler): the kernel's own boot (its startup detaches on purpose), not gameplay code

	if(delay)
		sleep(delay) // ALLOW(scheduler): the kernel's own boot: it sleeps between ticks, it is not gameplay code

	init_stage_completed = 0
	var/loop_started = FALSE

	to_chat(world, span_boldannounce("Initializing systems..."), MESSAGE_TYPE_DEBUG)

	var/list/stage_sorted_systems = new(INITSTAGE_MAX)
	for (var/i in 1 to INITSTAGE_MAX)
		stage_sorted_systems[i] = list()

	// One graph, one validator (kernel/graph.dm): a system's `needs` name other systems.
	var/list/boot_systems = kernel_boot_systems()
	var/list/type_to_node = list()
	for(var/datum/system/boot_system as anything in boot_systems)
		type_to_node[boot_system.type] = boot_system
	boot_errors = list()
	var/list/deps_by_node = kernel_system_deps(boot_systems, type_to_node, boot_errors)
	for(var/boot_error in boot_errors)
		stack_trace("ERROR: kernel: boot: [boot_error]")
		log_world("ERROR: kernel: boot: [boot_error]")

	var/datum/graph_check/boot_graph = graph_validate(boot_systems, deps_by_node)
	var/list/cycle = boot_graph.cycle
	var/list/sorted_nodes = boot_graph.order

	if(length(boot_systems) != length(sorted_nodes))
		var/list/usr_msg = list()
		for(var/datum/D as anything in boot_systems - sorted_nodes)
			usr_msg += "[D.type]"
		boot_dependency_cycle = jointext(cycle, " -> ")
		// Can't initialize them if they have circular dependencies, there's no real failsafe here.
		stack_trace("ERROR: CRITICAL: kernel: The following systems have circular dependencies: [boot_dependency_cycle]")
		log_world("ERROR: CRITICAL: kernel: boot dependency cycle: [boot_dependency_cycle]")
		to_chat(world, span_bolddanger("CRITICAL: Failed to initialize [jointext(usr_msg, ", ")]"), MESSAGE_TYPE_DEBUG)

	for (var/datum/system/node as anything in sorted_nodes)
		stage_sorted_systems[kernel_system_stage(node, deps_by_node)] += node

	var/start_timeofday = REALTIMEOFDAY
	for (var/current_init_stage in 1 to INITSTAGE_MAX)
		for (var/datum/system/node as anything in stage_sorted_systems[current_init_stage])
			current_initializing = node
			kernel_boot_system(node)
			CHECK_TICK
		current_initializing = null
		init_stage_completed = current_init_stage
		if (!loop_started)
			loop_started = TRUE
			if (!current_runlevel)
				SetRunLevel(1) // Intentionally not using the defines here because the kernel doesn't care about them
			// Loop.
			StartProcessing(0)

	// Every system's members that joined during init get their first evaluation now, in one pass each
	// (kernel/system.dm on_members_ready(); the machine service arms first wakes here).
	kernel_members_ready()

	var/time = (REALTIMEOFDAY - start_timeofday) / 10
	initializations_seconds = time
#ifdef BENCHMARK
	benchmark_rust_mark("kernel: init done")
#endif

	var/msg = "Initializations complete within [time] second[time == 1 ? "" : "s"]!"
	to_chat(world, span_boldannounce("[msg]"), MESSAGE_TYPE_DEBUG)
	log_world(msg)

	// Opt-in only: under DreamDaemon -safe, shelleo() raises a modal "Safe Mode" permission dialog that
	// blocks the VM thread until someone answers it (invisible with -invisible = silent hang after init).
	if(world.system_type == MS_WINDOWS && CONFIG_GET(flag/toast_notification_on_init) && !length(GLOB.clients))
		log_world("Init toast: calling world.shelleo(); under -safe this blocks on a Safe Mode permission dialog.")
		world.shelleo("start /min powershell -ExecutionPolicy Bypass -File tools/initToast/initToast.ps1 -name \"[world.name]\" -icon %CD%\\icons\\virgoicon_16.png -port [world.port]")

	// Set world options.
	world.change_fps(CONFIG_GET(number/fps))
	var/initialized_tod = REALTIMEOFDAY

	if(tgs_prime)
		world.TgsInitializationComplete()

	// Decide before sleeping: with sleep_offline set and no client connected, BYOND stops
	// advancing world.time, so a sleep(1 TICKS) followed by "resume" never returns until a
	// player or Topic() wakes the world -- RESUME_AFTER_INITIALIZATIONS was silently ignored
	// and an empty server sat frozen in pregame with the MC parked.
	// Only ever switch it on: writing sleep_offline when it doesn't need to change has been
	// seen to leave a clientless world parked (see the TGS note on BYOND forum post 2894866).
	if(post_init_sleep_offline(FALSE, CONFIG_GET(flag/resume_after_initializations)))
		world.sleep_offline = TRUE
	log_world("MC: post-init sleep_offline=[world.sleep_offline] (resume_after_initializations=[CONFIG_GET(flag/resume_after_initializations)])")
	sleep(1 TICKS) // ALLOW(scheduler): the master controller's own loop: it sleeps between ticks, it is not gameplay code
	initializations_finished_with_no_players_logged_in = initialized_tod < REALTIMEOFDAY - 10

/// TRUE when the world should sleep offline once initialization completes (kept separate so a test can pin it).
/// RESUME_AFTER_INITIALIZATIONS must win here, before the post-init sleep: an empty world with
/// sleep_offline set stops advancing world.time, so nothing after that sleep would run.
/datum/controller/kernel/proc/post_init_sleep_offline(current, resume)
	if(!sleep_offline_after_initializations)
		return current
	return !resume

/datum/controller/kernel/proc/SetRunLevel(new_runlevel)
	var/old_runlevel = current_runlevel

	testing("MC: Runlevel changed from [isnull(old_runlevel) ? "NULL" : old_runlevel] to [new_runlevel]")
	current_runlevel = log(2, new_runlevel) + 1
	if(current_runlevel < 1)
		current_runlevel = old_runlevel
		CRASH("Attempted to set invalid runlevel: [new_runlevel]")
	kernel_runlevel_changed()

/// Starts the kernel's host loop (kernel/loop.dm start_loop()): the kernel owns the loop, this is the name it had.
/datum/controller/kernel/proc/StartProcessing(delay)
	kernel().start_loop(delay)

/datum/controller/kernel/proc/record_performance_tick(usage)
	usage = max(usage, 0)
	perf_tick_end_usage = TICK_USAGE
	// ALLOW(sys_world_time_write): the kernel clock: the tick record's own timestamp, not an entity expiry
	perf_tick_end_time = world.time
	kernel_latency().note_tick(usage)
	// Close the tick's per-system accounting (code/controllers/measure/). Its OM charges are read first:
	// end_tick() clears them.
	var/datum/tick_meter/meter = km_meter()
	var/om_charged_ms = meter.tick_charged
	meter.end_tick(usage, MAPTICK_LAST_INTERNAL_TICK_USAGE)
	perf_tick_usage += usage
	perf_tick_realtime += REALTIMEOFDAY
	perf_samples_total++
	if(perf_tick_usage.len > perf_history_limit)
		// Trim in chunks so a full five-minute ring does not shift twelve
		// thousand list entries on every server tick.
		var/trim_count = min(1000, perf_tick_usage.len - 1)
		perf_tick_usage.Cut(1, trim_count + 1)
		perf_tick_realtime.Cut(1, trim_count + 1)
	var/previous_worst_usage = LAZYACCESS(perf_worst_tick, "usage") || 0
	if(usage > previous_worst_usage || usage > 100)
		var/list/top_systems = meter.latest_top_systems()
		var/list/breakdown = performance_tick_breakdown(usage, om_charged_ms)
		var/list/tick_record = list(
			// ALLOW(sys_world_time_write): the tick record's own timestamp, not an entity expiry
			"world_time" = world.time,
			"usage" = usage,
			"overrun" = max(usage - 100, 0),
			"cause" = performance_tick_cause(breakdown, top_systems),
			"top_subsystem" = perf_tick_top_name,
			"top_usage" = perf_tick_top_usage,
			"pre_mc" = perf_tick_start_usage,
			"maptick" = MAPTICK_LAST_INTERNAL_TICK_USAGE,
			"breakdown" = breakdown,
			// The same tick by system, from inside Behaviours as well as the systems' own work items.
			"top_systems" = top_systems,
			"streak" = meter.streak,
		)
		var/list/slow_step = GLOB.om_live_sched?.slow_step
		if(slow_step && slow_step["world_time"] == world.time)
			tick_record["slow_step"] = slow_step
		if(usage > previous_worst_usage)
			perf_worst_tick = tick_record
		if(usage <= 100)
			return
		SSserver_metrics?.note_overrun(tick_record)
		perf_outliers += list(tick_record)
		if(perf_outliers.len > 20)
			perf_outliers.Cut(1, perf_outliers.len - 19)

/// Where the tick's `usage` went, as list(list("name", "usage"), ...) in percent of a tick: each hosted
/// system, the object model's charged work (`om_charged_ms`, from the tick meter), the rest of the MC's
/// own iteration, and what ran before the kernel this tick (perf_tick_start_usage).
/datum/controller/kernel/proc/performance_tick_breakdown(usage, om_charged_ms = 0)
	var/list/breakdown = list()
	var/attributed_usage = 0
	for(var/subsystem_name in perf_tick_breakdown)
		var/subsystem_usage = LAZYACCESS(perf_tick_breakdown, subsystem_name)
		attributed_usage += subsystem_usage
		breakdown += list(list("name" = subsystem_name, "usage" = subsystem_usage))
	var/pre_mc = clamp(perf_tick_start_usage, 0, usage)
	var/om_usage = clamp(om_charged_ms / world.tick_lag, 0, max(usage - pre_mc - attributed_usage, 0))
	if(om_usage)
		breakdown += list(list("name" = PERF_OBJECT_MODEL, "usage" = om_usage))
		attributed_usage += om_usage
	if(pre_mc)
		breakdown += list(list("name" = PERF_OUTSIDE_MC, "usage" = pre_mc))
	var/unattributed = max(usage - attributed_usage - pre_mc, 0)
	if(unattributed)
		breakdown += list(list("name" = PERF_MC_OTHER, "usage" = unattributed))
	return breakdown

/// What a tick's time mostly went to: PERF_OUTSIDE_MC when the time before the MC is the largest part of
/// `breakdown`, else the costliest system the tick meter saw (`top_systems`) or the costliest subsystem.
/datum/controller/kernel/proc/performance_tick_cause(list/breakdown, list/top_systems)
	var/best_name = "None"
	var/best_usage = 0
	for(var/list/part as anything in breakdown)
		if(part["usage"] > best_usage)
			best_usage = part["usage"]
			best_name = part["name"]
	if(best_name != PERF_OBJECT_MODEL)
		return best_name
	// Name the object-model system that took most of it.
	var/list/top = length(top_systems) ? top_systems[1] : null
	return top ? "[top["key"]]" : best_name

/// Converts a perf_samples_total position into a current perf_tick_usage index.
/// Positions that have been trimmed away clamp to the oldest retained sample.
/datum/controller/kernel/proc/perf_index_of(position)
	return max(position - (perf_samples_total - perf_tick_usage.len), 1)

/// Tick usage above this percentage shares the top percentile bin.
#define PERF_HISTOGRAM_BINS 1000

/// performance_window() with no samples (shared; callers only read it).
GLOBAL_LIST_INIT(empty_performance_window, list("samples" = 0, "avg" = 0, "p50" = 0, "p95" = 0, "p99" = 0, "max" = 0, "overruns" = 0, "tps" = 0))

/datum/controller/kernel/proc/performance_window(seconds, start_index_override)
	var/sample_count
	var/start_index
	if(start_index_override)
		start_index = clamp(start_index_override, 1, perf_tick_usage.len + 1)
		sample_count = perf_tick_usage.len - start_index + 1
	else
		sample_count = min(perf_tick_usage.len, max(round(world.fps * seconds), 1))
		start_index = perf_tick_usage.len - sample_count + 1
	if(!sample_count)
		return GLOB.empty_performance_window
	// Percentiles come from a 1%-wide histogram filled in the same pass as the
	// average, so the window is never copied or sorted (Q7). Usage above
	// PERF_HISTOGRAM_BINS% lands in the top bin; "max" stays exact.
	var/list/histogram = new /list(PERF_HISTOGRAM_BINS + 1)
	var/sum = 0
	var/overruns = 0
	var/window_max = 0
	var/end_index = start_index + sample_count - 1
	for(var/i in start_index to end_index)
		var/value = perf_tick_usage[i]
		sum += value
		if(value > window_max)
			window_max = value
		if(value > 100)
			overruns++
		var/bin = min(round(value), PERF_HISTOGRAM_BINS) + 1
		histogram[bin]++
	var/list/percentile_ranks = list(
		max(CEILING(sample_count * 0.50, 1), 1),
		max(CEILING(sample_count * 0.95, 1), 1),
		max(CEILING(sample_count * 0.99, 1), 1),
	)
	var/list/percentiles = list(0, 0, 0)
	var/rank_index = 1
	var/cumulative = 0
	for(var/bin in 1 to PERF_HISTOGRAM_BINS + 1)
		cumulative += histogram[bin]
		while(rank_index <= 3 && cumulative >= percentile_ranks[rank_index])
			percentiles[rank_index] = bin - 1
			rank_index++
		if(rank_index > 3)
			break
	var/realtime_delta = perf_tick_realtime[perf_tick_realtime.len] - perf_tick_realtime[start_index]
	if(realtime_delta < 0)
		realtime_delta += 24 HOURS
	return list(
		"samples" = sample_count,
		"avg" = sum / sample_count,
		"percentile_samples" = sample_count,
		"p50" = percentiles[1],
		"p95" = percentiles[2],
		"p99" = percentiles[3],
		"max" = window_max,
		"overruns" = overruns,
		"tps" = realtime_delta > 0 ? ((sample_count - 1) / (realtime_delta * 0.1)) : world.fps,
	)

#undef PERF_HISTOGRAM_BINS

/// Warns us that the end of tick byond map_update will be laggier then normal, so that we can just skip the tick's work this tick.
/datum/controller/kernel/proc/laggy_byond_map_update_incoming()
	if (!skip_ticks)
		skip_ticks = 1

/datum/controller/kernel/stat_entry(msg)
	msg = "(TickRate:[Kernel.processing]) (Iteration:[Kernel.iteration]) (TickLimit: [round(Kernel.current_ticklimit, 0.1)])"
	return msg

/// A map load begins placing. Loads do not wait on one another here: the loads that can overlap are jobs,
/// and /datum/map_load (map_load.dm) runs them one at a time through its queue, so this only counts.
/datum/controller/kernel/StartLoadingMap()
	map_loading_depth++
	if(map_loading_depth > 1)
		return
	for(var/datum/system/system as anything in kernel_pure_systems())
		system.StartLoadingMap()
	map_loading = TRUE

/datum/controller/kernel/StopLoadingMap(bounds = null)
	map_loading_depth = max(0, map_loading_depth - 1)
	if(map_loading_depth > 0)
		return
	map_loading = FALSE
	for(var/datum/system/system as anything in kernel_pure_systems())
		system.StopLoadingMap()

/datum/controller/kernel/proc/UpdateTickRate()
	if (!processing)
		return
	var/client_count = length(GLOB.clients)
	if (client_count < CONFIG_GET(number/mc_tick_rate/disable_high_pop_mc_mode_amount))
		processing = CONFIG_GET(number/mc_tick_rate/base_mc_tick_rate)
	else if (client_count > CONFIG_GET(number/mc_tick_rate/high_pop_mc_mode_amount))
		processing = CONFIG_GET(number/mc_tick_rate/high_pop_mc_tick_rate)

/datum/controller/kernel/proc/OnConfigLoad()
	for(var/datum/system/system as anything in kernel_pure_systems())
		system.OnConfigLoad()

/// Attempts to dump our current profile info into a file, triggered if the MC thinks shit is going down
/// Accepts a delay in deciseconds of how long ago our last dump can be, this saves causing performance problems ourselves
/datum/controller/kernel/proc/AttemptProfileDump(delay)
	// Drift snapshots serialize BYOND's full proc profile synchronously. If the
	// full profiler is not explicitly enabled, PROFILE_REFRESH can still return
	// retained startup data and perform the expensive serialization anyway.
	// Compact PERF_PROFILE diagnostics remain available through SSprofiler.
	if(!CONFIG_GET(flag/auto_profile) || CONFIG_GET(flag/forbid_all_profiling))
		return FALSE
	var/profile_cooldown = max(delay, 2 MINUTES)
	if(REALTIMEOFDAY - last_profiled <= profile_cooldown)
		return FALSE
	last_profiled = REALTIMEOFDAY
	SSprofiler.DumpFile(allow_yield = FALSE)
