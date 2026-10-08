/*!
 * Copyright (c) 2020 Aleksej Komarov
 * SPDX-License-Identifier: MIT
 */

/**
 * tgui datum (represents a UI).
 */
/datum/tgui
	/// The mob who opened/is using the UI.
	var/mob/user
	/// The object which owns the UI.
	var/tmp/datum/src_object
	/// The title of the UI.
	var/title
	/// The window_id for browse() and onclose().
	var/tmp/datum/tgui_window/window
	/// Key that is used for remembering the window geometry.
	var/window_key
	/// Deprecated: Window size.
	var/window_size
	/// The interface (template) to be used for this UI.
	var/interface
	/// Whether this interface explicitly opts into periodic server refreshes.
	/// Normal interfaces are event-driven through SStgui.update_uis(); continuous
	/// monitors must opt in with set_autoupdate(TRUE).
	var/autoupdate = FALSE
	/// If the UI has been initialized yet.
	var/initialized = FALSE
	/// Time of opening the window.
	EXPIRY_DECLARE(opened_at)
	/// Stops further updates when close() was called.
	var/closing = FALSE
	/// The status/visibility of the UI.
	var/status = STATUS_INTERACTIVE
	/// Timed refreshing state
	var/refreshing = FALSE
	/// Topic state used to determine status/interactability.
	var/tmp/datum/tgui_state/state_static
	/// Rate limit client refreshes to prevent DoS.
	COOLDOWN_DECLARE(refresh_cooldown)
	/// The id of any ByondUi elements that we have opened
	var/list/open_byondui_elements
	/// The map z-level to display.
	var/map_z_level = 1
	/// The Parent UI
	var/tmp/datum/tgui/parent_ui
	/// Children of this UI
	var/list/children = list() // ALLOW(instance_list): d: tgui window tree; many call sites
	/// Any partial packets that we have received from TGUI, waiting to be sent
	var/partial_packets
	/// If the window should be closed with other windows when requested
	var/closeable = TRUE

/**
 * public
 *
 * Create a new UI.
 *
 * required user mob The mob who opened/is using the UI.
 * required src_object datum The object or datum which owns the UI.
 * required interface string The interface used to render the UI.
 * optional title string The title of the UI.
 * optional parent_ui datum/tgui The parent of this UI.
 * optional ui_x int Deprecated: Window width.
 * optional ui_y int Deprecated: Window height.
 * optional window datum/tgui_window: The window to display this TGUI within
 *
 * return datum/tgui The requested UI.
 */
/datum/tgui/New(mob/user, datum/src_object, interface, title, datum/tgui/parent_ui, ui_x, ui_y, datum/tgui_window/window)
	rel_set(src, nameof(user), user)
	rel_set(src, nameof(src_object), src_object)
	src.interface = interface
	if(title)
		src.title = title
	src.state_static = src_object.tgui_state()
	rel_set(src, nameof(parent_ui), parent_ui)
	if(parent_ui)
		rel_add(parent_ui, nameof(parent_ui.children), src)
	// Deprecated
	if(ui_x && ui_y)
		src.window_size = list(ui_x, ui_y)

	if(window)
		rel_set(src, nameof(window), window)
		src.window_key = window.id
	else
		src.window_key = "[REF(src_object)]-main"

/**
 * public
 *
 * Open this UI (and initialize it with data).
 *
 * Args:
 * preinitialized: bool - if TRUE, we will not attempt to force strict mode on the tgui's window datum
 *
 * return bool - TRUE if a new pooled window is opened, FALSE in all other situations including if a new pooled window didn't open because one already exists.
 */
