// The stat panel system (was SSstatpanels): refreshes every client's stat tabs every 4 ticks. The API is in
// statpanel_api.dm.
SYSTEM_DEF(statpanels)
	name = "Stat Panels"
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	/// TRUE while a pass that ran out of budget waits to resume.
	VAR_PRIVATE/resuming = FALSE
	var/list/currentrun = list()
	var/list/global_data
	var/list/mc_data
	var/list/mc_metrics
	EXPIRY_DECLARE(mc_metrics_generated_at)
	mc_metrics_generated_at = -INFINITY

	///how many subsystem fires between most tab updates
	var/default_wait = 10
	///how many subsystem fires between updates of misc tabs
	var/misc_wait = 3
	///how many subsystem fires between updates of the status tab
	var/status_wait = 2
	///how many subsystem fires between updates of the MC tab
	var/mc_wait = 5
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
			"Time Dilation: [round(SStime_track.time_dilation_current,1)]% AVG:([round(SStime_track.time_dilation_avg_fast,1)]%, [round(SStime_track.time_dilation_avg,1)]%, [round(SStime_track.time_dilation_avg_slow,1)]%)"
		)

		if(SSemergency_shuttle.evac)
			var/ETA = SSemergency_shuttle.get_status_panel_eta()
			if(ETA)
				global_data += "[ETA]"

		if(after_pending(SSticker, "reboot_timer"))
			var/reboot_time = after_left(SSticker, "reboot_timer")
			if(reboot_time)
				global_data += "Reboot: [DisplayTimeText(reboot_time, 1)]"
		// admin must have delayed round end
		else if(SSticker.ready_for_reboot)
			global_data += "Reboot: DELAYED"

		src.currentrun = GLOB.clients.Copy()
		mc_data = null

	var/list/currentrun = src.currentrun
	while(length(currentrun))
		var/client/target = currentrun[length(currentrun)]
		currentrun.len--

		if(!target?.stat_panel?.is_ready()) // Null target client, client has null stat panel, or stat panel isn't ready
			continue

		if(target.stat_tab == "Status" && num_fires % status_wait == 0)
			set_status_tab(target)

		if(!target.holder)
			target.stat_panel.send_message("remove_admin_tabs")
		else
			target.stat_panel.send_message("update_split_admin_tabs", FALSE)

			if(check_rights_for(target, R_MENTOR))
				target.stat_panel.send_message("add_tickets_tabs", target.holder.href_token)
			if(check_rights_for(target, R_HOLDER) && (!("MC" in target.panel_tabs) || !("Tickets" in target.panel_tabs)))
				target.stat_panel.send_message("add_admin_tabs", target.holder.href_token)

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

		if(KERNEL_OVER_BUDGET)
			resuming = TRUE
			return STEP_YIELD
	return STEP_DONE

/datum/system/statpanels/proc/update_misc_tabs(client/target,mob/target_mob)
	target_mob.update_misc_tabs()
	for(var/tab in target_mob.misc_tabs)
		if(length(target_mob.misc_tabs[tab]) == 0 && (tab in target.misc_tabs))
			target.misc_tabs -= tab
			target.stat_panel.send_message("remove_misc",tab)

		if(length(target_mob.misc_tabs[tab]) > 0)
			if(!(tab in target.misc_tabs))
				target.misc_tabs += tab
				target.stat_panel.send_message("create_misc",tab)
			target.stat_panel.send_message("update_misc",list(
				TN = tab, \
				TC = target_mob.misc_tabs[tab], \
			))

	for(var/tab in target.misc_tabs)
		if(!(tab in target_mob.misc_tabs))
			target.misc_tabs -= tab
			target.stat_panel.send_message("remove_misc",tab)

/datum/system/statpanels/proc/set_status_tab(client/target)
	if(!global_data)//statbrowser hasnt fired yet and we were called from immediate_send_stat_data()
		return

	target.stat_panel.send_message("update_stat", list(
		global_data = global_data,
		ping_str = "Ping: [round(target.lastping, 1)]ms (Average: [round(target.avgping, 1)]ms)",
		other_str = target.mob?.get_status_tab_items(),
	))

/datum/system/statpanels/proc/set_MC_tab(client/target)
	var/turf/eye_turf = get_turf(target.eye)
	var/coord_entry = COORD(eye_turf)
	if(!mc_data)
		generate_mc_data()
	if(!mc_metrics || !BEFORE(src, mc_metrics_generated_at + 5 SECONDS, CLOCK_WORLD))
		mc_metrics = generate_mc_metrics()
		EXPIRY_STAMP(src, mc_metrics_generated_at, CLOCK_WORLD)
	target.stat_panel.send_message("update_mc", list(
		"mc_data" = mc_data,
		"mc_metrics" = mc_metrics,
		"coord_entry" = coord_entry,
	))

