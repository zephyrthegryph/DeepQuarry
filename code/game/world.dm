#define RESTART_COUNTER_PATH "data/round_counter.txt"
/// Load byond-tracy. If USE_BYOND_TRACY is defined, then this is ignored and byond-tracy is always loaded.
#define USE_TRACY_PARAMETER "tracy"
/// Force the log directory to be something specific in the data/logs folder
#define OVERRIDE_LOG_DIRECTORY_PARAMETER "log-directory"
/// Prevent the master controller from starting automatically
#define NO_INIT_PARAMETER "no-init"
/// This world's 0-based position in a sharded dm-test run (`dm-test --shards=N`).
/// See dq_test_shard_init() in code/modules/unit_tests/unit_test.dm.
#define TEST_SHARD_INDEX_PARAMETER "shard-index"
/// The shard count for a sharded dm-test run. See TEST_SHARD_INDEX_PARAMETER.
#define TEST_SHARD_COUNT_PARAMETER "shard-count"
/// Path to the sharded run's assignment file: one "path<TAB>shard index" line
/// per non-sweep test type. See TEST_SHARD_INDEX_PARAMETER.
#define TEST_SHARD_TESTS_FILE_PARAMETER "shard-tests"
/// Overrides where RunUnitTests() writes its JSON results (default
/// data/unit_tests.json), so a sharded run's N worlds don't clobber each
/// other's results file.
#define TEST_RESULTS_FILE_PARAMETER "unit-tests-file"
/// Path to a file listing (one per line) an explicit test selection from
/// `dm-test --domains=`/`--tier=`/`--affected`. See TEST_SHARD_INDEX_PARAMETER.
#define TEST_SELECT_FILE_PARAMETER "test-select"

/// Set by `dm-test --profile-tests`: profile each unit test and write its proc
/// profile under the log directory. See dq_test_write_profile().
#define TEST_PROFILE_PARAMETER "test-profile"
/// Which unit-test tier to run: "normal" (default), "all" or "exhaustive".
/// See TEST_TIER_* in code/modules/unit_tests/_unit_tests.dm.
#define TEST_TIER_PARAMETER "test-tier"

GLOBAL_VAR(restart_counter)

/**
 * WORLD INITIALIZATION
 * THIS IS THE INIT ORDER:
 *
 * BYOND =>
 * - (secret init native) =>
 *   - world.Genesis() =>
 *     - world.init_byond_tracy()
 *     - (Start native profiling)
 *     - world.init_debugger()
 *     - Kernel.preboot() =>
 *       - config *unloaded
 *       - (all systems) preinit()
 *       - GLOB =>
 *         - make_datum_reference_lists()
 *   - (/static variable inits, reverse declaration order)
 * - (all pre-mapped atoms) /atom/New()
 * - world.New() =>
 *   - config.Load()
 *   - world.InitTgs() =>
 *     - TgsNew() *may sleep
 *     - GLOB.rev_data.load_tgs_info()
 *   - world.ConfigLoaded() =>
 *     - SSdbcore.InitializeRound()
 *     - world.SetupLogs()
 *     - load_admins()
 *     - ...
 *   - Kernel.boot_systems() =>
 *     - (all systems, in dependency order) initialize()
 *     - Kernel.StartProcessing() =>
 *       - Kernel.loop() =>
 *         - the watchdog
 *   - world.RunUnattendedFunctions()
 *
 * Now listen up because I want to make something clear:
 * If something is not in this list it should almost definitely be handled by a system initialize()ing
 * If whatever it is that needs doing doesn't fit in a system you probably aren't trying hard enough tbhfam
 *
 * GOT IT MEMORIZED?
 * - Dominion/Cyberboss
 *
 * Where to put init shit quick guide:
 * If you need it to happen before the mc is created: world/Genesis.
 * If you need it to happen last: world/New(),
 * Otherwise, in a subsystem preinit or init. Subsystems can set an init priority.
 */

/**
 * THIS !!!SINGLE!!! PROC IS WHERE ANY FORM OF INIITIALIZATION THAT CAN'T BE PERFORMED IN SUBSYSTEMS OR WORLD/NEW IS DONE
 * NOWHERE THE FUCK ELSE
 * I DON'T CARE HOW MANY LAYERS OF DEBUG/PROFILE/TRACE WE HAVE, YOU JUST HAVE TO DEAL WITH THIS PROC EXISTING
 * I'M NOT EVEN GOING TO TELL YOU WHERE IT'S CALLED FROM BECAUSE I'M DECLARING THAT FORBIDDEN KNOWLEDGE
 * SO HELP ME GOD IF I FIND ABSTRACTION LAYERS OVER THIS!
 */
/world/proc/Genesis(tracy_initialized = FALSE)
	RETURN_TYPE(/datum/controller/kernel)

	if(!tracy_initialized)
		Tracy = new
#ifdef USE_BYOND_TRACY
		if(Tracy.enable("USE_BYOND_TRACY defined"))
			Genesis(tracy_initialized = TRUE)
			return
