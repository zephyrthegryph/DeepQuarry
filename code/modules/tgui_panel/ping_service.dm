/*!
 * Copyright (c) 2022 Aleksej Komarov
 * SPDX-License-Identifier: MIT
 */

// The soft ping world service (was SSping): every 4 s it pings each ready tgui chat panel.
GLOBAL_DATUM_INIT(ping_service, /datum/world_service/ping, new)

/datum/world_service/ping
	name = "Ping"
	lane = /datum/om/behaviour/world/ping
	var/list/currentrun = list()

/datum/world_service/ping/stat_line()
	return "P:[length(GLOB.clients)]"

/datum/world_service/ping/service_step(resumed)
	// Prepare the new batch of clients
	if (!resumed)
		src.currentrun = GLOB.clients.Copy()

	// De-reference the list for sanic speeds
	var/list/currentrun = src.currentrun

	while (length(currentrun))
		var/client/client = currentrun[length(currentrun)]
		currentrun.len--

		if(!client?.prefs?.read_preference(/datum/preference/toggle/vchat_enable))
			winset(client, "output", "on-show=&is-disabled=0&is-visible=1")
			winset(client, "browseroutput", "is-disabled=1;is-visible=0")
			client.tgui_panel.oldchat = TRUE

		if (client?.tgui_panel?.is_ready())
			// Send a soft ping
			client.tgui_panel.window.send_message("ping/soft", list(
				// Slightly less than the subsystem timer (somewhat arbitrary)
				// to prevent incoming pings from resetting the afk state
				"afk" = client.is_afk(3.5 SECONDS),
			))

		if(TICK_CHECK)
			return FALSE
	return TRUE

/// ping (was SSping).
/datum/om/behaviour/world/ping
	name = "world: ping"
	every = 4 SECONDS
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

/datum/om/behaviour/world/ping/service()
	return GLOB.ping_service
