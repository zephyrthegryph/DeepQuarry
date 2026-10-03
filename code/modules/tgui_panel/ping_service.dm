/*!
 * Copyright (c) 2022 Aleksej Komarov
 * SPDX-License-Identifier: MIT
 */

// The soft ping system (was SSping): every 4 s it pings each ready tgui chat panel.
SYSTEM_DEF(ping)
	name = "Ping"
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	var/list/currentrun = list()
	/// TRUE while a ping pass that ran out of budget waits to resume.
	VAR_PRIVATE/ping_resuming = FALSE

/datum/system/ping/stat_entry(msg)
	return "[..()]P:[length(GLOB.clients)]"

/datum/system/ping/reactions()
	. = ..()
	. += every(4 SECONDS, PROC_REF(ping_clients), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/ping/proc/ping_clients(dt)
	// Prepare the new batch of clients
	if (!ping_resuming)
		src.currentrun = GLOB.clients.Copy()
	ping_resuming = FALSE

	// De-reference the list for sanic speeds
	var/list/currentrun = src.currentrun

	while (length(currentrun))
		var/client/client = currentrun[length(currentrun)]
		currentrun.len--

		if(!client?.prefs?.read_preference(/datum/preference/toggle/vchat_enable))
			winset(client, "output", "on-show=&is-disabled=0&is-visible=1")
			winset(client, SKIN_CHAT_BROWSER, "is-disabled=1;is-visible=0")
			client.tgui_panel.oldchat = TRUE

		if (client?.tgui_panel?.is_ready())
			// Send a soft ping
			client.tgui_panel.window.send_message("ping/soft", list(
				// Slightly less than the subsystem timer (somewhat arbitrary)
				// to prevent incoming pings from resetting the afk state
				"afk" = client.is_afk(3.5 SECONDS),
			))

		if(KERNEL_OVER_BUDGET)
			ping_resuming = TRUE
			return STEP_YIELD
	return STEP_DONE
