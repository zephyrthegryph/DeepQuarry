// The stat panel system (was SSstatpanels): refreshes every client's stat tabs every 4 ticks. The API is in
// statpanel_api.dm.
/// One client's turn in refresh_tabs() at least this long is logged (STATPANELS), with the tab it was on.
#define STATPANEL_SLOW_MS 5

SYSTEM_DEF(statpanels)
	name = "Stat Panels"
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	/// TRUE while a pass that ran out of budget waits to resume.
	VAR_PRIVATE/resuming = FALSE
	var/list/currentrun = list()
	var/list/global_data
	var/list/mc_metrics
	/// ckey -> (section -> the section's list as last sent to that client): what each admin's MC Health panel already holds.
	var/list/mc_sent_by_client = list()
	/// The MC Health panel's slow sections (mc_health_slow()), and when each group of them was built (group -> world time).
	var/list/mc_slow
	var/list/mc_slow_built_at
	/// The longest build of one slow group so far, ms (the MC_HEALTH trace line).
	var/mc_group_max_ms = 0
	/// The longest single client's turn in refresh_tabs so far, ms, and the turns past STATPANEL_SLOW_MS (the STATPANELS trace line).
	var/turn_max_ms = 0
	var/slow_turns = 0
	var/mc_metrics_generated_at = 0
	mc_metrics_generated_at = -INFINITY

	///how many subsystem fires between most tab updates
	var/default_wait = 10
	///how many subsystem fires between updates of misc tabs
	var/misc_wait = 3
	///how many subsystem fires between updates of the status tab
	var/status_wait = 2
	///how many subsystem fires (0.4 s each) between updates of the MC tab: about once a second
	var/mc_wait = 3
	///how many full runs this subsystem has completed. used for variable rate refreshes.
	var/num_fires = 0

/datum/system/statpanels/reactions()
	. = ..()
	. += every(4, PROC_REF(refresh_tabs), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/statpanels/proc/refresh_tabs(dt)
	var/resumed = resuming
	resuming = FALSE
	if (!resumed)
		num_fires++
	// The Status lines are only read by a status send (every status_wait fires; an immediate send reads the last ones).
	if (!resumed && (num_fires % status_wait == 0 || !global_data))
		global_data = list(
			//"Map: [SSmapping.config?.map_name || "Loading..."]",
			"Map: [using_map.name]",
			//cached ? "Next Map: [cached.map_name]" : null,
			//"Next Map: -- Not Available --",
			"Round ID: [GLOB.round_id ? GLOB.round_id : "NULL"]",
			"Server Time: [time2text(world.timeofday, "YYYY-MM-DD hh:mm:ss")]",
			"Round Time: [roundduration2text()]",
			"Station Date: [stationdate2text()], [capitalize(GLOB.world_time_season)]",
			"Station Time: [stationtime2text()]",
			"Time Dilation: [round(time_track_time_dilation_current(),1)]% AVG:([round(time_track_time_dilation_avg_fast(),1)]%, [round(time_track_time_dilation_avg(),1)]%, [round(time_track_time_dilation_avg_slow(),1)]%)"
		)

		if(emergency_shuttle_evac())
			var/ETA = SSemergency_shuttle.get_status_panel_eta()
			if(ETA)
				global_data += "[ETA]"

		if(after_pending(SSticker, "reboot_timer"))
			var/reboot_time = after_left(SSticker, "reboot_timer")
			if(reboot_time)
				global_data += "Reboot: [DisplayTimeText(reboot_time, 1)]"
		// admin must have delayed round end
		else if(ticker_ready_for_reboot())
			global_data += "Reboot: DELAYED"

	if (!resumed)
		src.currentrun = GLOB.clients.Copy()

	var/list/currentrun = src.currentrun
	while(length(currentrun))
		var/client/target = currentrun[length(currentrun)]
		currentrun.len--

		if(!target?.stat_panel?.is_ready()) // Null target client, client has null stat panel, or stat panel isn't ready
			continue
		var/turn_started = TICK_USAGE_REAL

		if(target.stat_tab == "Status" && num_fires % status_wait == 0)
			set_status_tab(target)

		if(!admin_can(target, 0))
			// Once, on losing rights: not every fire to every player.
			if(("MC" in target.panel_tabs) || ("Tickets" in target.panel_tabs) || ("SDQL2" in target.panel_tabs))
				target.stat_panel.send_message("remove_admin_tabs")
		else
			if(check_rights_for(target, R_MENTOR) && !("Tickets" in target.panel_tabs))
				target.stat_panel.send_message("add_tickets_tabs", admin_href_token(target))
			if(check_rights_for(target, R_HOLDER) && (!("MC" in target.panel_tabs) || !("Tickets" in target.panel_tabs)))
				target.stat_panel.send_message("add_admin_tabs", admin_href_token(target))

			if(target.stat_tab == "MC" && ((num_fires % mc_wait == 0)))
				set_MC_tab(target)

			if(target.stat_tab == "Tickets" && num_fires % default_wait == 0)
				set_tickets_tab(target)

			if(!REGISTRY_COUNT(REGISTRY_SDQL2_QUERIES) && ("SDQL2" in target.panel_tabs))
				target.stat_panel.send_message("remove_sdql2")

			else if(REGISTRY_COUNT(REGISTRY_SDQL2_QUERIES) && (target.stat_tab == "SDQL2" || !("SDQL2" in target.panel_tabs)) && num_fires % default_wait == 0)
				set_SDQL2_tab(target)

		if(target.mob)
			var/mob/target_mob = target.mob

			// Handle the action panels of the stat panel

			var/update_actions = FALSE
			// We're on a spell tab, update the tab so we can see cooldowns progressing and such
			if(target.stat_tab in target.spell_tabs)
				update_actions = TRUE
			// We're not on a spell tab per se, but we have cooldown actions, and we've yet to
			// set up our spell tabs at all
			//if(!length(target.spell_tabs) && locate(/datum/action/cooldown) in target_mob.actions)
				//update_actions = TRUE

			if(update_actions && num_fires % default_wait == 0)
				set_action_tabs(target, target_mob)
			//Update every fire if tab is open, otherwise update every 7 fires
			if((num_fires % misc_wait == 0))
				update_misc_tabs(target,target_mob)

		var/turn_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - turn_started)
		turn_max_ms = max(turn_max_ms, turn_ms)
		if(turn_ms >= STATPANEL_SLOW_MS)
			slow_turns++
			log_world("STATPANELS: one client's turn took [round(turn_ms, 0.1)] ms (tab [target.stat_tab], fire [num_fires]); [slow_turns] such turn(s), longest [round(turn_max_ms, 0.1)] ms")
		if(KERNEL_OVER_BUDGET)
			resuming = TRUE
			return STEP_YIELD
	return STEP_DONE