#else
		var/tracy_enable_reason
		if(USE_TRACY_PARAMETER in params)
			tracy_enable_reason = "world.params"
		if(fexists(TRACY_ENABLE_PATH))
			tracy_enable_reason ||= "enabled for round"
			SEND_TEXT(world.log, "[TRACY_ENABLE_PATH] exists, initializing byond-tracy!")
			fdel(TRACY_ENABLE_PATH)
		if(!isnull(tracy_enable_reason) && Tracy.enable(tracy_enable_reason))
			Genesis(tracy_initialized = TRUE)
			return
#endif

	Profile(PROFILE_RESTART)
	Profile(PROFILE_RESTART, type = "sendmaps")

	// Write everything to this log file until we get to SetupLogs() later
	_initialize_log_files("data/logs/config_error.[GUID()].log")

	// Init the debugger first so we can debug the kernel
	Debugger = new

	// Create the logger
	logger = new

	// THAT'S IT, WE'RE DONE, THE. FUCKING. END.
	// The kernel exists from here on. Its live work (the cadence and sequence sweeps) registers when world/New opens
	// registration: the static variable inits those registrations read run between this and world/New.
	Kernel = new /datum/controller/kernel
	Kernel.preboot()

/**
 * World creation
 *
 * Here is where a round itself is actually begun and setup.
 * * db connection setup
 * * config loaded from files
 * * loads admins
 * * Sets up the dynamic menu system
 * * and most importantly, calls initialize on the master subsystem, starting the game loop that causes the rest of the game to begin processing and setting up
 *
 *
 * Nothing happens until something moves. ~Albert Einstein
 *
 * For clarity, this proc gets triggered later in the initialization pipeline, it is not the first thing to happen, as it might seem.
 *
 * Initialization Pipeline:
 * Global vars are new()'ed, (including config, glob, and the master controller will also new and preinit all subsystems when it gets new()ed)
 * Compiled in maps are loaded (mainly centcom). all areas/turfs/objs/mobs(ATOMs) in these maps will be new()ed
 * world/New() (You are here)
 * Once world/New() returns, client's can connect.
 * 1 second sleep
 * Kernel initialization.
 * Subsystem initialization.
 * Non-compiled-in maps are maploaded, all atoms are new()ed
 * All atoms in both compiled and uncompiled maps are initialized()
 */
/world/New()
	log_world("World loaded at [time_stamp()]!")
	Kernel.registration_open = TRUE
	kernel()

	// Verdigris (Rust FFI) bring-up and version handshake. Init must come before
	// cleanup so the panic hook catches any failure inside cleanup itself. A DLL
	// built from a different bind set than this DM build fails here, loudly,
	// instead of misrouting arguments later.
#ifdef UNIT_TESTS
	// A mixture that exists before the Rust world is rebuilt below, like a
	// compiled-in map atom's; dq_preboot_gas_mixture_keeps_its_moles checks it.
	GLOB.dq_preboot_gas_probe = dq_make_preboot_gas_probe()
#endif
	var/verdigris_abi = vg_verdigris_init(VERDIGRIS_ABI)
	if(verdigris_abi != VERDIGRIS_ABI)
		var/abi_error = "FATAL: verdigris library ABI [verdigris_abi || "(none)"] does not match the DM build's VERDIGRIS_ABI [VERDIGRIS_ABI]. Rebuild verdigris.dll and the DM from the same tree (tools/build/build.sh)."
		log_world(abi_error)
		world.log << abi_error
		del(world) // ALLOW(scheduler): del(world): world shutdown
		return
	vg_verdigris_cleanup()
	vg_heat_reset()
	vg_configure_world(world.maxx, world.maxy, world.maxz)
	// Compiled-map atoms and global initializers run before world/New(), and
	// any gas mixture they made (a machine's `internal = new()`) already holds
	// a main-owned slot. The init/cleanup/configure calls above rebuild the
	// Rust world but keep those slots and their gas (gas/mix.rs reset_watches).
	// What they can't know is which slots still have a datum: the library
	// outlives a world reboot, so free every slot no live mixture names.
	var/list/live_mixtures = list()
	for(var/datum/gas_mixture/live_mix)
		if(!isnull(live_mix._extools_pointer_gasmixture))
			live_mixtures += live_mix
	var/freed_mixtures = vg_gas_retain_mixtures(live_mixtures)
	log_world("Verdigris: kept [length(live_mixtures)] gas mixture(s) created before world start, freed [freed_mixtures] stale slot(s)")
	log_world("Verdigris loaded: [vg_verdigris_version()] | features: [vg_verdigris_features()]")
#ifdef BENCHMARK
	benchmark_rust_mark("world: New (globals and compiled map loaded)")
#endif

	GLOB.world_startup_time = world.timeofday
	GLOB.rollover_safety_date = world.realtime - world.timeofday // 00:00 today (ish, since floating point error with world.realtime) of today

	//ChompADD Start - Newsfile
	var/savefile/F = new(NEWSFILE)
	if(F)
		var/title
		F["title"] >> title
		F["title"] >> title //This is done twice on purpose. For some reason BYOND misses the first read, if performed before the world starts
		var/body
		F["body"] >> body
		GLOB.servernews_hash = md5("[title]" + "[body]")
	//ChompADD End

	InitTgs()

	config.Load(params[OVERRIDE_CONFIG_DIRECTORY_PARAMETER])

	ConfigLoaded()

	if(NO_INIT_PARAMETER in params)
		return

	make_datum_reference_lists()