/datum/tgui/proc/open(preinitialized = FALSE)
	#ifdef TGUI_DEV_DIAGNOSTICS
	var/startup_timer = "tgui-open-[REF(src)]"
	var/list/startup_profile = list()
	rustg_time_reset(startup_timer)
	#endif
	if(!user?.client)
		return FALSE
	// A pre-supplied window that is already READY is only refused when something
	// else owns it: a pooled shell always belongs to the pool, and a locked window
	// belongs to whichever UI locked it. An unlocked READY dedicated window
	// (tooltip, media panel, ...) whose previous UI went away simply registers the
	// new UI against its live page instead of stranding the page with no owner.
	if(window() && window().status > TGUI_WINDOW_LOADING && (window().pooled || window().locked))
		return FALSE
	process_status()
	if(status < STATUS_UPDATE)
		return FALSE
	if(!window())
		rel_set(src, nameof(window), SStgui.request_pooled_window(user))
	#ifdef TGUI_DEV_DIAGNOSTICS
	startup_profile["pool_acquired_ms"] = rustg_time_milliseconds(startup_timer)
	#endif
	if(!window())
		return FALSE
	EXPIRY_STAMP(src, opened_at, CLOCK_WORLD)
	var/list/default_geometry = SStgui.get_default_geometry(interface)
	window().acquire_lock(src, default_geometry)
	if(!window().is_ready() && !preinitialized)
		window().initialize(
			strict_mode = TRUE,
			fancy = user.read_preference(/datum/preference/toggle/tgui_fancy),
			assets = list(
				SStgui.get_current_asset_generation().shell_assets(),
				))
	else
		window().send_message("ping")
	#ifdef TGUI_DEV_DIAGNOSTICS
	startup_profile["shell_ready_ms"] = rustg_time_milliseconds(startup_timer)
	var/needs_flush = send_assets(startup_profile, startup_timer)
	#else
	var/needs_flush = send_assets()
	#endif
	// The assets must have arrived before the first payload, or the page asks for chunks
	// that aren't there yet. The client's ack (not a poll) releases the payload; a client
	// that never answers gets it after ASSET_FLUSH_TIMEOUT.
	var/datum/client_session/session = user.client.session
	if(needs_flush && session)
		#ifdef TGUI_DEV_DIAGNOSTICS
		session.flush_assets(src, PROC_REF(send_open_payload), startup_profile, startup_timer)
		#else
		session.flush_assets(src, PROC_REF(send_open_payload))
		#endif
	else
		#ifdef TGUI_DEV_DIAGNOSTICS
		send_open_payload(startup_profile, startup_timer)
		#else
		send_open_payload()
		#endif
	SStgui.on_open(src)
	status_watch()
	// A shell that never answers is a zombie: one timer, cancelled when it does (or when the window closes).
	arm_ping_timeout()

	return TRUE

/// The first payload: config, data and static data together. Sent once assets have arrived.
/datum/tgui/proc/send_open_payload(list/startup_profile, startup_timer)
	if(closing || QDELETED(src) || !window() || !user?.client)
		return
	#ifdef TGUI_DEV_DIAGNOSTICS
	if(startup_profile)
		startup_profile["assets_flushed_ms"] = rustg_time_milliseconds(startup_timer)
		var/list/startup_payload = get_payload(
			with_data = TRUE,
			with_static_data = TRUE,
			startup_profile = startup_profile,
			startup_timer = startup_timer)
		startup_profile["payload_ready_ms"] = rustg_time_milliseconds(startup_timer)
		startup_payload["config"]["startup_profile"] = startup_profile.Copy()
		window().send_message("update", startup_payload)
		startup_profile["update_sent_ms"] = rustg_time_milliseconds(startup_timer)
		startup_profile["interface"] = interface
		startup_profile["prewarmed"] = window().prewarmed ? TRUE : FALSE
		startup_profile["native_shell"] = window().native_shell ? TRUE : FALSE
		startup_profile["generation"] = window().generation
		startup_profile["browser_profiling"] = client_profiling_enabled() ? TRUE : FALSE
		log_tgui(user, "Automatic TGUI server startup telemetry: [json_encode(startup_profile)]", window = window())
		return
	#endif
	window().send_message("update", get_payload(
		with_data = TRUE,
		with_static_data = TRUE))