/datum/system/statpanels/proc/generate_mc_metrics()
	var/list/history = Kernel.perf_tick_usage
	var/list/rust_allocator = vg_verdigris_allocator_diagnostics()
	var/history_start = max(1, history.len - 119)
	var/list/graph = history.len ? history.Copy(history_start) : list()
	var/list/subsystems = list()
	// Systems with periodic work (air, lighting, ticker, tgui, garbage ...).
	for(var/datum/system/S as anything in kernel_pure_systems())
		if(!S.times_fired && !S.fire_cost)
			continue
		subsystems += list(list(
			"name" = S.name,
			"state" = "  ",
			"usage" = 0,
			"overrun" = S.tick_overrun,
			"cost" = S.fire_cost,
			"fires" = S.times_fired,
			"ref" = REF(S),
		))
	return list(
		"tick_budget_ms" = world.tick_lag * 100,
		"target_tps" = world.fps,
		"current_usage" = history.len ? history[history.len] : 0,
		"maptick" = MAPTICK_LAST_INTERNAL_TICK_USAGE,
		"tidi" = SStime_track.time_dilation_current,
		"tidi_fast" = SStime_track.time_dilation_avg_fast,
		"tidi_medium" = SStime_track.time_dilation_avg,
		"tidi_slow" = SStime_track.time_dilation_avg_slow,
		"window_5s" = Kernel.performance_window(5),
		"window_30s" = Kernel.performance_window(30),
		"window_5m" = Kernel.performance_window(300),
		"graph" = graph,
		"outliers" = Kernel.perf_outliers.Copy(),
		"subsystems" = subsystems,
		"kernel" = km_panel_data(),
		"runtime" = list(
			"cpu" = world.cpu,
			"instances" = length(world.contents),
			"clients" = length(GLOB.clients),
			"tick_drift" = Kernel.tickdrift,
			"sleep_delta" = Kernel.sleep_delta,
			"queue_priority" = 0,
			"queue_priority_background" = 0,
			"kernel_ticks" = kernel().ticks,
			"kernel_last_tick_ms" = kernel().last_tick_ms,
			"rust_current_bytes" = rust_allocator?.len >= 1 ? rust_allocator[1] : 0,
			"rust_peak_bytes" = rust_allocator?.len >= 2 ? rust_allocator[2] : 0,
		),
	)

/datum/system/statpanels/proc/set_tickets_tab(client/target)
	var/list/tickets = list()
	if(check_rights_for(target, R_ADMIN|R_SERVER|R_MOD|R_MENTOR)) //Prevents non-staff from opening the list of ahelp tickets
		tickets = GLOB.tickets.stat_entry(target)
	target.stat_panel.send_message("update_tickets", tickets)

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



/datum/system/statpanels/proc/generate_mc_data()
	mc_data = list(
		list("CPU:", world.cpu),
		list("Instances:", "[num2text(length(world.contents), 10)]"),
		list("World Time:", "[world.time]"),
		list("Globals:", GLOB.stat_entry(), text_ref(GLOB)),
		list("[config]:", config.stat_entry(), text_ref(config)),
		list("Byond:", "(FPS:[world.fps]) (TickCount:[world.time/world.tick_lag]) (TickDrift:[round(Kernel.tickdrift,1)]([round((Kernel.tickdrift/(world.time/world.tick_lag))*100,0.1)]%)) (Internal Tick Usage: [round(MAPTICK_LAST_INTERNAL_TICK_USAGE,0.1)]%)"),
		list("Kernel Controller:", Kernel.stat_entry(), text_ref(Kernel)),
		list("Watchdog:", Kernel.watchdog.stat_entry(), text_ref(Kernel.watchdog)),
		list("","")
	)
#if defined(MC_TAB_TRACY_INFO) || defined(SPACEMAN_DMM)
	var/static/tracy_dll
	var/static/tracy_present
	if(isnull(tracy_dll))
		tracy_dll = TRACY_DLL_PATH
		tracy_present = fexists(tracy_dll)
	if(tracy_present)
		if(Tracy.enabled)
			mc_data.Insert(2, list(list("byond-tracy:", "Active (reason: [Tracy.init_reason || "N/A"])")))
		else if(Tracy.error)
			mc_data.Insert(2, list(list("byond-tracy:", "Errored ([Tracy.error])")))
		else if(fexists(TRACY_ENABLE_PATH))
			mc_data.Insert(2, list(list("byond-tracy:", "Queued for next round")))
		else
			mc_data.Insert(2, list(list("byond-tracy:", "Inactive")))
	else
		mc_data.Insert(2, list(list("byond-tracy:", "[tracy_dll] not present")))
#endif
	for(var/datum/system/system as anything in kernel_pure_systems())
		mc_data[++mc_data.len] = list("(system) [system.name]", system.stat_entry(""), "\ref[system]")
	mc_data[++mc_data.len] = list("Camera Net", "Cameras: [length(REGISTRY_MEMBERS(REGISTRY_CAMERAS))] | Chunks: [length(GLOB.cameranet.chunks)]", "\ref[GLOB.cameranet]")

/// Stat panel window declaration
/client/var/datum/tgui_window/stat_panel
