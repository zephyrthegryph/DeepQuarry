/*!
 * Copyright (c) 2020 Aleksej Komarov
 * SPDX-License-Identifier: MIT
 */

/**
 * tgui subsystem
 *
 * Contains all tgui state and subsystem code.
 *
 */

SUBSYSTEM_DEF(tgui)
	name = "tgui"
	wait = 9
	flags = SS_NO_INIT
	priority = FIRE_PRIORITY_TGUI
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

	dependencies = list(
		/datum/controller/subsystem/assets
	)

	/// A list of UIs scheduled to process
	var/list/current_run = list()
	/// A list of all open UIs
	var/list/all_uis = list()
	/// The HTML base used for all UIs.
	var/basehtml
	/// interface name -> list of code-split chunk files (`*.chunk.js`/`.css`) that
	/// must be delivered to render it. Read from tgui-chunk-manifest.json at PreInit;
	/// consumed by /datum/tgui/proc/send_assets(). Null/empty means the build didn't
	/// emit a manifest (e.g. an unsplit bundle) — interfaces then rely on whatever is
	/// already in the main bundle.
	var/list/chunk_manifest
	/// Deduplicated sequential list of every file in chunk_manifest. Sent once to
	/// idle browser shells so Chromium can populate its HTTP cache without importing
	/// or evaluating every interface module.
	var/list/chunk_files
	/// Shared interface default geometry emitted from the same TS registry used by Window.
	var/list/window_geometry_manifest
	/// Number of idle reusable browser shells kept warm per client. The reserve
	/// is replenished as shells are acquired instead of opening the whole pool at
	/// login, avoiding a Chromium startup burst while keeping normal opens warm.
	var/prewarm_window_reserve = 2

/datum/controller/subsystem/tgui/PreInit()
	basehtml = file2text('tgui/public/tgui.html')

	// Inject inline helper functions
	var/helpers = file2text('tgui/public/helpers.min.js')
	helpers = "<script type='text/javascript'>\n[helpers]\n</script>"
	basehtml = replacetextEx(basehtml, "<!-- tgui:helpers -->", helpers)

	// Inject inline ntos-error styles
	var/ntos_error = file2text('tgui/public/ntos-error.min.css')
	ntos_error = "<style type='text/css'>\n[ntos_error]\n</style>"
	basehtml = replacetextEx(basehtml, "<!-- tgui:ntos-error -->", ntos_error)

	basehtml = replacetextEx(basehtml, "<!-- tgui:nt-copyright -->", "Nanotrasen (c) 2284-[text2num(UTC_YEAR) + STATION_YEAR_OFFSET]") // This can't use the GLOB as it runs before those are populated

	// Load the code-split chunk manifest (interface name -> chunk files) emitted by
	// the rspack build. Just a file read here, same as basehtml above — safe at PreInit.
	// The chunk files themselves are registered into the asset cache later, by
	// SSassets/Initialize() which loads every /datum/asset subtype (including
	// /datum/asset/simple/tgui_chunks). We must NOT register them here: PreInit runs
	// before SSassets is ready, and hashing the files that early runtimes ("bad index").
	load_chunk_manifest()
	load_window_geometry_manifest()

/datum/controller/subsystem/tgui/proc/load_chunk_manifest(manifest_path = "tgui/public/tgui-chunk-manifest.json")
	chunk_manifest = null
	chunk_files = null
	if(fexists(manifest_path))
		var/raw = file2text(manifest_path)
		if(raw)
			chunk_manifest = json_decode(raw)
	if(!islist(chunk_manifest))
		return
	var/list/seen_files = list()
	chunk_files = list()
	for(var/interface_name in chunk_manifest)
		var/list/interface_files = chunk_manifest[interface_name]
		for(var/filename in interface_files)
			if(!seen_files[filename])
				seen_files[filename] = TRUE
				chunk_files += filename

/datum/controller/subsystem/tgui/proc/load_window_geometry_manifest(manifest_path = "tgui/public/tgui-window-manifest.json")
	if(fexists(manifest_path))
		var/raw = file2text(manifest_path)
		if(raw)
			window_geometry_manifest = json_decode(raw)

/datum/controller/subsystem/tgui/proc/get_default_geometry(interface_name)
	var/list/geometry = LAZYACCESS(window_geometry_manifest, interface_name)
	if(!islist(geometry) || !isnum(geometry["width"]) || !isnum(geometry["height"]))
		return null
	return geometry