/// Queues this UI's assets. Returns TRUE when the caller must wait for the client's ack.
/datum/tgui/proc/send_assets(list/startup_profile, startup_timer)
	#ifdef TGUI_DEV_DIAGNOSTICS
	var/assets_started_ms = startup_profile ? rustg_time_milliseconds(startup_timer) : 0
	#endif

	var/flush_queue = window().send_asset(get_asset_datum(
		/datum/asset/simple/namespaced/fontawesome))
	flush_queue |= window().send_asset(get_asset_datum(
		/datum/asset/simple/namespaced/tgfont))
	flush_queue |= window().send_asset(get_asset_datum(
		/datum/asset/simple/namespaced/tgui_extra_fonts))
	flush_queue |= window().send_asset(get_asset_datum(
		/datum/asset/json/icon_ref_map))
	for(var/datum/asset/asset in src_object().ui_assets(user))
		flush_queue |= window().send_asset(asset)
	#ifdef TGUI_DEV_DIAGNOSTICS
	if(startup_profile)
		startup_profile["assets_queued_ms"] = rustg_time_milliseconds(startup_timer)
	#endif
	// Ship this interface's code-split chunk(s) before the window receives its
	// "update" payload, so the React side can lazy-import the interface module the
	// moment it mounts. Each interface chunk is self-contained (rspack splitChunks is
	// off), so the single manifest entry is the complete set of files needed — no
	// dependency closure. No-op when the build emitted no manifest (unsplit bundle).
	var/datum/tgui_asset_generation/asset_generation = window().asset_generation() || SStgui.get_current_asset_generation()
	var/list/interface_chunks = asset_generation.get_interface_chunks(interface)
	// Directly copying development chunks into BYOND's cache is not sufficient:
	// Chromium can request a file before BYOND has registered its browse_rsc name,
	// producing an intermittent ChunkLoadError. The asset transport deduplicates
	// files already sent to this client, so always use the reliable publication path.
	if(interface_chunks)
		flush_queue |= SSassets.transport.send_assets(user.client, asset_generation.get_chunk_assets(interface_chunks))
	#ifdef TGUI_DEV_DIAGNOSTICS
	if(startup_profile)
		startup_profile["asset_delivery_ms"] = rustg_time_milliseconds(startup_timer) - assets_started_ms
		startup_profile["asset_flush_required"] = flush_queue ? TRUE : FALSE
		startup_profile["interface_chunk_count"] = length(interface_chunks)
	#endif
	return flush_queue ? TRUE : FALSE

/datum/tgui/proc/client_profiling_enabled()
	return FALSE

/**
 * public
 *
 * Close the UI.
 *
 * optional can_be_suspended bool
 */
/datum/tgui/proc/close(can_be_suspended = TRUE, logout = FALSE)
	if(closing)
		return
	closing = TRUE
	for(var/datum/tgui/child in children)
		child.close(can_be_suspended, logout)
	// If we don't have window_id, open proc did not have the opportunity
	// to finish, therefore it's safe to skip this whole block.
	if(window())
		// Windows you want to keep are usually blue screens of death
		// and we want to keep them around, to allow user to read
		// the error message properly.
		window().release_lock()
		window().close(can_be_suspended, logout)
		// Either side may already be gone (deleted src_object, deleted mob);
		// SStgui.on_close must still run so the UI leaves all_uis.
		if(!QDELETED(src_object()))
			src_object().tgui_close(user)
		SStgui.on_close(src)
		status_unwatch()
		cancel_after(src, "ping")

		if(user?.client)
			terminate_byondui_elements()

	// Unset machine just to be sure.
	if(!QDELETED(user))
		user.unset_machine()

	state_static = null
	if(parent_ui())
		parent_ui().children -= src
	rel_clear(src, nameof(parent_ui))
	spent(src)

/**
 * public
 *
 * Closes all ByondUI elements, left dangling by a forceful TGUI exit,
 * such as via Alt+F4, closing in non-fancy mode, or terminating the process
 *
 */
/datum/tgui/proc/terminate_byondui_elements()

	for(var/byondui_element in open_byondui_elements)
		winset(user.client, byondui_element, list("parent" = ""))

/**
 * public
 *
 * Enable/disable auto-updating of the UI.
 *
 * required value bool Enable/disable auto-updating.
 */
/datum/tgui/proc/set_autoupdate(autoupdate)
	src.autoupdate = autoupdate
	SStgui.sync_autoupdate(src)

/**
 * public
 *
 * Replace current ui.state with a new one.
 *
 * required state datum/ui_state/state Next state
 */
/datum/tgui/proc/set_state(datum/tgui_state/state)
	src.state_static = state

