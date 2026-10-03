#define PING_BUFFER_TIME 25
/// Cadence of the every() item, in ticks (was the subsystem's wait).
#define SERVER_MAINT_INTERVAL 6

// Server housekeeping (was SSserver_maint): wipes tmp/ at boot and shutdown, clears nulls from the
// global mob lists and refreshes client pings every 6 ticks.
SYSTEM_DEF(server_maint)
	name = "Server Tasks"
	needs = list(/datum/system/garbage)
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	/// TRUE while a pass that ran out of budget waits to resume.
	VAR_PRIVATE/resuming = FALSE
	var/list/currentrun
	///Associated list of list names to lists to clear of nulls
	var/list/lists_to_clear
	///Delay between list clearings in ticks
	var/delay = 5
	var/cleanup_ticker = 0

/datum/system/server_maint/reactions()
	. = ..()
	. += every(SERVER_MAINT_INTERVAL, PROC_REF(maintain), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/server_maint/initialize()
	initialized = TRUE
	// A sharded dm-test run boots N worlds sharing this worktree's tmp/, each
	// still actively using it (icon2base64's dummy savefiles, universal_icon's
	// scratch .dmi files, ...); wiping it out from under a sibling shard was the
	// root cause of "cannot open savefile buffer dummy for write" under --shards.
	// Only the un-sharded case (the overwhelming majority of runs) still gets the
	// old wipe-on-boot behavior.
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	if (GLOB.dq_test_shard_count <= 1 && fexists("tmp/"))
#else
	if (fexists("tmp/"))
#endif
		fdel("tmp/")
	//if (CONFIG_GET(flag/hub))
		//world.update_hub_visibility(TRUE)
	//Keep in mind, because of how delay works adding a list here makes each list take wait * delay more time to clear
	//Do it for stuff that's properly important, and shouldn't have null checks inside its other uses
	lists_to_clear = list(
		"player_list" = REGISTRY_MEMBERS(REGISTRY_PLAYERS),
		"mob_list" = REGISTRY_MEMBERS(REGISTRY_MOBS),
		"living_mob_list" = REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS),
		"dead_mob_list" = REGISTRY_MEMBERS(REGISTRY_DEAD_MOBS),
		"observer_mob_list" = REGISTRY_MEMBERS(REGISTRY_OBSERVERS),
		"listening_objects" = REGISTRY_MEMBERS(REGISTRY_LISTENING_OBJECTS),
		"human_mob_list" = REGISTRY_MEMBERS(REGISTRY_HUMANS),
		"silicon_mob_list" = REGISTRY_MEMBERS(REGISTRY_SILICONS),
		"ai_list" = REGISTRY_MEMBERS(REGISTRY_AIS),
		//"keyloop_list" = global.keyloop_list, //A null here will cause new clients to be unable to move. totally unacceptable
	)

	/*var/datum/tgs_version/tgsversion = world.TgsVersion()
	if(tgsversion)
		SSblackbox.record_feedback("text", "server_tools", 1, tgsversion.raw_parameter)*/


/datum/system/server_maint/proc/maintain(dt)
	var/resumed = resuming
	resuming = FALSE
	if(!resumed)
		if(list_clear_nulls(GLOB.clients))
			log_world("Found a null in clients list!")
		src.currentrun = GLOB.clients.Copy()

		var/position_in_loop = (cleanup_ticker / delay) + 1	 //Index at 1, thanks byond

		if(!(position_in_loop % 1)) //If it's a whole number
			var/listname = lists_to_clear[position_in_loop]
			if(list_clear_nulls(lists_to_clear[listname]))
				log_world("Found a null in [listname]!")

		cleanup_ticker++

		var/amount_to_work = length(lists_to_clear)
		if(cleanup_ticker >= amount_to_work * delay) //If we've already done a loop, reset
			cleanup_ticker = 0

	var/list/currentrun = src.currentrun

	for(var/I in currentrun)
		var/client/C = I
		//handle kicking inactive players

		if (!(!C || ELAPSED_SINCE(src, C.connection_time, CLOCK_WORLD) < PING_BUFFER_TIME || C.inactivity >= (SERVER_MAINT_INTERVAL - 1)))
			winset(C, null, "command=.update_ping+[num2text(world.time+world.tick_lag*TICK_USAGE_REAL/100, 32)]")

		if(KERNEL_OVER_BUDGET) //one day, when ss13 has 1000 people per server, you guys are gonna be glad I added this budget check
			resuming = TRUE
			return STEP_YIELD
	return STEP_DONE

/datum/system/server_maint/on_shutdown()
	// See the matching guard in initialize(): a sharded run's worlds share tmp/
	// with siblings that may still be running.
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	if (GLOB.dq_test_shard_count <= 1 && fexists("tmp/"))
#else
	if (fexists("tmp/"))
#endif
		fdel("tmp/")
	//kick_clients_in_lobby(span_boldannounce("The round came to an end with you in the lobby."), TRUE) //second parameter ensures only afk clients are kicked
	var/server = CONFIG_GET(string/server)
	for(var/thing in GLOB.clients)
		if(!thing)
			continue
		var/client/C = thing
		C?.tgui_panel?.send_roundrestart()
		if(server) //if you set a server location in config.txt, it sends you there instead of trying to reconnect to the same world address. -- NeoFite
			C << link("byond://[server]")

#undef PING_BUFFER_TIME

#undef SERVER_MAINT_INTERVAL
