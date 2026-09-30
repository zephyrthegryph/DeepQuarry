/**
 * Master: the compatibility shim of the old MC.
 *
 * The host loop is the kernel's (code/controllers/kernel/loop.dm) and there is no subsystem queue any more. What is left
 * here is the boot sequence (Initialize: the init DAG over subsystems and systems), the run level, and the values that
 * read `Master.x` across the codebase (iteration, last_run, sleep_delta, tickdrift, current_ticklimit,
 * current_runlevel, processing, init_stage_completed, ...), which the kernel loop keeps up to date with the same meaning.
 **/

// See initialization order in /code/game/world.dm
GLOBAL_REAL(Master, /datum/controller/master)
/datum/controller/master
	name = "Master"

	/// Are we processing (higher values increase the processing delay by n ticks)
	var/processing = TRUE
	/// How many times have we ran
	var/iteration = 0
	/// world.time of last fire, for tracking lag outside of the mc
	var/last_run

	/// List of subsystems to process().
	var/list/subsystems

	///Most recent init stage to complete init.
	var/static/init_stage_completed

	// Vars for keeping track of tick drift.
	var/init_timeofday
	var/init_time
	/// Wall-clock seconds the last full subsystem initialization took.
	var/initializations_seconds = 0
	var/tickdrift = 0
	/// Tickdrift as of last tick, w no averaging going on
	var/olddrift = 0

	/// How long is the loop sleeping between runs, read only (set by the kernel loop off of anti-tick-contention heuristics)
	var/sleep_delta = 1
	/// Only run ticker subsystems for the next n ticks.
	var/skip_ticks = 0

	/// makes the mc main loop runtime
	var/make_runtime = FALSE

	var/initializations_finished_with_no_players_logged_in //I wonder what this could be?

	var/map_loading = FALSE //!Are we loading in a new map?

	var/current_runlevel //!for scheduling different subsystems for different stages of the round
	var/sleep_offline_after_initializations = TRUE

	/// During initialization, will be the instanced subsytem that is currently initializing.
	/// Outside of initialization, returns null.
	var/current_initializing_subsystem = null

	/// The last decisecond we force dumped profiling information
	/// Used to avoid spamming profile reads since they can be expensive (string memes)
	var/last_profiled = 0

	var/static/restart_clear = 0
	var/static/restart_timeout = 0
	var/static/restart_count = 0

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
	var/list/perf_tick_usage = list() // ALLOW(instance_list): d: MC singleton, filled every tick
	var/list/perf_tick_realtime = list() // ALLOW(instance_list): d: MC singleton, filled every tick
	var/list/perf_outliers = list() // ALLOW(instance_list): d: MC singleton, filled every tick
	/// Breakdown for the highest-usage tick since the last explicit reset.
	var/list/perf_worst_tick
	var/perf_history_limit = 12000
	/// Names of one subsystem dependency cycle found at boot, or null (boot_dependencies.dm).
	var/boot_dependency_cycle
	/// Boot DAG errors (a system's need that names no node), or null before boot (kernel/boot.dm).
	var/list/boot_errors
	/// Every sample ever recorded, so callers can hold a position that survives trimming.
	var/perf_samples_total = 0
	var/perf_tick_top_name = "None"
	var/perf_tick_top_usage = 0
	var/perf_tick_peak_usage = 0
	var/list/perf_tick_breakdown