/// Atomically advances the development manifest and its registered chunk files.
/datum/controller/subsystem/tgui/proc/reload_development_chunks()
	var/development_directory = "tgui/public/.tmp"
	var/development_manifest = "[development_directory]/tgui-chunk-manifest.json"
	if(!fexists(development_manifest))
		return
	load_chunk_manifest(development_manifest)
	load_window_geometry_manifest("[development_directory]/tgui-window-manifest.json")
	var/list/chunk_filenames = list()
	for(var/interface_name in chunk_manifest)
		for(var/filename in chunk_manifest[interface_name])
			chunk_filenames[filename] = TRUE
	var/datum/asset/simple/namespaced/tgui_chunks/chunks = get_asset_datum(/datum/asset/simple/namespaced/tgui_chunks)
	chunks.reload_from_directory(development_directory, chunk_filenames)

/datum/controller/subsystem/tgui/OnConfigLoad()
	var/storage_iframe = CONFIG_GET(string/storage_cdn_iframe)

	if(storage_iframe && storage_iframe != /datum/config_entry/string/storage_cdn_iframe::default)
		basehtml = replacetextEx(basehtml, "\[tgui:storagecdn]", storage_iframe)
		return

	if(CONFIG_GET(string/asset_transport) == "webroot")
		var/datum/asset_transport/webroot/webroot = SSassets.transport

		var/datum/asset_cache_item/item = webroot.register_asset("iframe.html", file("tgui/public/iframe.html"))
		basehtml = replacetextEx(basehtml, "\[tgui:storagecdn]", webroot.get_asset_url("iframe.html", item))
		return

	if(!storage_iframe)
		return

	basehtml = replacetextEx(basehtml, "\[tgui:storagecdn]", storage_iframe)

/datum/controller/subsystem/tgui/Shutdown()
	close_all_uis()

/datum/controller/subsystem/tgui/stat_entry(msg)
	msg = "P:[length(all_uis)]"
	return ..()

/datum/controller/subsystem/tgui/fire(resumed = FALSE)
	if(!resumed)
		src.current_run = all_uis.Copy()
	// Cache for sanic speed (lists are references anyways)
	var/list/current_run = src.current_run
	while(length(current_run))
		var/datum/tgui/ui = current_run[length(current_run)]
		current_run.len--
		// TODO: Move user/src_object check to process()
		if(ui?.user && ui.src_object)
			ui.process(wait * 0.1)
		else
			ui.close(0)
		if(MC_TICK_CHECK)
			return

/**
 * public
 *
 * Requests a usable tgui window from the pool.
 * Returns null if pool was exhausted.
 *
 * required user mob
 * return datum/tgui
 */
/datum/controller/subsystem/tgui/proc/request_pooled_window(mob/user)
	if(!user.client)
		return null
	var/list/windows = user.client.tgui_windows
	var/window_id
	var/datum/tgui_window/window
	var/window_found = FALSE
	// Find a usable window
	for(var/i in 1 to TGUI_WINDOW_HARD_LIMIT)
		window_id = TGUI_WINDOW_ID(i)
		window = windows[window_id]
		// As we are looping, create missing window datums
		if(!window)
			window = new(user.client, window_id, pooled = TRUE)
		// Skip windows with acquired locks
		if(window.locked)
			continue
		if(window.status == TGUI_WINDOW_READY)
			addtimer(CALLBACK(src, PROC_REF(maintain_client_prewarm), user.client), 1 SECOND, TIMER_UNIQUE)
			return window
		if(window.status == TGUI_WINDOW_CLOSED)
			window.status = TGUI_WINDOW_LOADING
			window_found = TRUE
			break
	if(!window_found)
		log_tgui(user, "Error: Pool exhausted",
			context = "SStgui/request_pooled_window")
		return null
	addtimer(CALLBACK(src, PROC_REF(maintain_client_prewarm), user.client), 1 SECOND, TIMER_UNIQUE)
	return window

/**
 * Warm the reusable browser pool for a newly connected client.
 *
 * Slots are staggered by the caller so asset delivery and browser startup do
 * not create one large login spike. A slot already opened or acquired by a
 * real UI is left untouched.
 */
/datum/controller/subsystem/tgui/proc/prewarm_client_window(client/client, pool_index)
	if(!client || QDELETED(client) || pool_index < 1 || pool_index > TGUI_WINDOW_SOFT_LIMIT)
		return
	var/window_id = TGUI_WINDOW_ID(pool_index)
	var/datum/tgui_window/window = client.tgui_windows[window_id]
	if(!window)
		window = new(client, window_id, pooled = TRUE)
	if(window.locked || window.status != TGUI_WINDOW_CLOSED)
		return
	window.prewarmed = TRUE
	window.initialize(
		strict_mode = TRUE,
		fancy = client.prefs?.read_preference(/datum/preference/toggle/tgui_fancy),
		assets = list(get_asset_datum(/datum/asset/simple/tgui)),
	)
	var/flush_queue = window.send_asset(get_asset_datum(/datum/asset/simple/namespaced/fontawesome))
	flush_queue |= window.send_asset(get_asset_datum(/datum/asset/simple/namespaced/tgfont))
	flush_queue |= window.send_asset(get_asset_datum(/datum/asset/simple/namespaced/tgui_extra_fonts))
	flush_queue |= window.send_asset(get_asset_datum(/datum/asset/json/icon_ref_map))
	if(flush_queue)
		client.browse_queue_flush()