#ifdef BENCHMARK
	benchmark_rust_mark("world: datum reference lists")
#endif

	var servername = CONFIG_GET(string/servername)
	if(config && servername != null && CONFIG_GET(flag/server_suffix) && world.port > 0)
		// dumb and hardcoded but I don't care~
		servername += " #[(world.port % 1000) / 100]"
		CONFIG_SET(string/servername, servername)

	// TODO - Figure out what this is. Can you assign to world.log?
	// if(config && CONFIG_FLAG(flag/log_runtime))
	// 	log = file("data/logs/runtime/[time2text(world.realtime,"YYYY-MM-DD-(hh-mm-ss)")]-runtime.log")

	GLOB.timezoneOffset = world.timezone * 36000

	callHook("startup")

	// This should probably moved somewhere else
	// Maybe even a comsig?
	if(CONFIG_GET(flag/usewhitelist))
		load_whitelist()
	if(CONFIG_GET(flag/usealienwhitelist))
		load_alienwhitelist()
	load_jobwhitelist()

	src.update_status()
	setup_season() // ition

#ifdef UNIT_TESTS
	log_test("Unit Tests Enabled. This will destroy the world when testing is complete.")
	log_test("If you did not intend to enable this please check code/__defines/unit_testing.dm")
#endif

#ifdef BENCHMARK
	benchmark_rust_mark("world: before kernel boot")
#endif
	Kernel.boot_systems(10, TRUE)

	RunUnattendedFunctions()

	//so we aren't adding to the round-start lag; the download itself is an om_io job
	after(null, 5 MINUTES, GLOBAL_PROC_REF(ToRban_autoupdate_if_enabled))

	return

/// Initializes TGS and loads the returned revising info into GLOB.revdata
/world/proc/InitTgs()
	TgsNew(new /datum/tgs_event_handler/impl, TGS_SECURITY_TRUSTED)
	GLOB.revdata.load_tgs_info()

/// Runs after config is loaded but before the systems boot
/world/proc/ConfigLoaded()
	// Everything in here is prioritized in a very specific way.
	// If you need to add to it, ask yourself hard if what your adding is in the right spot
	// (i.e. basically nothing should be added before load_admins() in here)

	// Try to set round ID
	SSdbcore.InitializeRound()

	SetupLogs()

	load_admins(initial = TRUE)

	if(fexists(RESTART_COUNTER_PATH))
		GLOB.restart_counter = text2num(trim(file2text(RESTART_COUNTER_PATH)))
		fdel(RESTART_COUNTER_PATH)

/// Runs after the call to Kernel.boot_systems, but before the delay kicks in. Used to turn the world execution into some single function then exit
/world/proc/RunUnattendedFunctions()
	#ifdef UNIT_TESTS
	HandleTestRun()
	#endif

	#ifdef AUTOWIKI
	setup_autowiki()
	#endif


/world/proc/HandleTestRun()
	//trigger things to run the whole process
	Kernel.sleep_offline_after_initializations = FALSE
	SSticker.start_immediately = TRUE
	CONFIG_SET(number/round_end_countdown, 0)
	var/after_start
#ifdef UNIT_TESTS
	dq_test_shard_init()
	after_start = GLOBAL_PROC_REF(start_unit_tests)
#else
	after_start = GLOBAL_PROC_REF(force_end_round)
#endif
	var/start_delay = 10 SECONDS
#ifdef UNIT_TESTS
	// The full suite keeps upstream's 10 s round-start settle so CI and local
	// full runs see the same world. Focused runs are for iteration and start
	// after 2 s; a test that only passes after the longer settle should wait
	// for what it needs itself (see doc/testing.md).
	if(unit_test_is_focused_run())
		start_delay = 2 SECONDS
#endif
	SSticker.OnRoundstart(om_callable(null, GLOBAL_PROC_REF(om_after), null, start_delay, after_start))

/// after() target: ends the round now (a test-harness run with no tests compiled in).
/proc/force_end_round()
	SSticker.force_ending = ADMIN_FORCE_END_ROUND

/// Returns a list of data about the world state, don't clutter
/world/proc/get_world_state_for_logging()
	var/data = list()
	data["tick_usage"] = world.tick_usage
	data["tick_lag"] = world.tick_lag
	data["time"] = EXPIRY_AT(src, CLOCK_WORLD, 0)
	data["timestamp"] = rustg_unix_timestamp()
	return data

/world/proc/SetupLogs()
	var/override_dir = params[OVERRIDE_LOG_DIRECTORY_PARAMETER]
	if(!override_dir)
		var/realtime = world.realtime
		var/texttime = time2text(realtime, "YYYY/MM/DD", TIMEZONE_UTC)
		GLOB.log_directory = "data/logs/[texttime]/round-"
		if(GLOB.round_id)
			GLOB.log_directory += "[GLOB.round_id]"
		else
			var/timestamp = replacetext(time_stamp(), ":", ".")
			GLOB.log_directory += "[timestamp]"
	else
		GLOB.log_directory = "data/logs/[override_dir]"

	logger.init_logging()

	var/latest_changelog = file("[global.config.directory]/../html/changelogs/archive/" + time2text(world.timeofday, "YYYY-MM", TIMEZONE_UTC) + ".yml")
	GLOB.changelog_hash = fexists(latest_changelog) ? md5(latest_changelog) : 0 //for telling if the changelog has changed recently

	if(GLOB.round_id)
		log_game("Round ID: [GLOB.round_id]")

	// This was printed early in startup to the world log and config_error.log,
	// but those are both private, so let's put the commit info in the runtime
	// log which is ultimately public.
	log_runtime(GLOB.revdata.get_log_message())

