SYSTEM_DEF(ticker)
	name = "Ticker"
	phase = KERNEL_PHASE_K
	latency_class = LATENCY_L0
	init_stage = INITSTAGE_MAIN
	wait = 2 SECONDS
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVEL_SETUP | RUNLEVEL_GAME

	/// state of current round (used by process()) Use the defines GAME_STATE_* !
	var/current_state = GAME_STATE_STARTUP
	/// Boolean to track if round should be forcibly ended next ticker tick.
	/// Set by admin intervention ([ADMIN_FORCE_END_ROUND])
	/// or a "round-ending" event, like summoning Nar'Sie, a blob victory, the nuke going off, etc. ([FORCE_END_ROUND])
	var/force_ending = END_ROUND_AS_NORMAL
	/// If TRUE, there is no lobby phase, the game starts immediately.
	var/start_immediately = FALSE
	/// Boolean to track and check if our subsystem setup is done.
	var/setup_done = FALSE

	var/hide_mode = FALSE
	var/datum/game_mode/mode = null

	var/login_music //music played in pregame lobby
	var/round_end_sound //music/jingle played when the world reboots
	var/round_end_sound_sent = TRUE //If all clients have loaded it

	var/list/datum/mind/minds = list() //The characters in the game. Used for objective tracking.

	var/delay_end = FALSE //if set true, the round will not restart on it's own
	var/admin_delay_notice = "" //a message to display to anyone who tries to restart the world after a delay
	var/ready_for_reboot = FALSE //all roundend preparation done with, all that's left is reboot

	var/tipped = FALSE //Did we broadcast the tip of the day yet?
	var/selected_tip // What will be the tip of the day?

	var/timeLeft //pregame timer
	EXPIRY_DECLARE(start_at)

	var/gametime_offset = 432000 //Deciseconds to add to world.time for station time.
	var/station_time_rate_multiplier = 12 //factor of station time progressal vs real time.

	/// Num of players, used for pregame stats on statpanel
	var/totalPlayers = 0
	/// Num of ready players, used for pregame stats on statpanel (only viewable by admins)
	var/totalPlayersReady = 0
	/// Num of ready admins, used for pregame stats on statpanel (only viewable by admins)
	var/total_admins_ready = 0

	var/queue_delay = 0
	var/list/queued_players = list() //used for join queues when the server exceeds the hard population cap

	/// What is going to be reported to other stations at end of round?
	var/news_report

	var/roundend_check_paused = FALSE

	EXPIRY_DECLARE(round_start_time)
	var/list/round_start_events
	var/list/round_end_events
	var/mode_result = "undefined"
	var/end_state = "undefined"

	/// People who have been commended and will receive a heart
	var/list/hearts

	/// Why an emergency shuttle was called
	var/emergency_reason


	/// ### LEGACY VARS ###
	/// Default time to wait before rebooting in desiseconds.
	var/const/restart_timeout = 4 MINUTES
	/// Track where we are ending game/round
	var/end_game_state = END_GAME_NOT_OVER
	/// Time remaining until restart in desiseconds
	var/restart_timeleft
	/// world.time of last restart warning.
	EXPIRY_DECLARE(last_restart_notify)

/// Time left until a scheduled reboot; announce_countdown() counts it down while it is above zero.
/datum/system/ticker/var/tmp/reboot_countdown_left = 0

/// Sets the time left and arms (or, at zero, cancels) the countdown's next announcement.
/datum/system/ticker/proc/set_reboot_countdown_left(value)
	reboot_countdown_left = value
	if(value > 0)
		after(src, reboot_countdown_delay(), PROC_REF(announce_countdown), key = "reboot_countdown")
	else
		cancel_after(src, "reboot_countdown")

/datum/system/ticker/initialize()
	lifecycle_decls_init(src) // a non-atom has no materialize
	EXPIRY_SET(src, start_at, (CONFIG_GET(number/lobby_countdown) * 10), CLOCK_WORLD)

/// The round state machine runs every `wait` (phase K).
/datum/system/ticker/reactions()
	. = ..()
	. += every(2 SECONDS, PROC_REF(round_step), when = PROC_REF(work_ready), phase = KERNEL_PHASE_K, lane = LANE_SIMULATION)