/** Keep a small idle reserve warm, starting at most one browser per call. */
/datum/controller/subsystem/tgui/proc/maintain_client_prewarm(client/client)
	if(!client || QDELETED(client))
		return
	var/reserve_count = 0
	var/closed_index
	for(var/index in 1 to TGUI_WINDOW_SOFT_LIMIT)
		var/window_id = TGUI_WINDOW_ID(index)
		var/datum/tgui_window/window = client.tgui_windows[window_id]
		if(!window)
			if(!closed_index)
				closed_index = index
			continue
		if(!window.locked && (window.status == TGUI_WINDOW_READY || (window.prewarmed && window.status == TGUI_WINDOW_LOADING)))
			reserve_count++
		else if(!window.locked && window.status == TGUI_WINDOW_CLOSED && !closed_index)
			closed_index = index
	if(reserve_count < prewarm_window_reserve && closed_index)
		prewarm_client_window(client, closed_index)

/datum/controller/subsystem/tgui/proc/schedule_client_prewarm(client/client)
	if(!client)
		return
	for(var/index in 1 to prewarm_window_reserve)
		var/datum/callback/prewarm_callback = CALLBACK(src, PROC_REF(maintain_client_prewarm), client)
		var/prewarm_delay = (1 + ((index - 1) * 2)) SECONDS
		addtimer(prewarm_callback, prewarm_delay)

/**
 * public
 *
 * Force closes all tgui windows.
 *
 * required user mob
 */
/datum/controller/subsystem/tgui/proc/force_close_all_windows(mob/user)
	log_tgui(user, context = "SStgui/force_close_all_windows")
	if(user.client)
		user.client.tgui_windows = list()
		for(var/i in 1 to TGUI_WINDOW_HARD_LIMIT)
			var/window_id = TGUI_WINDOW_ID(i)
			user << browse(null, "window=[window_id]")

/**
 * public
 *
 * Force closes the tgui window by window_id.
 *
 * required user mob
 * required window_id string
 */
/datum/controller/subsystem/tgui/proc/force_close_window(mob/user, window_id)
	log_tgui(user, context = "SStgui/force_close_window")
	// Close all tgui datums based on window_id.
	for(var/datum/tgui/ui in user.tgui_open_uis)
		if(ui.window && ui.window.id == window_id)
			ui.close(can_be_suspended = FALSE)
	// Close window directly just to be sure.
	user << browse(null, "window=[window_id]")

/**
 * public
 *
 * Try to find an instance of a UI, and push an update to it.
 *
 * required user mob The mob who opened/is using the UI.
 * required src_object datum The object/datum which owns the UI.
 * optional ui datum/tgui The UI to be updated, if it exists.
 * optional force_open bool If the UI should be re-opened instead of updated.
 *
 * return datum/tgui The found UI.
 */
/datum/controller/subsystem/tgui/proc/try_update_ui(
		mob/user,
		datum/src_object,
		datum/tgui/ui)
	// Look up a UI if it wasn't passed
	if(isnull(ui))
		ui = get_open_ui(user, src_object)
	// Couldn't find a UI.
	if(isnull(ui))
		return null
	ui.process_status()
	// UI ended up with the closed status
	// or is actively trying to close itself.
	// FIXME: Doesn't actually fix the paper bug.
	if(ui.status <= STATUS_CLOSE)
		ui.close()
		return null
	ui.send_update()
	return ui

/**
 * public
 *
 * Get a open UI given a user and src_object.
 *
 * required user mob The mob who opened/is using the UI.
 * required src_object datum The object/datum which owns the UI.
 *
 * return datum/tgui The found UI.
 */
/datum/controller/subsystem/tgui/proc/get_open_ui(mob/user, datum/src_object)
	// No UIs opened for this src_object
	if(!LAZYLEN(src_object?.open_tguis))
		return null
	for(var/datum/tgui/ui in src_object.open_tguis)
		// Make sure we have the right user
		if(ui.user == user)
			return ui
	return null

/**
 * public
 *
 * Update all UIs attached to src_object.
 *
 * required src_object datum The object/datum which owns the UIs.
 *
 * return int The number of UIs updated.
 */