#ifndef USE_CUSTOM_ERROR_HANDLER
	world.log = file("[GLOB.log_directory]/dd.log")
#else
	if (TgsAvailable()) // why
		world.log = file("[GLOB.log_directory]/dd.log") //not all runtimes trigger world/Error, so this is the only way to ensure we can see all of them.
#endif

GLOBAL_VAR_INIT(world_topic_spam_protect_ip, "0.0.0.0")
GLOBAL_VAR_INIT(world_topic_spam_protect_time, world.timeofday)

// ALLOW(sys_topic_override): server queries from BYOND world.Export (T is a query string, not an href to a datum); TGS and the status/ping protocol own its shape.
/world/Topic(T, addr, master, key)
	TGS_TOPIC
	log_topic("\"[T]\", from:[addr], master:[master], key:[key]")

	// The localhost diagnostic probes below answer only to 127.0.0.1, and also need key=<DIAG_TOPIC_KEY> when that's set.
	var/diag = diag_topic_command(T, addr)

	// Opt-in MC liveness probe for hung-server triage; localhost only.
	if (diag == "mcdiag")
		var/list/d = list(
			"world_time" = world.time, "tick_usage" = world.tick_usage, "cpu" = world.cpu, "sleep_offline" = world.sleep_offline, // ALLOW(sys_world_time_write): reports the current clock in a diagnostic reply, not a stored time
			"kernel_ticks" = kernel().ticks, "kernel_last_tick" = kernel().last_tick, "kernel_phase_faults" = kernel().phase_faults,
			"mc_iteration" = Kernel?.iteration, "mc_last_run" = Kernel?.last_run, "mc_sleep_delta" = Kernel?.sleep_delta,
			"mc_processing" = Kernel?.processing, "mc_runlevel" = Kernel?.current_runlevel, "mc_init_stage" = Kernel?.init_stage_completed,
			"mc_tickdrift" = Kernel?.tickdrift, "watchdog_lasttick" = Kernel?.watchdog?.lasttick,
			"ticker_state" = SSticker?.current_state, "ticker_last_fire" = SSticker?.last_fire, "profiler_last_sample" = SSprofiler?.last_fire,
		)
		return json_encode(d)
	// Localhost-only census of machines with step work on the machine pipeline, by type, with how
	// many of them the step stage's idle rule would settle (watch armed / no work).
	if (diag == "omsteps")
		var/list/active_by_type = list()
		var/list/settleable_by_type = list()
		var/active = 0
		for(var/obj/machinery/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
			if(!M.step_active || !om_attached(M, /datum/om/pipeline/machine))
				continue
			active++
			var/type_key = "[M.type]"
			active_by_type[type_key] = (active_by_type[type_key] || 0) + 1
			if(om_watch_armed(M) || !M.step_has_work())
				settleable_by_type[type_key] = (settleable_by_type[type_key] || 0) + 1
		return json_encode(list("active" = active, "active_by_type" = active_by_type, "settleable_by_type" = settleable_by_type))

	// Localhost-only census of the OM deadline wheel: entries per bucket, how many are still live
	// (their generation matches the rec's armed deadline) and which owner types/behaviours hold them.
	if (diag == "omdeadlines")
		var/datum/om/scheduler/sched = om_scheduler()
		var/datum/om/registry/reg = om_registry()
		var/total = 0
		var/live = 0
		var/max_bucket = 0
		var/list/by_owner = list()
		var/list/by_behaviour = list()
		for(var/list/L as anything in sched.buckets)
			var/n = length(L) / 4
			total += n
			max_bucket = max(max_bucket, n)
			for(var/i in 1 to length(L) step 4)
				var/datum/om/rec/rec = L[i]
				var/dl_key = L[i + 1]
				var/bid = dl_key % OM_DL_SUB
				var/datum/om/behaviour/B = (bid >= 1 && bid <= length(reg.behaviours)) ? reg.behaviours[bid] : null
				var/bname = B ? "[B.type]" : "bid [bid]"
				var/is_live = FALSE
				if(rec && !rec.torn_down && rec.deadlines)
					var/list/D = rec.deadlines
					for(var/j in 1 to length(D) step 3)
						if(D[j] == dl_key && D[j + 1] == L[i + 2])
							is_live = TRUE
							break
				if(is_live)
					live++
				var/owner_type = "[rec?.owner?.type]"
				by_owner[owner_type] = (by_owner[owner_type] || 0) + 1
				by_behaviour["[bname][is_live ? "" : " (stale)"]"] = (by_behaviour["[bname][is_live ? "" : " (stale)"]"] || 0) + 1
		return json_encode(list("total" = total, "live" = live, "stale" = total - live, "max_bucket" = max_bucket, "by_owner" = by_owner, "by_behaviour" = by_behaviour))

	// Localhost-only census of light source updates by source atom type (SSlighting.fire()) since the churn
	// metrics last took them (every metrics sample, or never with metrics off), top 40.
	if (diag == "lightcensus")
		var/list/census = GLOB.churn_census.lights.Copy()
		var/list/rows = list()
		for(var/source_type in census)
			rows["[source_type]"] = census[source_type]
		rows = sortTim(rows, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
		if(length(rows) > 40)
			rows.Cut(41)
		return json_encode(list("world_time" = world.time, "queued" = length(SSlighting.sources_queue), "by_type" = rows)) // ALLOW(sys_world_time_write): reports the current clock in a diagnostic reply, not a stored time

	// Localhost-only census of qdel() by type since boot (SSgarbage's per-type stats), top 40.
	if (diag == "qdelcensus")
		var/list/rows = list()
		for(var/path in SSgarbage.items)
			var/datum/qdel_item/item = SSgarbage.items[path]
			rows[item.name] = item.qdels
		rows = sortTim(rows, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
		if(length(rows) > 40)
			rows.Cut(41)
		return json_encode(list("world_time" = world.time, "by_type" = rows)) // ALLOW(sys_world_time_write): reports the current clock in a diagnostic reply, not a stored time

	// Localhost-only on-demand proc profiling for live triage: mcprof_start begins a BYOND proc +
	// sendmaps profile; mcprof_dump writes both as JSON into the round log dir (logged with their
	// paths) and returns the top 40 procs by real time as JSON; mcprof_stop ends collection.
	if (diag == "mcprof_start" || diag == "mcprof_dump" || diag == "mcprof_stop")
		if(diag == "mcprof_start")
			world.Profile(PROFILE_CLEAR)
			world.Profile(PROFILE_CLEAR, type = "sendmaps")
			world.Profile(PROFILE_START)
			world.Profile(PROFILE_START, type = "sendmaps")
			log_runtime("MCPROF: started at [world.time]")
			return "started"
		if(diag == "mcprof_stop")
			world.Profile(PROFILE_STOP)
			world.Profile(PROFILE_STOP, type = "sendmaps")
			log_runtime("MCPROF: stopped at [world.time]")
			return "stopped"
		var/proc_json = world.Profile(PROFILE_REFRESH, format = "json")
		var/stamp = "[world.time]"
		var/proc_path = "[GLOB.log_directory]/profiler/mcprof-[stamp].json"
		var/maps_path = "[GLOB.log_directory]/profiler/mcprof-sendmaps-[stamp].json"
		WRITE_FILE(file(proc_path), proc_json)
		WRITE_FILE(file(maps_path), world.Profile(PROFILE_REFRESH, type = "sendmaps", format = "json"))
		log_runtime("MCPROF: dumped [proc_path] and [maps_path]")
		var/list/top = list()
		for(var/list/row as anything in json_decode(proc_json))
			top += list(list("n" = row["name"], "self" = row["self"], "total" = row["total"], "real" = row["real"], "calls" = row["calls"]))
		sortTim(top, GLOBAL_PROC_REF(cmp_mcprof_real))
		if(length(top) > 40)
			top.Cut(41)
		return json_encode(top)

	if (T == "ping")
		var/x = 1
		for (var/client/C)
			x++
		return x

	else if(T == "players")
		var/n = 0
		for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			if(M.client)
				n++
		return n

	else if (copytext(T,1,7) == "status")
		var/input[] = params2list(T)
		var/list/s = list()
		s["version"] = GLOB.game_version
		s["mode"] = GLOB.master_mode
		s["respawn"] = CONFIG_GET(flag/abandon_allowed)
		s["persistance"] = CONFIG_GET(flag/persistence_disabled)
		s["enter"] = CONFIG_GET(flag/enter_allowed)
		s["vote"] = CONFIG_GET(flag/allow_vote_mode)
		s["ai"] = CONFIG_GET(flag/allow_ai)
		s["host"] = host ? host : null

		// This is dumb, but spacestation13.com's banners break if player count isn't the 8th field of the reply, so... this has to go here.
		s["players"] = 0
		s["stationtime"] = stationtime2text()
		s["roundduration"] = roundduration2text()
		s["map"] = strip_improper(using_map.full_name) //Done to remove the non-UTF-8 text macros

		if(input["status"] == "2") // Shiny new hip status.
			var/active = 0
			var/list/players = list()
			var/list/admins = list()

			for(var/client/C in GLOB.clients)
				if(C.holder)
					if(C.holder.fakekey)
						continue
					admins[C.key] = C.holder.rank_names()
				players += C.key
				if(isliving(C.mob))
					active++

			s["players"] = players.len
			//s["playerlist"] = list2params(players)
			s["active_players"] = active
			var/list/adm = get_admin_counts()
			var/list/presentmins = adm["present"]
			var/list/afkmins = adm["afk"]
			s["admins"] = presentmins.len + afkmins.len //equivalent to the info gotten from adminwho
			//s["adminlist"] = list2params(admins)
		else // Legacy.
			var/n = 0
			var/admins = 0

			for(var/client/C in GLOB.clients)
				if(C.holder)
					if(C.holder.fakekey)
						continue	//so stealthmins aren't revealed by the hub
					admins++
				s["player[n]"] = C.key
				n++

			s["players"] = n
			s["admins"] = admins

		return list2params(s)

	else if(T == "manifest")
		if(!SSjob.initialized)
			return null

		var/list/positions = list()
		var/list/set_names = list(
				"heads" = SSjob.get_job_titles_in_department(DEPARTMENT_COMMAND),
				"sec" = SSjob.get_job_titles_in_department(DEPARTMENT_SECURITY),
				"eng" = SSjob.get_job_titles_in_department(DEPARTMENT_ENGINEERING),
				"med" = SSjob.get_job_titles_in_department(DEPARTMENT_MEDICAL),
				"sci" = SSjob.get_job_titles_in_department(DEPARTMENT_RESEARCH),
				"car" = SSjob.get_job_titles_in_department(DEPARTMENT_CARGO),
				"pla" = SSjob.get_job_titles_in_department(DEPARTMENT_PLANET), // 
				"civ" = SSjob.get_job_titles_in_department(DEPARTMENT_CIVILIAN),
				"bot" = SSjob.get_job_titles_in_department(DEPARTMENT_SYNTHETIC)
			)

		for(var/datum/data/record/t in GLOB.data_core.general)
			var/name = t.fields["name"]
			var/rank = t.fields["rank"]
			var/real_rank = make_list_rank(t.fields["real_rank"])

			var/department = 0
			var/active = 0
			for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
				if(M.real_name == name && M.client && M.client.inactivity <= 10 MINUTES)
					active = 1
					break
			var/isactive = active ? "Active" : "Inactive"
			for(var/k in set_names)
				if(real_rank in set_names[k])
					if(!positions[k])
						positions[k] = list()
					positions[k][name] = list(rank,isactive)
					department = 1
			if(!department)
				if(!positions["misc"])
					positions["misc"] = list()
				positions["misc"][name] = list(rank,isactive)

		for(var/datum/data/record/t in GLOB.data_core.hidden_general)
			var/name = t.fields["name"]
			var/rank = t.fields["rank"]
			var/real_rank = make_list_rank(t.fields["real_rank"])

			var/active = 0
			for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
				if(M.real_name == name && M.client && M.client.inactivity <= 10 MINUTES)
					active = 1
					break
			var/isactive = active ? "Active" : "Inactive"

			var/datum/job/J = SSjob.get_job(real_rank)
			if(J?.offmap_spawn)
				if(!positions["off"])
					positions["off"] = list()
				positions["off"][name] = list(rank,isactive)

		// Synthetics don't have actual records, so we will pull them from here.
		for(var/mob/living/silicon/ai/ai in REGISTRY_MEMBERS(REGISTRY_MOBS))
			var/isactive = (ai.client && ai.client.inactivity <= 10 MINUTES) ? "Active" : "Inactive"
			if(!positions["bot"])
				positions["bot"] = list()
			positions["bot"][ai.name] = list("Artificial Intelligence",isactive)
		for(var/mob/living/silicon/robot/robot in REGISTRY_MEMBERS(REGISTRY_MOBS))
			// No combat/syndicate cyborgs, no drones, and no AI shells.
			var/isactive = (robot.client && robot.client.inactivity <= 10 MINUTES) ? "Active" : "Inactive"
			if(robot.shell)
				continue
			if(robot.module && robot.module.hide_on_manifest())
				continue
			if(!positions["bot"])
				positions["bot"] = list()
			positions["bot"][robot.name] = list("[robot.modtype] [robot.braintype]",isactive) // end

		for(var/k in positions)
			positions[k] = list2params(positions[k]) // converts positions["heads"] = list("Bob"="Captain", "Bill"="CMO") into positions["heads"] = "Bob=Captain&Bill=CMO"

		return list2params(positions)

	else if(T == "revision")
		if(GLOB.revdata.commit)
			return list2params(list(testmerge = GLOB.revdata.testmerge, date = GLOB.revdata.date, commit = GLOB.revdata.commit, originmastercommit = GLOB.revdata.originmastercommit))
		else
			return "unknown"

/// Returns TRUE if the world should do a TGS hard reboot.
/world/proc/check_hard_reboot()
	if(!TgsAvailable())
		return FALSE
	// byond-tracy can't clean up itself, and thus we should always hard reboot if its enabled, to avoid an infinitely growing trace.
	//if(Tracy?.enabled)
	//	return TRUE
	var/ruhr = CONFIG_GET(number/rounds_until_hard_restart)
	switch(ruhr)
		if(-1)
			return FALSE
		if(0)
			return TRUE
		else
			if(GLOB.restart_counter >= ruhr)
				return TRUE
			else
				text2file("[++GLOB.restart_counter]", RESTART_COUNTER_PATH)
				return FALSE

/world/proc/FinishTestRun()
	var/list/fail_reasons
	if(GLOB)
		if(GLOB.total_runtimes != 0)
			fail_reasons = list("Total runtimes: [GLOB.total_runtimes]")
#ifdef UNIT_TESTS
		if(GLOB.failed_any_test)
			LAZYADD(fail_reasons, "Unit Tests failed!")
		if(GLOB.boot_unclean)
			LAZYADD(fail_reasons, GLOB.boot_unclean)
#endif
		if(!GLOB.log_directory)
			LAZYADD(fail_reasons, "Missing GLOB.log_directory!")
	else
		fail_reasons = list("Missing GLOB!")
	if(!fail_reasons)
		text2file("Success!", "[GLOB.log_directory]/clean_run.lk")
	else
		log_world("Test run failed!\n[fail_reasons.Join("\n")]")
	// Shut down once Reboot() has returned (the MC is already down, so this is a world tick
	// callback, not a timer): deleting the world from inside Reboot() leaves byond in a bad way.
	world_next_tick(om_callable(null, GLOBAL_PROC_REF(world_finish_test_shutdown)))

/proc/world_finish_test_shutdown()
	spent(world) //shut it down

/// Callbacks run at the start of the next world tick (/world/Tick()), in order. For world procs
/// whose follow-up must run after they return, including after the MC has shut down.
GLOBAL_LIST_EMPTY(world_next_tick_callbacks)

/// `spec` is an om_callable() spec.
/proc/world_next_tick(list/spec)
	GLOB.world_next_tick_callbacks += list(spec)

/// The last DM code of every tick: the MC and every sleeping proc due this tick have run, the map send
/// has not. The tick frame (metrics_capture.dm) splits the tick's time at the MC here.
/world/Tick()
	if(!GLOB)
		return
	var/datum/tick_frame/frame = GLOB.tick_frame
	frame?.frame_end(TICK_USAGE)
	if(!length(GLOB.world_next_tick_callbacks))
		return
	var/started = TICK_USAGE
	var/list/due = GLOB.world_next_tick_callbacks
	GLOB.world_next_tick_callbacks = list()
	for(var/list/spec as anything in due)
		om_run_async(spec)
	if(frame)
		frame.callbacks += max(TICK_USAGE - started, 0)

/world/Reboot(reason = 0, fast_track = FALSE)
	if (reason || fast_track) //special reboot, do none of the normal stuff
		if (usr)
			log_admin("[key_name(usr)] Has requested an immediate world restart via client side debugging tools")
			message_admins("[key_name_admin(usr)] Has requested an immediate world restart via client side debugging tools")
			to_chat(world, span_boldannounce("[key_name_admin(usr)] has requested an immediate world restart via client side debugging tools"))

		else
			to_chat(world, span_boldannounce("Rebooting world immediately due to host request"))
	else
		Kernel.shutdown_kernel()	//run the systems' shutdowns
		for(var/client/C in GLOB.clients)
			if(CONFIG_GET(string/server))	//if you set a server location in config.txt, it sends you there instead of trying to reconnect to the same world address. -- NeoFite
				C << link("byond://[CONFIG_GET(string/server)]")

	#ifdef UNIT_TESTS
	FinishTestRun()
	return
	#else
	if(check_hard_reboot())
		log_world("World hard rebooted at [time_stamp()]")
		shutdown_logging() // See comment below.
		TgsEndProcess()
		return ..()

	log_world("World rebooted at [time_stamp()]")

	shutdown_logging() // Past this point, no logging procs can be used, at risk of data loss.
	QDEL_NULL(Tracy)
	QDEL_NULL(Debugger)

	TgsReboot() // TGS can decide to kill us right here, so it's important to do it last

	..()
	#endif

/world/Del()
	// Joins verdigris' frame and job threads before BYOND unloads the DLL.
	vg_world_shutdown()
	QDEL_NULL(Tracy)
	QDEL_NULL(Debugger)
	. = ..()

/hook/startup/proc/loadMode()
	world.load_mode()
	return 1

/world/proc/load_mode()
	if(!fexists("data/mode.txt"))
		return


	var/list/Lines = file2list("data/mode.txt")
	if(Lines.len)
		if(Lines[1])
			GLOB.master_mode = Lines[1]
			log_world("## MISC Saved mode is '[GLOB.master_mode]'")

/world/proc/save_mode(the_mode)
	var/F = file("data/mode.txt")
	fdel(F)
	F << the_mode

/world/proc/update_status()
	var/s = ""

	if (config && CONFIG_GET(string/servername))
		s += span_bold("[CONFIG_GET(string/servername)]") + " &#8212; "

	s += span_bold("[station_name()]");
	s += " ("
	s += "<a href=\"https://\">" //Change this to wherever you want the hub to link to.
	s += "Default"  //Replace this with something else. Or ever better, delete it and uncomment the game version.
	s += "</a>"
	s += ")"

	var/list/features = list()

	if(SSticker)
		if(GLOB.master_mode)
			features += GLOB.master_mode
	else
		features += span_bold("STARTING")

	if (!CONFIG_GET(flag/enter_allowed))
		features += "closed"

	features += CONFIG_GET(flag/abandon_allowed) ? "respawn" : "no respawn"

	features += CONFIG_GET(flag/persistence_disabled) ? "persistence disabled" : "persistence enabled"

	features += CONFIG_GET(flag/persistence_ignore_mapload) ? "persistence mapload disabled" : "persistence mapload enabled"

	if (config && CONFIG_GET(flag/allow_vote_mode))
		features += "vote"

	if (config && CONFIG_GET(flag/allow_ai))
		features += "AI allowed"

	var/n = 0
	for (var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if (M.client)
			n++

	if (n > 1)
		features += "~[n] players"
	else if (n > 0)
		features += "~[n] player"


	if (config && CONFIG_GET(string/hostedby))
		features += "hosted by <b>[CONFIG_GET(string/hostedby)]</b>"

	if (features)
		s += ": [jointext(features, ", ")]"

	/* does this help? I do not know */
	if (src.status != s)
		src.status = s

// Things to do when a new z-level was just made.
/world/proc/max_z_changed()
	if(!istype(GLOB.players_by_zlevel, /list))
		GLOB.players_by_zlevel = new /list(world.maxz, 0)
		GLOB.living_players_by_zlevel = new /list(world.maxz, 0)

	while(GLOB.players_by_zlevel.len < world.maxz)
		GLOB.players_by_zlevel.len++
		GLOB.players_by_zlevel[GLOB.players_by_zlevel.len] = list()

		GLOB.living_players_by_zlevel.len++
		GLOB.living_players_by_zlevel[GLOB.living_players_by_zlevel.len] = list()

/**
 * Handles increasing the world's maxx var and initializing the new turfs and assigning them to the global area.
 * If map_load_z_cutoff is passed in, it will only load turfs up to that z level, inclusive.
 * This is because maploading will handle the turfs it loads itself.
 */
/world/proc/increase_max_x(new_maxx, map_load_z_cutoff = maxz)
	if(new_maxx <= maxx)
		return
	maxx = new_maxx
	// if(!map_load_z_cutoff)
	// 	return
	// var/area/global_area = GLOB.areas_by_type[world.area] // We're guaranteed to be touching the global area, so we'll just do this
	// LISTASSERTLEN(global_area.turfs_by_zlevel, map_load_z_cutoff, list())
	// for (var/zlevel in 1 to map_load_z_cutoff)
	// 	var/list/to_add = block(
	// 		old_max + 1, 1, zlevel,
	// 		maxx, maxy, zlevel
	// 	)

	// 	global_area.turfs_by_zlevel[zlevel] += to_add

/world/proc/increase_max_y(new_maxy, map_load_z_cutoff = maxz)
	if(new_maxy <= maxy)
		return
	maxy = new_maxy
	// if(!map_load_z_cutoff)
	// 	return
	// var/area/global_area = GLOB.areas_by_type[world.area] // We're guaranteed to be touching the global area, so we'll just do this
	// LISTASSERTLEN(global_area.turfs_by_zlevel, map_load_z_cutoff, list())
	// for (var/zlevel in 1 to map_load_z_cutoff)
	// 	var/list/to_add = block(
	// 		1, old_maxy + 1, 1,
	// 		maxx, maxy, map_load_z_cutoff
	// 	)
	// 	global_area.turfs_by_zlevel[zlevel] += to_add

// Call this to make a new blank z-level, don't modify maxz directly.
// Allocate a new top z-level and return its index. The return is captured
// BEFORE max_z_changed() runs, so even if that yields and another
// allocation happens, this call still reports the z it created — callers
// can rely on it instead of re-reading world.maxz across a yield.
/world/proc/increment_max_z()
	maxz++
	. = maxz
	vg_configure_world(maxx, maxy, maxz)
	max_z_changed()

// Call this to change world.fps, don't modify it directly.
/world/proc/change_fps(new_value = 40)
	if(new_value <= 0)
		CRASH("change_fps() called with [new_value] new_value.")
	if(fps == new_value)
		return //No change required.

	fps = new_value
	on_tickrate_change()

// Called whenver world.tick_lag or world.fps are changed.
/world/proc/on_tickrate_change()
	return

/proc/auxtools_stack_trace(msg)
	CRASH(msg)

/proc/auxtools_expr_stub()
	CRASH("auxtools not loaded")

/proc/enable_debugging(mode, port)
	CRASH("auxtools not loaded")

/world/Profile(command, type, format)
	if((command & PROFILE_STOP) || !global.config?.loaded || !CONFIG_GET(flag/forbid_all_profiling))
		. = ..()

#undef NO_INIT_PARAMETER
#undef OVERRIDE_LOG_DIRECTORY_PARAMETER
#undef USE_TRACY_PARAMETER
#undef RESTART_COUNTER_PATH

/proc/cmp_mcprof_real(list/a, list/b)
	return b["real"] - a["real"]

/// The diagnostic probe a world/Topic call asks for ("mcdiag", "omsteps", ...), or null unless it
/// comes from localhost and, when DIAG_TOPIC_KEY is set, carries key=<it>.
/proc/diag_topic_command(T, addr)
	if(addr != "127.0.0.1" && findtext(addr, "127.0.0.1:") != 1)
		return null
	var/list/topic_params = params2list(T)
	if(!length(topic_params))
		return null
	var/required_key = config?.entries ? CONFIG_GET(string/diag_topic_key) : null
	if(required_key && topic_params["key"] != required_key)
		return null
	return topic_params[1]