/**
 * public
 *
 * Makes an asset available to use in tgui.
 *
 * required asset datum/asset
 *
 * return bool - true if an asset was actually sent
 */
/datum/tgui/proc/send_asset(datum/asset/asset)
	if(!window())
		CRASH("send_asset() was called either without calling open() first or when open() did not return TRUE.")
	return window().send_asset(asset)

/**
 * public
 *
 * Send a full update to the client (includes static data).
 *
 * optional custom_data list Custom data to send instead of ui_data.
 * optional force bool Send an update even if UI is not interactive.
 */
/datum/tgui/proc/send_full_update(custom_data, force)
	if(!user?.client || !initialized || closing)
		return
	var/should_update_data = force || status >= STATUS_UPDATE
	window().send_message("update", get_payload(
		custom_data,
		with_data = should_update_data,
		with_static_data = TRUE))

/**
 * public
 *
 * Send a partial update to the client (excludes static data).
 *
 * optional custom_data list Custom data to send instead of ui_data.
 * optional force bool Send an update even if UI is not interactive.
 */
/datum/tgui/proc/send_update(custom_data, force)
	if(!user?.client || !initialized || closing)
		return
	var/should_update_data = force || status >= STATUS_UPDATE
	window().send_message("update", get_payload(
		custom_data,
		with_data = should_update_data))

/**
 * private
 *
 * The per-push config: only what can change between pushes.
 */
/datum/tgui/proc/slim_config()
	return list(
		"title" = title,
		"status" = status,
		"refreshing" = FALSE,
		"mapZLevel" = map_z_level,
	)

/**
 * private
 *
 * The complete config block, sent once on open, ready and full updates.
 */
/datum/tgui/proc/full_config()
	var/datum/tgui_asset_generation/asset_generation = window()?.asset_generation() || SStgui.get_current_asset_generation()
	var/list/default_geometry = asset_generation.get_default_geometry(interface)
	return list(
		"chunk_base_url" = asset_generation.get_chunk_base_url(),
		"title" = title,
		"status" = status,
		"interface" = list(
			"name" = interface,
			"layout" = user.read_preference(/datum/preference/choiced/tgui_layout),
		),
		"refreshing" = FALSE,
		"mapZLevel" = map_z_level,
		"mapInfo" = list(
			"maxx" = world.maxx,
			"maxy" = world.maxy,
		),
		"window" = list(
			"key" = window_key,
			"size" = window_size,
			"fancy" = user.read_preference(/datum/preference/toggle/tgui_fancy),
			"locked" = user.read_preference(/datum/preference/toggle/tgui_lock),
			"scale" = user.read_preference(/datum/preference/toggle/ui_scale),
			"prewarmed" = window()?.prewarmed ? TRUE : FALSE,
			"generation" = window()?.generation || 0,
			"native_shell" = window()?.native_shell ? TRUE : FALSE,
			"default_geometry" = default_geometry,
			"geometry_preapplied" = window()?.geometry_preapplied ? TRUE : FALSE,
			"preapplied_geometry" = window()?.preapplied_geometry,
		),
		"client" = list(
			"ckey" = user.client.ckey,
			"address" = user.client.address,
			"computer_id" = user.client.computer_id,
			// The development cache handshake is the explicit live-profiling switch
			// (see client_profiling_enabled()). A normal server running production
			// assets therefore pays no browser-profiler overhead.
			"profiling" = client_profiling_enabled() ? TRUE : FALSE,
		),
		"user" = list(
			"name" = "[user]",
			"observer" = isobserver(user),
		),
	)

/**
 * private
 *
 * Package the data to send to the UI, as JSON.
 *
 * return list
 */