/datum/system/ticker/proc/round_step(dt)
	switch(current_state)
		if(GAME_STATE_STARTUP)
			EXPIRY_SET(src, start_at, (CONFIG_GET(number/lobby_countdown) * 10), CLOCK_WORLD)
			for(var/client/C in GLOB.clients)
				window_flash(C, ignorepref = TRUE) //let them know lobby has opened up.
			to_chat(world, span_boldnotice("Welcome to [station_name()]!"))
			for(var/channel_tag in CONFIG_GET(str_list/channel_announce_new_game))
				send2chat(new /datum/tgs_message_content("New round starting on [using_map.full_name] ([using_map.name])!"), channel_tag)
			current_state = GAME_STATE_PREGAME

			round_step(0)
		if(GAME_STATE_PREGAME)
			//lobby stats for statpanels
			if(isnull(timeLeft))
				timeLeft = max(0,start_at - world.time)
				to_chat(world, span_notice("Round starting in [round(timeLeft / 10)] Seconds!"))
			totalPlayers = REGISTRY_COUNT(REGISTRY_NEW_PLAYERS)
			totalPlayersReady = 0
			total_admins_ready = 0
			for(var/mob/new_player/player as anything in REGISTRY_MEMBERS(REGISTRY_NEW_PLAYERS))
				if(player.ready == PLAYER_READY_TO_PLAY)
					++totalPlayersReady
					if(player.client?.holder)
						++total_admins_ready

			if(start_immediately)
				timeLeft = 0

			//countdown
			if(timeLeft < 0)
				return

			// Do not count down the time, if the game start is delayed
			if (GLOB.round_progressing)
				timeLeft -= wait

			if(timeLeft <= 0)
				current_state = GAME_STATE_SETTING_UP
				Kernel.SetRunLevel(RUNLEVEL_SETUP)
				if(start_immediately)
					round_step(0)

		if(GAME_STATE_SETTING_UP)
			if(!setup())
				//setup failed
				current_state = GAME_STATE_STARTUP
				EXPIRY_SET(src, start_at, (CONFIG_GET(number/lobby_countdown) * 10), CLOCK_WORLD)
				timeLeft = null
				Kernel.SetRunLevel(RUNLEVEL_LOBBY)

		if(GAME_STATE_PLAYING)
			// The mode's own periodic work (latespawn, meteor waves) runs on the slow lane,
			// started when the round starts (setup()).
			if(mode.explosion_in_progress)
				return // wait until explosion is done.

			if(force_ending)
				current_state = GAME_STATE_FINISHED
				om_task_periodic_stop(mode)
				declare_completion(force_ending)
				Kernel.SetRunLevel(RUNLEVEL_POSTGAME)
			else
				// Calculate if game and/or mode are finished (Complicated by the continuous_rounds config option)
				var/game_finished = FALSE
				var/mode_finished = FALSE
				if (CONFIG_GET(flag/continuous_rounds)) // Game keeps going after mode ends.
					game_finished = (SSemergency_shuttle.returned() || mode.station_was_nuked)
					mode_finished = ((end_game_state >= END_GAME_MODE_FINISHED) || mode.check_finished()) // Short circuit if already finished.
				else // Game ends when mode does
					game_finished = (mode.check_finished() || (SSemergency_shuttle.returned() && SSemergency_shuttle.evac)) || GLOB.universe_has_ended
					mode_finished = game_finished

				if(game_finished && mode_finished)
					end_game_state = END_GAME_READY_TO_END
					current_state = GAME_STATE_FINISHED
					om_task_periodic_stop(mode)
					Kernel.SetRunLevel(RUNLEVEL_POSTGAME)
					declare_completion() // its SQL and TGS chat run off-thread (io_job, send2chat)
				else if (mode_finished && (end_game_state < END_GAME_MODE_FINISHED))
					end_game_state = END_GAME_MODE_FINISHED // Only do this cleanup once!
					mode.cleanup()
					//call a transfer shuttle vote
					to_chat(world, span_boldannounce("The round has ended!"))
					SSvote.start_vote(new /datum/vote/crew_transfer)

		// FIXME: IMPROVE THIS LATER!
		if(GAME_STATE_FINISHED)
			post_game_tick()

			if (ELAPSED(src, last_restart_notify, CLOCK_WORLD) >= 1 MINUTE && !delay_end)
				to_chat(world, span_boldannounce("Restarting in [round(restart_timeleft/600, 1)] minute\s."))
				EXPIRY_STAMP(src, last_restart_notify, CLOCK_WORLD)