/datum/system/statpanels/proc/update_misc_tabs(client/target,mob/target_mob)
	target_mob.update_misc_tabs()
	var/list/mob_tabs = STATE_GET(target_mob, mob_misc, misc_tabs)
	for(var/tab in mob_tabs)
		if(length(mob_tabs[tab]) == 0 && (tab in target.misc_tabs))
			target.misc_tabs -= tab
			target.stat_panel.send_message("remove_misc",tab)
			target.stat_panel.forget_sent("update_misc:[tab]")

		if(length(mob_tabs[tab]) > 0)
			if(!(tab in target.misc_tabs))
				target.misc_tabs += tab
				target.stat_panel.send_message("create_misc",tab)
			// Rebuilt every misc_wait fires; the page gets it only when a line changed.
			target.stat_panel.send_message("update_misc",list(
				TN = tab, \
				TC = mob_tabs[tab], \
			), same_key = "update_misc:[tab]")

	for(var/tab in target.misc_tabs)
		if(!(tab in mob_tabs))
			target.misc_tabs -= tab
			target.stat_panel.send_message("remove_misc",tab)
			target.stat_panel.forget_sent("update_misc:[tab]")

/datum/system/statpanels/proc/set_status_tab(client/target)
	if(!global_data)//statbrowser hasnt fired yet and we were called from immediate_send_stat_data()
		return

	target.stat_panel.send_message("update_stat", list(
		global_data = global_data,
		ping_str = "Ping: [round(target.lastping, 1)]ms (Average: [round(target.avgping, 1)]ms)",
		other_str = target.mob?.get_status_tab_items(),
	), same_key = "update_stat")

/// The MC Health panel's data (mc_health.dm), sent only to a client on the panel (stat_tab "MC") and rebuilt at most once a second.
/datum/system/statpanels/proc/set_MC_tab(client/target)
	var/turf/eye_turf = get_turf(target.eye)
	if(!mc_metrics || ELAPSED(src, mc_metrics_generated_at, CLOCK_WORLD) >= 1 SECONDS)
		mc_metrics = mc_health_data()
		STAMP(src, mc_metrics_generated_at, CLOCK_WORLD)
	// Only the sections this client has not got: a slow section (mc_health_slow()) is the same list object until it is built again, so an
	// unchanged one is skipped without encoding it. A client that opens the panel or reloads its page gets everything (mc_health_forget()).
	var/key = target.ckey
	var/list/sent = mc_sent_by_client[key]
	if(!sent)
		sent = list()
		mc_sent_by_client[key] = sent
	var/list/changed = list()
	for(var/section in mc_metrics)
		var/value = mc_metrics[section]
		if(sent[section] != value)
			changed[section] = value
			sent[section] = value
	if(length(changed) == length(mc_metrics))
		log_tgui(target, "Server health: whole send of [length(changed)] section(s), window [target.stat_panel.id], ready=[target.stat_panel.is_ready() ? 1 : 0].", context = "stat_panel")
	target.stat_panel.send_message("update_mc", list(
		"mc_metrics" = changed,
		"partial" = length(changed) != length(mc_metrics),
		"coord_entry" = COORD(eye_turf),
	))

/// The client's panel holds none of the MC Health sections any more (it was opened again or its page reloaded): the next send is whole.
/datum/system/statpanels/proc/mc_health_forget(client/target)
	if(target)
		mc_sent_by_client -= target.ckey

/datum/system/statpanels/proc/set_tickets_tab(client/target)
	var/list/tickets = list()
	if(check_rights_for(target, R_ADMIN|R_SERVER|R_MOD|R_MENTOR)) //Prevents non-staff from opening the list of ahelp tickets
		tickets = GLOB.tickets.stat_entry(target)
	target.stat_panel.send_message("update_tickets", tickets, same_key = "update_tickets")

/datum/system/statpanels/proc/set_SDQL2_tab(client/target)
	var/list/sdql2A = list()
	sdql2A[++sdql2A.len] = list("", "Access Global SDQL2 List", REF(sdql2_vv_statobj()))
	var/list/sdql2B = list()
	for(var/datum/SDQL2_query/query as anything in REGISTRY_MEMBERS(REGISTRY_SDQL2_QUERIES))
		sdql2B = query.generate_stat()

	sdql2A += sdql2B
	target.stat_panel.send_message("update_sdql2", sdql2A)

/// Set up the various action tabs.
/datum/system/statpanels/proc/set_action_tabs(client/target, mob/target_mob)
	return

/// Stat panel window declaration
/client/var/datum/tgui_window/stat_panel