/datum/tgui/proc/get_payload(custom_data, with_data, with_static_data, list/startup_profile, startup_timer)
	var/list/json_data = list()
	// The full config block (window, client, preferences, geometry) only goes out with
	// static data: open, ready and full updates. A data push carries the slim block --
	// the frontend merges config, so everything not resent keeps its value.
	json_data["config"] = with_static_data ? full_config() : slim_config()
	var/data = custom_data || with_data && src_object().tgui_data(user, src, state())
	#ifdef TGUI_DEV_DIAGNOSTICS
	if(startup_profile)
		startup_profile["dynamic_data_ms"] = rustg_time_milliseconds(startup_timer)
	#endif
	if(data)
		json_data["data"] = data
	var/static_data = with_static_data && src_object().tgui_static_data(user)
	#ifdef TGUI_DEV_DIAGNOSTICS
	if(startup_profile)
		startup_profile["static_data_ms"] = rustg_time_milliseconds(startup_timer)
	#endif
	if(static_data)
		json_data["static_data"] = static_data
	if(src_object().tgui_shared_states)
		json_data["shared"] = src_object().tgui_shared_states
	return json_data

/**
 * public
 *
 * Asks for a coalesced push, delivered in phase R (code/modules/tgui/ui_push.dm). Every request in one
 * tick becomes one push, so 50 update_uis() calls in a tick cost one tgui_data() per UI.
 *
 * optional reinteract bool Re-run tgui_interact on the push (update_uis semantics),
 * rather than only re-sending data.
 */
/datum/tgui/proc/request_push(reinteract = TRUE)
	if(closing || QDELETED(src))
		return
	ui_push_queue(src, reinteract ? UI_PUSH_INTERACT : UI_PUSH_DATA)

/**
 * private
 *
 * Run an update cycle for this UI. Called internally by SStgui
 * every second or so.
 */
/datum/tgui/process(force = FALSE)
	if(closing)
		return
	if(!ui_participants_alive())
		return
	// Update through the declared UI's refresh (its ui_prepare() hook, then the push)
	if(status != STATUS_DISABLED && (autoupdate || force))
		ui_refresh(src_object(), user, src)
		return
	// Update status only
	var/needs_update = process_status()
	if(status <= STATUS_CLOSE)
		close()
		return
	if(needs_update)
		send_status_update()

/**
 * private
 *
 * TRUE while the window's object, window and user are all still there. Closes the window (or, for a persistent
 * UI on a dedicated window, follows the client to its current mob) and returns FALSE otherwise.
 */
/datum/tgui/proc/ui_participants_alive()
	if(QDELETED(src_object()) || QDELETED(window()))
		close(can_be_suspended = FALSE)
		return FALSE
	// A persistent UI on a dedicated window (tooltip, media panel) outlives the
	// mob it was opened against: follow the client to its current mob rather than
	// tearing the page down with the dead mob.
	if(QDELETED(user) && !closeable && !window().pooled)
		var/mob/current_mob = window().client()?.mob
		if(QDELETED(current_mob) || !SStgui.transfer_ui(src, current_mob))
			close(can_be_suspended = FALSE)
			return FALSE
	var/datum/host = src_object().tgui_host(user)
	// If the object or user died (or something else), abort.
	if(QDELETED(host) || QDELETED(user))
		close(can_be_suspended = FALSE)
		return FALSE
	return TRUE

/// Arms the one zombie-window timer (cancelled when the window reports ready, or closes).
/datum/tgui/proc/arm_ping_timeout()
	after(src, TGUI_PING_TIMEOUT, PROC_REF(ping_timeout), key = "ping", clock = CLOCK_WORLD)

/// Sends the window its current status and data.
/datum/tgui/proc/send_status_update()
	window().send_message("update", get_payload())

/// The user, the host or the window stopped being referenced (deleted, or cleared): the status check decides what
/// that means for the window. Deferred to the presentation lane: this runs inside the other end's destruction.
/datum/tgui/proc/participant_gone(datum/other)
	if(closing || QDELETED(src))
		return
	ui_push_queue(src, UI_PUSH_STATUS)

/// The ping timer fired: a window that never reported ready is a zombie.
/datum/tgui/proc/ping_timeout()
	if(closing || initialized || QDELETED(src))
		return
	log_tgui(user, "Error: Zombie window detected, killing it with fire. window_id: [window()?.id] opened_at: [opened_at] world.time: [world.time]", context = "tgui/ping_timeout")
	close(can_be_suspended = FALSE)

/**
 * private
 *
 * Updates the status, and returns TRUE if status has changed.
 */
/datum/tgui/proc/process_status()
	var/prev_status = status
	if(src_object())
		status = src_object().tgui_status(user, state())
	if(parent_ui())
		status = min(status, parent_ui().status)
	return prev_status != status

