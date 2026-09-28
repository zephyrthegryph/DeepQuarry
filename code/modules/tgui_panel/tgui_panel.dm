/*!
 * Copyright (c) 2020 Aleksej Komarov
 * SPDX-License-Identifier: MIT
 */

/**
 * tgui_panel datum
 * Hosts tgchat and other nice features.
 */
/datum/tgui_panel
	var/tmp/client_handle
	var/datum/tgui_window/window
	var/broken = FALSE
	var/initialized_at
	var/oldchat = FALSE
	/// Each client notifies on protected playback, so this prevents spamming admins.
	var/static/admins_warned = 0 // COOLDOWN, shared by every panel

/datum/tgui_panel/New(client/client, id)
	src.client_handle = om_handle(client)
	window = new(client, id)
	window.subscribe(src, PROC_REF(on_message))

/datum/tgui_panel/Del()
	window?.unsubscribe(src)
	window?.close()
	return ..()

/**
 * public
 *
 * TRUE if panel is initialized and ready to receive messages.
 */
/datum/tgui_panel/proc/is_ready()
	return !broken && window.is_ready()

/**
 * public
 *
 * Initializes tgui panel.
 */
/datum/tgui_panel/proc/initialize(force = FALSE)
	// Deferred a tick, until after the client constructor: a timer, the constructor never waits.
	om_after(src, 1 TICKS, PROC_REF(initialize_window))

/datum/tgui_panel/proc/initialize_window()
	initialized_at = world.time
	// Perform a clean initialization
	window.initialize(
		strict_mode = TRUE,
		assets = list(
			get_asset_datum(/datum/asset/simple/tgui_panel),
		))
	window.send_asset(get_asset_datum(/datum/asset/simple/namespaced/fontawesome))
	window.send_asset(get_asset_datum(/datum/asset/simple/namespaced/tgfont))
	window.send_asset(get_asset_datum(/datum/asset/spritesheet_batched/chat))
	// Other setup
	request_telemetry()
	om_after(src, 5 SECONDS, PROC_REF(on_initialize_timed_out))
	window.send_message("testTelemetryCommand")

/**
 * private
 *
 * Called when initialization has timed out.
 */
/datum/tgui_panel/proc/on_initialize_timed_out()
	// Currently does nothing but sending a message to old chat.
	// SEND_TEXT(client, span_userdanger("Failed to load fancy chat, click <a href='byond://?src=[REF(src)];reload_tguipanel=1'>HERE</a> to attempt to reload it."))

/**
 * private
 *
 * Callback for handling incoming tgui messages.
 */
/datum/tgui_panel/proc/on_message(type, payload)
	if(type == "ready")
		broken = FALSE
		var/list/stored_rounds = CONFIG_GET(flag/chatlog_database_backend) ? vchatlog_get_recent_roundids(client().ckey) : null
		window.send_message("connected", list(
			"round_id" = GLOB.round_id, // Sends the round ID to the chat, requires round IDs
			"chatlog_db_backend" = CONFIG_GET(flag/chatlog_database_backend),
			"chatlog_api_endpoint" = CONFIG_GET(string/chatlog_database_api_endpoint),
			"chatlog_stored_rounds" = islist(stored_rounds) ? list("0") + stored_rounds : list("0"),
		))
		window.send_message("update", list(
			"config" = list(
				"client" = list(
					"ckey" = client().ckey,
					"chatlog_token" = client().chatlog_token,
					"address" = client().address,
					"computer_id" = client().computer_id,
				),
				"server" = list(
					"round_id" = GLOB.round_id,
				),
				"window" = list(
					"fancy" = FALSE,
					"locked" = FALSE,
				),
			),
		))
		return TRUE
	if(type == "audio/setAdminMusicVolume")
		client().admin_music_volume = payload["volume"]
		return TRUE

	if(type == "audio/protected")
		if(COOLDOWN_FINISHED(src, admins_warned))
			message_admins(span_notice("Audio returned a protected playback error, likely due to being copyrighted."))
			COOLDOWN_START(src, admins_warned, 10 SECONDS)
		return TRUE

	if(type == "telemetry")
		analyze_telemetry(payload)
		return TRUE

/**
 * public
 *
 * Sends a round restart notification.
 */
/datum/tgui_panel/proc/send_roundrestart()
	window.send_message("roundrestart")

REF_OWNED(/datum/tgui_panel, "window")

/// LC-refs: the client this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/tgui_panel/proc/client() as /client
	return om_resolve(client_handle)