/datum/controller/master/New()
	// Ensure usr is null, to prevent any potential weirdness resulting from the MC having a usr if it's manually restarted.
	usr = null

	if(!config)
		config = new
	// Highlander-style: there can only be one! Kill off the old and replace it with the new.

	if(!random_seed)
		#ifdef UNIT_TESTS
		random_seed = 29051994 // How about 22475?
		#else
		random_seed = rand(1, 1e9)
		#endif
		rand_seed(random_seed)

	var/list/_subsystems = list()
	subsystems = _subsystems
	if (Master != src)
		if (istype(Master)) //If there is an existing Master take over its subsystems and run level and delete it
			if(istype(Master.subsystems))
				subsystems = Master.subsystems
			current_runlevel = Master.current_runlevel
			qdel(Master)
			Master = src
		else
			//Code used for first master on game boot or if existing master got deleted
			Master = src
			var/list/subsystem_types = subtypesof(/datum/controller/subsystem)
			sortTim(subsystem_types, GLOBAL_PROC_REF(cmp_subsystem_init_stage))

			//Find any abandoned subsystem from the previous master (if there was any)
			var/list/existing_subsystems = list()
			for(var/global_var in global.vars)
				if (istype(global.vars[global_var], /datum/controller/subsystem))
					existing_subsystems += global.vars[global_var]

			//Either init a new SS or if an existing one was found use that
			for(var/I in subsystem_types)
				var/ss_idx = existing_subsystems.Find(I)
#ifdef BENCHMARK
				var/started = REALTIMEOFDAY
				var/mb_before = benchmark_early_private_mb()
#endif
				if (ss_idx)
					_subsystems += existing_subsystems[ss_idx]
				else
					_subsystems += new I
#ifdef BENCHMARK
				benchmark_early_note("new [I]", REALTIMEOFDAY - started, mb_before)
#endif

	// The gameplay systems keep their SS<X> names (SYSTEM_DEF); they exist from here on, before the globals are built
	// (some of those read SSmapping and friends).
	kernel_create_systems()

	if(!GLOB)
		new /datum/controller/global_vars

// ALLOW(lifecycle): MC singleton; asks for a hard delete.
/datum/controller/master/Destroy()
	..()
	// Tell qdel() to Del() this object.
	return QDEL_HINT_HARDDEL_NOW

/datum/controller/master/Shutdown()
	processing = FALSE
	sortTim(subsystems, GLOBAL_PROC_REF(cmp_subsystem_init))
	reverse_range(subsystems)
	for(var/datum/controller/subsystem/ss in subsystems)
		log_world("Shutting down [ss.name] subsystem...")
		if (ss.slept_count > 0)
			log_world("Warning: Subsystem `[ss.name]` slept [ss.slept_count] times.")
		ss.Shutdown()
	kernel_shutdown_systems()
	shutdown_world_services()
	log_world("Shutdown complete")