/datum/system/ticker/proc/setup()
	to_chat(world, span_boldannounce("Starting game..."))
	var/init_start = world.timeofday
#ifdef BENCHMARK
	benchmark_rust_mark("ticker: setup start")
#endif

	CHECK_TICK
	setup_choose_gamemode()
	// TODO

	CHECK_TICK
	setup_economy()
	create_characters() //Create player characters
	collect_minds()
	equip_characters()


	for(var/list/spec as anything in round_start_events)
		om_run_async(spec)
	LAZYCLEARLIST(round_start_events)

	//otherwise round_start_time would be 0 for the signals
	EXPIRY_STAMP(src, round_start_time, CLOCK_WORLD)
	GLOB.round_start_time = REALTIMEOFDAY
	SSserver_metrics.round_started()

	// Spawn randomized items
	spawn_multi_point_items()

	// Place empty AI cores once we know who is playing AI
	for(var/obj/effect/landmark/start/S in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		if(S.name != JOB_AI)
			continue
		if(locate_within(S.loc, /mob/living))
			continue
		registry_join(REGISTRY_EMPTY_AI_CORES, new /obj/structure/AIcore/deactivated(get_turf(S)))

	// Final init, these things need round to start for their info to be ready
	for(var/obj/item/paper/dockingcodes/dcp as anything in REGISTRY_MEMBERS(REGISTRY_DOCKING_CODE_PAPERS))
		dcp.populate_info()
	for(var/obj/machinery/power/solar_control/SC as anything in REGISTRY_MEMBERS(REGISTRY_SOLAR_CONTROLS))
		SC.auto_start()

	log_world("Game start took [(world.timeofday - init_start)/10]s")
	SSdbcore.SetRoundStart() // an io_job write; returns at once

	to_chat(world, span_notice(span_bold("Welcome to [station_name()], enjoy your stay!")))
	play_simple_announcement(world, ANNOUNCER_MSG_ROUND_START)

	current_state = GAME_STATE_PLAYING
	om_task_periodic(mode, PERIODIC_SLOW)
	Kernel.SetRunLevel(RUNLEVEL_GAME)

	//Holiday Round-start stuff	~Carn
	Holiday_Game_Start()

	// TODO END

	PostSetup()
#ifdef BENCHMARK
	benchmark_rust_mark("ticker: setup done")
	benchmark_mark_seconds(14)
#endif

	return TRUE

/datum/system/ticker/proc/PostSetup()
	mode.post_setup()
	// TODO

	var/list/adm = get_admin_counts()
	var/list/allmins = adm["present"]
	send2adminchat("Server", "Round [GLOB.round_id ? "#[GLOB.round_id]" : ""] has started[length(allmins) ? ".":" with no active admins online!"]")

	setup_done = TRUE
	// TODO START

	// TODO END
	for(var/obj/effect/landmark/start/S in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		//Deleting Startpoints but we need the ai point to AI-ize people later
		if (S.name != "AI")
			spent(S)

	if(CONFIG_GET(flag/sql_enabled))
		statistic_cycle() // Polls population totals regularly and stores them in an SQL DB -- TLE

//These callbacks will fire after roundstart key transfer
/// `spec` is an om_callable() spec.
/datum/system/ticker/proc/OnRoundstart(list/spec)
	if(!HasRoundStarted())
		LAZYADD(round_start_events, list(spec))
	else
		om_run_async(spec)

//These callbacks will fire before roundend report
/datum/system/ticker/proc/OnRoundend(datum/callback/cb)
	if(current_state >= GAME_STATE_FINISHED)
		cb.InvokeAsync()
	else
		LAZYADD(round_end_events, cb)

// Formerly the first half of setup() - The part that chooses the game mode.
// Returns 0 if failed to pick a mode, otherwise 1
/datum/system/ticker/proc/setup_choose_gamemode()
	//Create and announce mode
	if(GLOB.master_mode == "secret")
		src.hide_mode = TRUE

	var/list/runnable_modes = config.get_runnable_modes()
	if((GLOB.master_mode == "random") || (GLOB.master_mode == "secret"))
		if(!length(runnable_modes))
			to_chat(world, span_filter_system(span_bold("Unable to choose playable game mode.") + " Reverting to pregame lobby."))
			return 0
		if(GLOB.secret_force_mode != "secret")
			src.mode = config.pick_mode(GLOB.secret_force_mode)
		if(!src.mode)
			var/list/weighted_modes = list()
			for(var/datum/game_mode/GM in runnable_modes)
				weighted_modes[GM.config_tag] = CONFIG_GET(keyed_list/probabilities)[GM.config_tag]
			src.mode = config.gamemode_cache[pickweight(weighted_modes)]
	else
		src.mode = config.pick_mode(GLOB.master_mode)

	if(!src.mode)
		to_chat(world, span_boldannounce("Serious error in mode setup! Reverting to pregame lobby.")) //Uses setup instead of set up due to computational context.
		return 0

	SSjob.reset_occupations()
	src.mode.create_antagonists()
	src.mode.pre_setup()
	SSjob.divide_occupations() // Apparently important for new antagonist system to register specific job antags properly.

	if(!src.mode.can_start())
		to_chat(world, span_filter_system(span_bold("Unable to start [mode.name].") + " Not enough players readied, [CONFIG_GET(keyed_list/player_requirements)[mode.config_tag]] players needed. Reverting to pregame lobby."))
		mode.fail_setup()
		mode = null
		SSjob.reset_occupations()
		return 0

	if(hide_mode)
		to_chat(world, span_world(span_notice("The current game mode is - Secret!")))
		if(length(runnable_modes))
			var/list/tmpmodes = list()
			for (var/datum/game_mode/M in runnable_modes)
				tmpmodes+=M.name
			tmpmodes = sortList(tmpmodes)
			if(length(tmpmodes))
				to_chat(world, span_filter_system(span_bold("Possibilities:") + " [english_list(tmpmodes, and_text= "; ", comma_text = "; ")]"))
	else
		src.mode.announce()
	return 1

// Called during GAME_STATE_FINISHED (RUNLEVEL_POSTGAME)
/datum/system/ticker/proc/post_game_tick()
	switch(end_game_state)
		if(END_GAME_READY_TO_END)
			callHook("roundend") // TODO, remove all hooks that use this in favor of global signal

			if (mode.station_was_nuked)
				feedback_set_details("end_proper", "nuke")
				restart_timeleft = 1 MINUTE // No point waiting five minutes if everyone's dead.
				if(!delay_end)
					to_chat(world, span_boldannounce("Rebooting due to destruction of [station_name()] in [round(restart_timeleft/600)] minute\s."))
					EXPIRY_STAMP(src, last_restart_notify, CLOCK_WORLD)
			else
				feedback_set_details("end_proper", "proper completion")
				restart_timeleft = restart_timeout

			if(GLOB.blackbox)
				GLOB.blackbox.save_all_data_to_sql()	// TODO - Blackbox or statistics subsystem

			end_game_state = END_GAME_ENDING
			return

/datum/system/ticker/proc/create_characters()
	for(var/mob/new_player/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(player && player.ready && player.mind?.assigned_role)
			var/datum/job/J = SSjob.get_job(player.mind.assigned_role)

			// Ask their new_player mob to spawn them
			if(!player.spawn_checks_vr(player.mind.assigned_role))
				var/datum/job/job_datum = SSjob.get_job(J.title)
				job_datum.current_positions--
				player.mind.assigned_role = null
				continue

			// Snowflakey AI treatment
			if(J?.mob_type & JOB_SILICON_AI)
				player.close_spawn_windows()
				player.AIize(move = TRUE)
				continue

			var/mob/living/carbon/human/new_char = player.create_character()

			// Created their playable character, delete their /mob/new_player
			if(new_char)
				replaced_by(player, new_char)
				if(new_char.client)
					new_char.client.init_verbs()

			// If they're a carbon, they can get manifested
			if(J?.mob_type & JOB_CARBON)
				GLOB.data_core.manifest_inject(new_char)
		CHECK_TICK

/datum/system/ticker/proc/collect_minds()
	for(var/mob/living/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(player.mind)
			minds += player.mind
		CHECK_TICK

/datum/system/ticker/proc/equip_characters()
	var/captainless=1
	for(var/mob/living/carbon/human/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(player && player.mind && player.mind.assigned_role)
			if(player.mind.assigned_role == JOB_SITE_MANAGER)
				captainless=0
			if(!SSantag.player_is_antag(player.mind, only_offstation_roles = 1))
				SSjob.equip_rank(player, player.mind.assigned_role, 0)
				UpdateFactionList(player)
				// equip_custom_items(player) // Removal
				// player.apply_traits() // Removal
		// ition Start
		if(player.client)
			if(player.client.prefs.read_preference(/datum/preference/toggle/human/auto_backup_implant)) // migrated pref
				var/obj/item/implant/backup/imp = new(src)

				if(imp.handle_implant(player,player.zone_sel.selecting))
					imp.post_implant(player)
		// ition End
		CHECK_TICK
	if(captainless)
		for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			if(!isnewplayer(M))
				to_chat(M, span_notice("Site Management is not forced on anyone."))

///Whether the game has started, including roundend.
/datum/system/ticker/proc/HasRoundStarted()
	return current_state >= GAME_STATE_PLAYING

///Whether the game is currently in progress, excluding roundend
/datum/system/ticker/proc/IsRoundInProgress()
	return current_state == GAME_STATE_PLAYING

///Whether the game is currently in progress, excluding roundend
/datum/system/ticker/proc/IsPostgame()
	return current_state == GAME_STATE_FINISHED

/// Puts the Master's run level back where the round state says it is (a recreated Master starts at the lobby's).
/datum/system/ticker/proc/restore_runlevel()
	if (Kernel)
		switch (current_state)
			if(GAME_STATE_SETTING_UP)
				Kernel.SetRunLevel(RUNLEVEL_SETUP)
			if(GAME_STATE_PLAYING)
				Kernel.SetRunLevel(RUNLEVEL_GAME)
			if(GAME_STATE_FINISHED)
				Kernel.SetRunLevel(RUNLEVEL_POSTGAME)

/datum/system/ticker/proc/Reboot(reason, end_string, delay)
	set waitfor = FALSE // ALLOW(scheduler): UNTIL waits on the round-end sound before arming the reboot timer
	if(usr && !check_rights(R_SERVER, TRUE))
		return

	if(!delay)
		delay = CONFIG_GET(number/round_end_countdown) SECONDS
		if(delay >= 60 SECONDS)
			set_reboot_countdown_left(delay)

	var/skip_delay = check_rights()
	if(delay_end && !skip_delay)
		to_chat(world, span_boldannounce("An admin has delayed the round end."))
		return

	to_chat(world, span_boldannounce("Rebooting World in [DisplayTimeText(delay)]. [reason]"))

	var/start_wait = world.time
	UNTIL(round_end_sound_sent || ELAPSED_SINCE(src, start_wait, CLOCK_WORLD) > (delay * 2)) //don't wait forever
	after(src, delay - (world.time - start_wait), PROC_REF(reboot_callback), key = "reboot_timer", with = list(reason, end_string))

/// The wait before the next countdown step: a minute, or what is left of the last one.
/datum/system/ticker/proc/reboot_countdown_delay()
	return min(60 SECONDS, reboot_countdown_left)

/// One countdown step (re-armed by set_reboot_countdown_left() while time is left).
/datum/system/ticker/proc/announce_countdown()
	var/remaining_time = reboot_countdown_left - reboot_countdown_delay()
	if(remaining_time > 0)
		set_reboot_countdown_left(remaining_time)
		if(remaining_time > 60 SECONDS)
			to_chat(world, span_boldannounce("Rebooting World in [DisplayTimeText(remaining_time)]."))
		return
	set_reboot_countdown_left(0)
	if(!delay_end)
		to_chat(world, span_boldannounce("Rebooting World."))

/datum/system/ticker/proc/reboot_callback(reason, end_string)
	if(end_string)
		end_state = end_string

	log_game(span_boldannounce("Rebooting World. [reason]"))

	world.Reboot()

/**
 * Deletes the current reboot timer and nulls the var
 *
 * Arguments:
 * * user - the user that cancelled the reboot, may be null
 */
/datum/system/ticker/proc/cancel_reboot(mob/user)
	if(!after_pending(src, "reboot_timer"))
		to_chat(user, span_warning("There is no pending reboot!"))
		return FALSE
	to_chat(world, span_boldannounce("An admin has delayed the round end."))
	cancel_after(src, "reboot_timer")
	set_reboot_countdown_left(0)
	return TRUE

/**
 * Helper proc that delays the roundend for us.
 * This proc will trigger a reboot if the delay is 'toggled off'.
 * Use with care.
 */
/datum/system/ticker/proc/toggle_delay()
	delay_end = !delay_end

	set_reboot_countdown_left(0)
	if(after_pending(src, "reboot_timer"))
		cancel_after(src, "reboot_timer")
	else
		Reboot("World reboot after administrative delay.")