/datum/controller/subsystem/tgui/proc/update_uis(datum/src_object)
	// No UIs opened for this src_object
	if(!LAZYLEN(src_object?.open_tguis))
		return 0
	var/count = 0
	for(var/datum/tgui/ui in src_object.open_tguis)
		// Check if UI is valid.
		if(ui?.src_object && ui.user && ui.src_object.tgui_host(ui.user))
			INVOKE_ASYNC(ui, TYPE_PROC_REF(/datum/tgui, process), wait * 0.1, TRUE)
			count++
	return count

/**
 * public
 *
 * Close all UIs attached to src_object.
 *
 * required src_object datum The object/datum which owns the UIs.
 *
 * return int The number of UIs closed.
 */
/datum/controller/subsystem/tgui/proc/close_uis(datum/src_object)
	// No UIs opened for this src_object
	if(!LAZYLEN(src_object?.open_tguis))
		return 0
	var/count = 0
	for(var/datum/tgui/ui in src_object.open_tguis)
		// Check if UI is valid.
		if(ui?.src_object && ui.user && ui.src_object.tgui_host(ui.user))
			ui.close()
			count++
	return count

/**
 * public
 *
 * Close all UIs regardless of their attachment to src_object.
 *
 * return int The number of UIs closed.
 */
/datum/controller/subsystem/tgui/proc/close_all_uis()
	var/count = 0
	for(var/datum/tgui/ui in all_uis)
		// Check if UI is valid.
		if(ui?.src_object && ui.user && ui.src_object.tgui_host(ui.user))
			ui.close()
			count++
	return count

/**
 * public
 *
 * Update all UIs belonging to a user.
 *
 * required user mob The mob who opened/is using the UI.
 * optional src_object datum If provided, only update UIs belonging this src_object.
 *
 * return int The number of UIs updated.
 */
/datum/controller/subsystem/tgui/proc/update_user_uis(mob/user, datum/src_object)
	var/count = 0
	if(length(user?.tgui_open_uis) == 0)
		return count
	for(var/datum/tgui/ui in user.tgui_open_uis)
		if(isnull(src_object) || ui.src_object == src_object)
			ui.process(wait * 0.1, force = 1)
			count++
	return count

/**
 * public
 *
 * Close all UIs belonging to a user.
 *
 * required user mob The mob who opened/is using the UI.
 * optional src_object datum If provided, only close UIs belonging this src_object.
 *
 * return int The number of UIs closed.
 */
/datum/controller/subsystem/tgui/proc/close_user_uis(mob/user, datum/src_object, logout = FALSE)
	var/count = 0
	if(length(user?.tgui_open_uis) == 0)
		return count
	for(var/datum/tgui/ui in user.tgui_open_uis)
		if((isnull(src_object) || ui.src_object == src_object) && ui.closeable)
			ui.close(logout = logout)
			count++
	return count

/**
 * private
 *
 * Add a UI to the list of open UIs.
 *
 * required ui datum/tgui The UI to be added.
 */
/datum/controller/subsystem/tgui/proc/on_open(datum/tgui/ui)
	ui.user?.tgui_open_uis |= ui
	LAZYOR(ui.src_object.open_tguis, ui)
	all_uis |= ui

/**
 * private
 *
 * Remove a UI from the list of open UIs.
 *
 * required ui datum/tgui The UI to be removed.
 *
 * return bool If the UI was removed or not.
 */
/datum/controller/subsystem/tgui/proc/on_close(datum/tgui/ui)
	// Remove it from the list of processing UIs.
	all_uis -= ui
	current_run -= ui
	// If the user exists, remove it from them too.
	if(ui.user)
		ui.user.tgui_open_uis -= ui
	if(ui.src_object)
		LAZYREMOVE(ui.src_object.open_tguis, ui)
	return TRUE

/**
 * private
 *
 * Handle client logout, by closing all their UIs.
 *
 * required user mob The mob which logged out.
 *
 * return int The number of UIs closed.
 */
/datum/controller/subsystem/tgui/proc/on_logout(mob/user)
	close_user_uis(user, logout = TRUE)

/**
 * private
 *
 * Handle clients switching mobs, by transferring their UIs.
 *
 * required user source The client's original mob.
 * required user target The client's new mob.
 *
 * return bool If the UIs were transferred.
 */
/datum/controller/subsystem/tgui/proc/on_transfer(mob/source, mob/target)
	// The old mob had no open UIs.
	if(length(source?.tgui_open_uis) == 0)
		return FALSE
	if(isnull(target.tgui_open_uis) || !istype(target.tgui_open_uis, /list))
		target.tgui_open_uis = list()
	// Transfer all the UIs.
	for(var/datum/tgui/ui in source.tgui_open_uis)
		// Inform the UIs of their new owner.
		ui.user = target
		target.tgui_open_uis += ui
	// Clear the old list.
	source.tgui_open_uis.Cut()
	return TRUE