ADMIN_VERB(cmd_controller_view_ui, R_SERVER|R_DEBUG, "Controller Overview", "View the current states of the Subsystem Controllers.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	Master.tgui_interact(user.mob)

/datum/controller/master/tgui_status(mob/user, datum/tgui_state/state)
	if(!user.client?.holder?.check_for_rights(R_SERVER|R_DEBUG))
		return STATUS_CLOSE
	return STATUS_INTERACTIVE

DECLARE_UI(/datum/controller/master, "ControllerOverview")

/datum/controller/master/ui_opening(mob/user, datum/tgui/ui)
	use_rolling_usage = TRUE

/datum/controller/master/tgui_close(mob/user)
	var/valid_found = FALSE
	for(var/datum/tgui/open_ui as anything in open_tguis)
		if(open_ui.user == user)
			continue
		valid_found = TRUE
	if(!valid_found)
		use_rolling_usage = FALSE
	return ..()

UI_DATA_REPLACE(/datum/controller/master, "fast_update=overview_fast_update:num", "rolling_length=rolling_usage_length:num", "merge:ui_data_datum_controller_master{subsystems:list,world_time:unknown,map_cpu:unknown}")

/// The computed part of /datum/controller/master's window data (declared on its UI_DATA row).
/datum/controller/master/proc/ui_data_datum_controller_master(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/subsystem_data = list()
	for(var/datum/controller/subsystem/subsystem as anything in subsystems)
		var/list/rolling_usage = subsystem.rolling_usage
		subsystem.prune_rolling_usage()

		// Then we sum
		var/sum = 0
		for(var/i in 2 to length(rolling_usage) step 2)
			sum += rolling_usage[i]
		var/average = sum / DS2TICKS(rolling_usage_length)

		subsystem_data += list(list(
			"name" = subsystem.name,
			"ref" = REF(subsystem),
			"init_order" = subsystem.init_order,
			"last_fire" = subsystem.last_fire,
			"next_fire" = subsystem.next_fire,
			"can_fire" = subsystem.can_fire,
			"doesnt_fire" = !!(subsystem.flags & SS_NO_FIRE),
			"cost_ms" = subsystem.wall_cost,
			"wall_cost_last_ms" = subsystem.wall_cost_last,
			"cpu_cost_ms" = subsystem.cost,
			"cpu_cost_last_ms" = subsystem.active_cost_last,
			"suspended_cost_last_ms" = subsystem.suspended_cost_last,
			"run_slices_last" = subsystem.run_slices_last,
			"tick_usage" = subsystem.tick_usage,
			"usage_per_tick" = average,
			"tick_overrun" = subsystem.tick_overrun,
			"initialized" = subsystem.initialized,
			"initialization_failure_message" = subsystem.initialization_failure_message,
		))
	// The gameplay systems are listed beside the subsystems (their fire work is kernel work items).
	for(var/datum/system/system as anything in kernel_pure_systems())
		subsystem_data += list(list(
			"name" = "[system.name] (system)",
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
	data["subsystems"] = subsystem_data
	data["world_time"] = world.time
	data["map_cpu"] = world.map_cpu

	return data

UI_ACT(/datum/controller/master, "toggle_fast_update", ui_act_toggle_fast_update)
UI_ACT_PROC(/datum/controller/master, ui_act_toggle_fast_update)
	overview_fast_update = !overview_fast_update
	return TRUE

UI_ACT(/datum/controller/master, "set_rolling_length", ui_act_set_rolling_length, UI_ARG_NUM("rolling_length"))
UI_ACT_PROC(/datum/controller/master, ui_act_set_rolling_length)
	var/length = params["rolling_length"]
	if(!length || length < 0)
		return
	rolling_usage_length = length SECONDS
	return TRUE

UI_ACT(/datum/controller/master, "view_variables", ui_act_view_variables, UI_ARG_REF("ref", "subsystems", /datum/controller/subsystem))
UI_ACT_PROC(/datum/controller/master, ui_act_view_variables)
	if(!check_rights_for(ui.user.client, R_DEBUG))
		message_admins(
			"[key_name(ui.user)] tried to view master controller variables while having improper rights, \
			this is potentially a malicious exploit and worth noting."
		)

	var/datum/controller/subsystem/subsystem = params["ref"]
	if(isnull(subsystem))
		to_chat(ui.user, span_warning("Failed to locate subsystem."))
		return
	SSadmin_verbs.dynamic_invoke_verb(ui.user, /datum/admin_verb/debug_variables, subsystem)
	return TRUE

/datum/controller/master/proc/check_and_perform_fast_update()
	set waitfor = FALSE // ALLOW(scheduler): MC code

	if(!overview_fast_update)
		return

	var/static/already_updating = FALSE
	if(already_updating)
		return
	already_updating = TRUE
	SStgui.update_uis(src)
	already_updating = FALSE

// Please don't stuff random bullshit here,
// Make a subsystem, give it the SS_NO_FIRE flag, and do your work in its Initialize()
/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	set waitfor = 0 // ALLOW(scheduler): MC code

	if(delay)
		sleep(delay) // ALLOW(scheduler): MC

	if(init_sss)
		init_subtypes(/datum/controller/subsystem, subsystems)

	init_stage_completed = 0
	var/mc_started = FALSE

	to_chat(world, span_boldannounce("Initializing subsystems..."), MESSAGE_TYPE_DEBUG)

	var/list/stage_sorted_subsystems = new(INITSTAGE_MAX)
	for (var/i in 1 to INITSTAGE_MAX)
		stage_sorted_subsystems[i] = list()

	var/list/type_to_subsystem = list()
	for(var/datum/controller/subsystem/subsystem as anything in subsystems)
		type_to_subsystem[subsystem.type] = subsystem

	// Allows subsystems to declare other subsystems that must initialize after them.
	for(var/datum/controller/subsystem/subsystem as anything in subsystems)
		for(var/dependent_type in subsystem.dependents)
			if(!ispath(dependent_type, /datum/controller/subsystem))
				stack_trace("ERROR: MC: subsystem `[subsystem.type]` has an invalid dependent: `[dependent_type]`. Skipping")
				continue
			var/datum/controller/subsystem/dependent = type_to_subsystem[dependent_type]
			LAZYOR(dependent.dependencies, subsystem.type)
		subsystem.dependents = list()

	// Systems are nodes of the same DAG (kernel/boot.dm): a system's `needs` name subsystems or systems.
	var/list/boot_systems = kernel_boot_systems()
	var/list/type_to_node = type_to_subsystem.Copy()
	for(var/datum/system/boot_system as anything in boot_systems)
		type_to_node[boot_system.type] = boot_system
	boot_errors = list()
	var/list/deps_by_node = list()
	var/list/system_deps = kernel_system_deps(boot_systems, type_to_node, boot_errors)
	for(var/datum/system/boot_system as anything in system_deps)
		deps_by_node[boot_system] = system_deps[boot_system]

	// Resolves each subsystem's declared dependencies (boot_dependencies.dm). A dependency is a subsystem or
	// a system, so a boot a subsystem used to do by hand is a declaration.
	for(var/datum/controller/subsystem/subsystem as anything in subsystems)
		var/list/resolved = list()
		for(var/dependency_type in subsystem.dependencies)
			if(!ispath(dependency_type, /datum/controller/subsystem) && !ispath(dependency_type, /datum/system))
				stack_trace("ERROR: MC: subsystem `[subsystem.type]` has an invalid dependency: `[dependency_type]`. Skipping")
				continue
			var/datum/dependency = type_to_node[dependency_type]
			if(!dependency)
				if(ispath(dependency_type, /datum/system))
					boot_errors += "[subsystem.type] depends on [dependency_type], which is not a boot node"
				continue
			var/dependency_stage
			var/datum/controller/subsystem/dependency_subsystem = istype(dependency, /datum/controller/subsystem) ? dependency : null
			if(dependency_subsystem)
				dependency_stage = dependency_subsystem.init_stage
			else
				dependency_stage = kernel_system_stage(dependency, deps_by_node)
			// Not a foolproof failsafe, likely to only prevent any immediate issues if this is only triggered once.
			if(subsystem.init_stage < dependency_stage)
				stack_trace("ERROR: MC: subsystem `[subsystem.type]` has an init_stage before one of its dependencies (Dependency: `[dependency.type]`, [subsystem.init_stage] < [dependency_stage])! Setting init_stage to [dependency_stage]")
				subsystem.init_stage = dependency_stage
			if(dependency_subsystem)
				dependency_subsystem.dependents += subsystem
			resolved += dependency
		deps_by_node[subsystem] = resolved
	for(var/boot_error in boot_errors)
		stack_trace("ERROR: MC: boot: [boot_error]")
		log_world("ERROR: MC: boot: [boot_error]")
	var/list/boot_nodes = subsystems + boot_systems

	// The same validator orders the kernel's work items (kernel/graph.dm).
	var/datum/graph_check/boot_graph = graph_validate(boot_nodes, deps_by_node)
	var/list/cycle = boot_graph.cycle
	var/list/sorted_nodes = boot_graph.order
	for(var/i in 1 to length(subsystems))
		var/datum/controller/subsystem/subsystem = subsystems[i]
		subsystem.ordering_id = i

	if(length(boot_nodes) != length(sorted_nodes))
		var/list/usr_msg = list()
		for(var/datum/D as anything in boot_nodes - sorted_nodes)
			usr_msg += "[D.type]"
		boot_dependency_cycle = jointext(cycle, " -> ")
		// Can't initialize them if they have circular dependencies, there's no real failsafe here.
		stack_trace("ERROR: CRITICAL: MC: The following nodes have circular dependencies: [boot_dependency_cycle]")
		log_world("ERROR: CRITICAL: MC: boot dependency cycle: [boot_dependency_cycle]")
		to_chat(world, span_bolddanger("CRITICAL: Failed to initialize [jointext(usr_msg, ", ")]"), MESSAGE_TYPE_DEBUG)

	for (var/datum/node as anything in sorted_nodes)
		var/node_init_stage
		if(istype(node, /datum/system))
			node_init_stage = kernel_system_stage(node, deps_by_node)
		else
			var/datum/controller/subsystem/subsystem = node
			node_init_stage = subsystem.init_stage
			if (!isnum(node_init_stage) || node_init_stage < 1 || node_init_stage > INITSTAGE_MAX || round(node_init_stage) != node_init_stage)
				stack_trace("ERROR: MC: subsystem `[subsystem.type]` has invalid init_stage: `[node_init_stage]`. Setting to `[INITSTAGE_MAX]`")
				node_init_stage = subsystem.init_stage = INITSTAGE_MAX
		stage_sorted_subsystems[node_init_stage] += node

	// Sort subsystems by display setting for easy access.
	var/evaluated_order = 1
	sortTim(subsystems, GLOBAL_PROC_REF(cmp_subsystem_display))
	var/start_timeofday = REALTIMEOFDAY
	for (var/current_init_stage in 1 to INITSTAGE_MAX)

		// Initialize subsystems.
		for (var/datum/node in stage_sorted_subsystems[current_init_stage])
			if(istype(node, /datum/system))
				kernel_boot_system(node)
				CHECK_TICK
				continue
			var/datum/controller/subsystem/subsystem = node
			subsystem.init_order = evaluated_order
			evaluated_order++
			init_subsystem(subsystem)

			CHECK_TICK
		current_initializing_subsystem = null
		init_stage_completed = current_init_stage
		if (!mc_started)
			mc_started = TRUE
			if (!current_runlevel)
				SetRunLevel(1) // Intentionally not using the defines here because the MC doesn't care about them
			// Loop.
			Master.StartProcessing(0)

	// Every system's members that joined during init get their first evaluation now, in one pass each
	// (kernel/system.dm on_members_ready(); the machine service arms first wakes here).
	kernel_members_ready()

	var/time = (REALTIMEOFDAY - start_timeofday) / 10
	initializations_seconds = time
#ifdef BENCHMARK
	benchmark_rust_mark("mc: init done")
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
	sleep(1 TICKS) // ALLOW(scheduler): MC
	initializations_finished_with_no_players_logged_in = initialized_tod < REALTIMEOFDAY - 10

/// TRUE when the world should sleep offline once initialization completes (kept separate so a test can pin it).
/// RESUME_AFTER_INITIALIZATIONS must win here, before the post-init sleep: an empty world with
/// sleep_offline set stops advancing world.time, so nothing after that sleep would run.
/datum/controller/master/proc/post_init_sleep_offline(current, resume)
	if(!sleep_offline_after_initializations)
		return current
	return !resume

/**
 * Initialize a given subsystem and handle the results.
 *
 * Arguments:
 * * subsystem - the subsystem to initialize.
 */
/datum/controller/master/proc/init_subsystem(datum/controller/subsystem/subsystem)
	var/static/list/valid_results = list(
		SS_INIT_FAILURE,
		SS_INIT_NONE,
		SS_INIT_SUCCESS,
		SS_INIT_NO_NEED,
		SS_INIT_NO_MESSAGE,
	)

	if ((subsystem.flags & SS_NO_INIT) || subsystem.initialized) //Don't init SSs with the corresponding flag or if they already are initialized
		subsystem.initialized = TRUE // set initialized to TRUE, because the value of initialized may still be checked on SS_NO_INIT subsystems as an "is this ready" check
		return

	current_initializing_subsystem = subsystem
	rustg_time_reset(SS_INIT_TIMER_KEY)

	var/result = subsystem.Initialize()

	// Capture end time
	var/time = rustg_time_milliseconds(SS_INIT_TIMER_KEY)
	var/seconds = round(time / 1000, 0.01)
	subsystem.init_time_ms = time
#ifdef BENCHMARK
	benchmark_rust_mark("init [subsystem.name]")
#endif

	// Always update the blackbox tally regardless.
	// NOT IMPLEMENTED: SSblackbox.record_feedback("tally", "subsystem_initialize", time, subsystem.name)
	feedback_set_details("subsystem_initialize", "[time] [subsystem.name]")

	// Gave invalid return value.
	if(result && !(result in valid_results))
		WARNING("[subsystem.name] subsystem initialized, returning invalid result [result]. This is a bug.")

	// just returned ..() or didn't implement Initialize() at all
	if(result == SS_INIT_NONE)
		WARNING("[subsystem.name] subsystem does not implement Initialize() or it returns ..(). If the former is true, the SS_NO_INIT flag should be set for this subsystem.")

	if(result != SS_INIT_FAILURE)
		// Some form of success, implicit failure, or the SS in unused.
		subsystem.initialized = TRUE
	else
		// The subsystem officially reports that it failed to init and wishes to be treated as such.
		subsystem.initialized = FALSE
		subsystem.can_fire = FALSE

	// The rest of this proc is printing the world log and chat message.
	var/message_prefix

	// If true, print the chat message with boldwarning text.
	var/chat_warning = FALSE

	switch(result)
		if(SS_INIT_FAILURE)
			message_prefix = "Failed to initialize [subsystem.name] subsystem after"
			chat_warning = TRUE
		if(SS_INIT_SUCCESS, SS_INIT_NO_MESSAGE)
			message_prefix = "Initialized [subsystem.name] subsystem within"
		if(SS_INIT_NO_NEED)
			// This SS is disabled or is otherwise shy.
			return
		else
			// SS_INIT_NONE or an invalid value.
			message_prefix = "Initialized [subsystem.name] subsystem with errors within"
			chat_warning = TRUE

	var/message = "[message_prefix] [seconds] second[seconds == 1 ? "" : "s"]!"
	var/chat_message = chat_warning ? span_boldwarning(message) : span_boldannounce(message)

	if(result != SS_INIT_NO_MESSAGE)
		to_chat(world, chat_message, MESSAGE_TYPE_DEBUG)
	log_world(message)

/datum/controller/master/proc/SetRunLevel(new_runlevel)
	var/old_runlevel = current_runlevel

	testing("MC: Runlevel changed from [isnull(old_runlevel) ? "NULL" : old_runlevel] to [new_runlevel]")
	current_runlevel = log(2, new_runlevel) + 1
	if(current_runlevel < 1)
		current_runlevel = old_runlevel
		CRASH("Attempted to set invalid runlevel: [new_runlevel]")
	kernel_runlevel_changed()

/// Starts the kernel's host loop (kernel/loop.dm start_loop()): the kernel owns the loop, this is the name it had.
/datum/controller/master/proc/StartProcessing(delay)
	kernel().start_loop(delay)

/datum/controller/master/proc/record_performance_tick(usage)
	usage = max(usage, 0)
	kernel_latency().note_tick(usage)
	// Close the tick's per-system accounting (code/controllers/measure/).
	km_meter().end_tick(usage, MAPTICK_LAST_INTERNAL_TICK_USAGE)
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
		var/list/breakdown = performance_tick_breakdown(usage)
		var/datum/tick_meter/meter = km_meter()
		var/list/tick_record = list(
			"world_time" = world.time,
			"usage" = usage,
			"overrun" = max(usage - 100, 0),
			"top_subsystem" = perf_tick_top_name,
			"top_usage" = perf_tick_top_usage,
			"maptick" = MAPTICK_LAST_INTERNAL_TICK_USAGE,
			"breakdown" = breakdown,
			// The same tick by system, from inside Behaviours as well as the MC's own subsystems.
			"top_systems" = meter.latest_top_systems(),
			"streak" = meter.streak,
		)
		if(usage > previous_worst_usage)
			perf_worst_tick = tick_record
		if(usage <= 100)
			return
		perf_outliers += list(tick_record)
		if(perf_outliers.len > 20)
			perf_outliers.Cut(1, perf_outliers.len - 19)

/datum/controller/master/proc/performance_tick_breakdown(usage)
	var/list/breakdown = list()
	var/attributed_usage = 0
	for(var/subsystem_name in perf_tick_breakdown)
		var/subsystem_usage = LAZYACCESS(perf_tick_breakdown, subsystem_name)
		attributed_usage += subsystem_usage
		breakdown += list(list("name" = subsystem_name, "usage" = subsystem_usage))
	var/unattributed = max(usage - attributed_usage, 0)
	if(unattributed)
		breakdown += list(list("name" = "BYOND / pre-MC / external", "usage" = unattributed))
	return breakdown

/// Converts a perf_samples_total position into a current perf_tick_usage index.
/// Positions that have been trimmed away clamp to the oldest retained sample.
/datum/controller/master/proc/perf_index_of(position)
	return max(position - (perf_samples_total - perf_tick_usage.len), 1)

/// Tick usage above this percentage shares the top percentile bin.
#define PERF_HISTOGRAM_BINS 1000

/// performance_window() with no samples (shared; callers only read it).
GLOBAL_LIST_INIT(empty_performance_window, list("samples" = 0, "avg" = 0, "p50" = 0, "p95" = 0, "p99" = 0, "max" = 0, "overruns" = 0, "tps" = 0))

/datum/controller/master/proc/performance_window(seconds, start_index_override)
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

/// Warns us that the end of tick byond map_update will be laggier then normal, so that we can just skip running subsystems this tick.
/datum/controller/master/proc/laggy_byond_map_update_incoming()
	if (!skip_ticks)
		skip_ticks = 1

/datum/controller/master/stat_entry(msg)
	msg = "(TickRate:[Master.processing]) (Iteration:[Master.iteration]) (TickLimit: [round(Master.current_ticklimit, 0.1)])"
	return msg

/datum/controller/master/StartLoadingMap()
	//disallow more than one map to load at once, multithreading it will just cause race conditions
	while(map_loading)
		stoplag() // ALLOW(scheduler): MC code (map-load mutex)
	for(var/S in subsystems)
		var/datum/controller/subsystem/SS = S
		SS.StartLoadingMap()
	for(var/datum/system/system as anything in kernel_pure_systems())
		system.StartLoadingMap()
	map_loading = TRUE

/datum/controller/master/StopLoadingMap(bounds = null)
	map_loading = FALSE
	for(var/S in subsystems)
		var/datum/controller/subsystem/SS = S
		SS.StopLoadingMap()
	for(var/datum/system/system as anything in kernel_pure_systems())
		system.StopLoadingMap()

/datum/controller/master/proc/UpdateTickRate()
	if (!processing)
		return
	var/client_count = length(GLOB.clients)
	if (client_count < CONFIG_GET(number/mc_tick_rate/disable_high_pop_mc_mode_amount))
		processing = CONFIG_GET(number/mc_tick_rate/base_mc_tick_rate)
	else if (client_count > CONFIG_GET(number/mc_tick_rate/high_pop_mc_mode_amount))
		processing = CONFIG_GET(number/mc_tick_rate/high_pop_mc_tick_rate)

/datum/controller/master/proc/OnConfigLoad()
	for (var/thing in subsystems)
		var/datum/controller/subsystem/SS = thing
		SS.OnConfigLoad()

/// Attempts to dump our current profile info into a file, triggered if the MC thinks shit is going down
/// Accepts a delay in deciseconds of how long ago our last dump can be, this saves causing performance problems ourselves
/datum/controller/master/proc/AttemptProfileDump(delay)
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