/datum/tgui/proc/set_map_z_level(nz)
	map_z_level = nz

/**
 * private
 *
 * Callback for handling incoming tgui messages.
 */
/datum/tgui/proc/on_message(type, list/payload, list/href_list)
	// Pass act type messages to tgui_act
	if(type && copytext(type, 1, 5) == "act/")
		var/act_type = copytext(type, 5)
		#ifdef TGUI_DEBUGGING
		log_tgui(user, "Action: [act_type] [href_list["payload"]], Window: [window().id], Source: [src_object()]")
		#endif
		process_status()
		input_submit(new /datum/input_event/ui_act(user, src, act_type, payload, state()))
		return FALSE
	switch(type)
		if("ready")
			// Send a full update when the user manually refreshes the UI
			if(initialized)
				send_full_update()
			initialized = TRUE
			cancel_after(src, "ping")
		if("ping/reply")
			initialized = TRUE
			cancel_after(src, "ping")
		if("suspend")
			close(can_be_suspended = TRUE)
			return TRUE
		if("close")
			close(can_be_suspended = FALSE)
			return TRUE
		if("log")
			// ALLOW(sys_topic_raw_dispatch): tgui protocol message field (fatal log flag), not a datum href action.
			if(href_list["fatal"])
				close(can_be_suspended = FALSE)
		if("setSharedState")
			if(status != STATUS_INTERACTIVE)
				return
			var/datum/shared_state_owner = src_object()
			LAZYINITLIST(shared_state_owner.tgui_shared_states)
			shared_state_owner.tgui_shared_states[href_list["key"]] = href_list["value"]
			SStgui.update_uis(src_object())
		if("fallback")
			#ifdef TGUI_DEBUGGING
			log_tgui(user, "Fallback Triggered: [href_list["payload"]], Window: [window().id], Source: [src_object()]")
			#endif
			src_object().tgui_fallback(payload, user)
		if(TGUI_MANAGED_BYONDUI_TYPE_RENDER)
			var/byond_ui_id = payload[TGUI_MANAGED_BYONDUI_PAYLOAD_ID]
			if(!byond_ui_id || LAZYLEN(open_byondui_elements) > TGUI_MANAGED_BYONDUI_LIMIT)
				return

			LAZYOR(open_byondui_elements, byond_ui_id)
		if(TGUI_MANAGED_BYONDUI_TYPE_UNMOUNT)
			var/byond_ui_id = payload[TGUI_MANAGED_BYONDUI_PAYLOAD_ID]
			if(!byond_ui_id)
				return

			LAZYREMOVE(open_byondui_elements, byond_ui_id)

/// Wrapper for behavior to potentially wait until the next tick if the server is overloaded
/datum/tgui/proc/on_act_message(act_type, payload, state)
	if(QDELETED(src) || QDELETED(src_object()))
		return
	if(src_object().tgui_act(act_type, payload, src, state))
		SStgui.update_uis(src_object(), src)
		if(isatom(src_object()) && !QDELETED(src_object()))
			var/atom/A = src_object()
			A.interaction_ran(user, null)

/// The src_object this refers to (a relation view: null once that is deleted).
/datum/tgui/proc/src_object() as /datum
	return src_object

/// The window this refers to (a relation view: null once that is deleted).
/datum/tgui/proc/window() as /datum/tgui_window
	return window

/// A shared (registered) definition/flyweight: never cleared.
/datum/tgui/proc/state() as /datum/tgui_state
	return state_static

/// The parent_ui this refers to (a relation view: null once that is deleted).
/datum/tgui/proc/parent_ui() as /datum/tgui
	return parent_ui

/datum/tgui/relations()
	. = ..()
	. += rel_one(nameof(user), back = nameof(/mob::tgui_open_uis), on_unlink = PROC_REF(participant_gone))
	. += rel_one(nameof(src_object), on_unlink = PROC_REF(participant_gone))
	. += rel_one(nameof(window), on_unlink = PROC_REF(participant_gone))
/mob/relations()
	. = ..()
	. += rel_many(nameof(tgui_open_uis), back = nameof(/datum/tgui::user))
