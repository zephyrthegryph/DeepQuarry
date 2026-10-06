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

/// One coherent, immutable TGUI publication. Windows retain this datum so a
/// later live build cannot mix their shell runtime with another build's chunks.
/datum/tgui_asset_generation
	var/id
	var/basehtml
	var/list/chunk_manifest
	var/list/chunk_files
	var/list/window_geometry_manifest
	/// A live generation's own shell/chunk bundles, created with it and owned by it.
	/// Null for the boot generation, which reads the asset registry's singletons.
	var/datum/asset/simple/live_shell_assets
	var/datum/asset/simple/namespaced/live_chunk_assets


/datum/tgui_asset_generation/proc/get_default_geometry(interface_name)
	var/list/geometry = LAZYACCESS(window_geometry_manifest, interface_name)
	if(!islist(geometry) || !isnum(geometry["width"]) || !isnum(geometry["height"]))
		return null
	return geometry

/datum/tgui_asset_generation/proc/get_interface_chunks(interface_name)
	return LAZYACCESS(chunk_manifest, interface_name)

/datum/tgui_asset_generation/proc/get_chunk_base_url()
	if(istype(chunk_assets(), /datum/asset/simple/namespaced/tgui_live_generation_chunks))
		var/datum/asset/simple/namespaced/tgui_live_generation_chunks/live_chunks = chunk_assets()
		return live_chunks.get_public_base_url()
	if(istype(chunk_assets(), /datum/asset/simple/namespaced/tgui_chunks))
		var/datum/asset/simple/namespaced/tgui_chunks/boot_chunks = chunk_assets()
		return boot_chunks.get_public_base_url()
	return null

/datum/tgui_asset_generation/proc/get_chunk_assets(list/filenames)
	if(!islist(filenames) || !length(filenames))
		return null
	if(istype(chunk_assets(), /datum/asset/simple/namespaced/tgui_live_generation_chunks))
		var/datum/asset/simple/namespaced/tgui_live_generation_chunks/live_chunks = chunk_assets()
		return live_chunks.get_assets(filenames)
	var/list/result = list()
	for(var/filename in filenames)
		var/datum/asset_cache_item/item = chunk_assets()?.assets[filename]
		if(item)
			result[filename] = item
	return result

SYSTEM_DEF(tgui)
	name = "tgui"
	phase = KERNEL_PHASE_K
	latency_class = LATENCY_L0
	wait = 9
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	init_stage = INITSTAGE_MAIN
	needs = list(
		/datum/system/assets
	)

	/// The open windows that opted into periodic refreshes (autoupdate). The system's one recurring work item
	/// exists only while this is non-empty. Everything else about a window is event-driven (see ui_status).
	var/list/autoupdating = list()
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
	/// Currently published coherent TGUI generation. New or reinitialized shells
	/// pin this object; older shells retain the generation they already loaded.
	var/datum/tgui_asset_generation/current_asset_generation
	/// All generations remain alive for the process lifetime so old content-addressed
	/// URLs and browse_rsc resources cannot disappear beneath an open shell.
	var/list/asset_generations = list()
	var/asset_generation_sequence = 0

/datum/system/tgui/preinit()
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

/datum/system/tgui/proc/load_chunk_manifest(manifest_path = "tgui/public/tgui-chunk-manifest.json")
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

/datum/system/tgui/proc/load_window_geometry_manifest(manifest_path = "tgui/public/tgui-window-manifest.json")
	if(fexists(manifest_path))
		var/raw = file2text(manifest_path)
		if(raw)
			window_geometry_manifest = json_decode(raw)

/datum/system/tgui/proc/get_default_geometry(interface_name)
	var/datum/tgui_asset_generation/generation = get_current_asset_generation()
	return generation?.get_default_geometry(interface_name)

/datum/system/tgui/proc/get_current_asset_generation() as /datum/tgui_asset_generation
	if(current_asset_generation)
		return current_asset_generation
	var/datum/tgui_asset_generation/generation = new
	generation.id = "boot"
	generation.basehtml = basehtml
	generation.chunk_manifest = chunk_manifest
	generation.chunk_files = chunk_files
	generation.window_geometry_manifest = window_geometry_manifest
	asset_generations += generation
	current_asset_generation = generation
	return generation

/// Validates and atomically publishes a complete live TGUI generation. Nothing
/// in the current generation is mutated; failure leaves every window untouched.
/datum/system/tgui/proc/reload_development_chunks()
	var/development_directory = "tgui/public/.tmp"
	var/development_manifest = "[development_directory]/tgui-chunk-manifest.json"
	var/development_geometry = "[development_directory]/tgui-window-manifest.json"
	if(!fexists(development_manifest) || !fexists(development_geometry) || !fexists("[development_directory]/tgui.bundle.js") || !fexists("[development_directory]/tgui.bundle.css"))
		log_tgui(null, "Rejected incomplete live TGUI generation: required shell or manifest file missing.", context = "SStgui/reload_development_chunks")
		return FALSE
	var/list/new_manifest = json_decode(file2text(development_manifest))
	var/list/new_geometry_manifest = json_decode(file2text(development_geometry))
	if(!islist(new_manifest) || !islist(new_geometry_manifest))
		log_tgui(null, "Rejected invalid live TGUI generation manifest.", context = "SStgui/reload_development_chunks")
		return FALSE
	var/list/chunk_filenames = list()
	var/list/new_chunk_files = list()
	for(var/interface_name in new_manifest)
		var/list/interface_files = new_manifest[interface_name]
		if(!islist(interface_files) || !length(interface_files))
			log_tgui(null, "Rejected live TGUI generation: [interface_name] has no chunk files.", context = "SStgui/reload_development_chunks")
			return FALSE
		for(var/filename in interface_files)
			if(findtext(filename, "/") || findtext(filename, "\\") || !fexists("[development_directory]/[filename]"))
				log_tgui(null, "Rejected live TGUI generation: unsafe or missing chunk [filename].", context = "SStgui/reload_development_chunks")
				return FALSE
			if(!chunk_filenames[filename])
				new_chunk_files += filename
			chunk_filenames[filename] = TRUE
	var/generation_id = "live-[++asset_generation_sequence]"
	var/datum/asset/simple/tgui_live_generation/new_shell = new(development_directory, generation_id)
	var/datum/asset/simple/namespaced/tgui_live_generation_chunks/new_chunks = new(development_directory, chunk_filenames)
	var/datum/tgui_asset_generation/generation = new
	generation.id = generation_id
	generation.basehtml = basehtml
	generation.chunk_manifest = new_manifest
	generation.chunk_files = new_chunk_files
	generation.window_geometry_manifest = new_geometry_manifest
	generation.live_shell_assets = new_shell
	generation.live_chunk_assets = new_chunks
	asset_generations += generation
	// The single assignment is the publication point. A window sees the complete
	// old generation or the complete new one, never partially-updated state.
	current_asset_generation = generation
	for(var/client/client in GLOB.clients)
		client.tgui_chunk_warm_started = FALSE
	log_tgui(null, "Published immutable TGUI asset generation [generation_id] with [length(new_chunk_files)] chunks.", context = "SStgui/reload_development_chunks")
	return TRUE

/datum/system/tgui/OnConfigLoad()
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

/datum/system/tgui/on_shutdown()
	close_all_uis()

/datum/system/tgui/stat_entry(msg)
	msg = "P:[length(all_uis)]"
	return ..()

/// The autoupdate pass (phase K): the refresh of the windows that opted into one. A window's status, range and
/// liveness are event-driven (om_ui_status_bind(), the ping timer): this is the only recurring work, and it parks
/// when no window is autoupdating (set_autoupdate(TRUE) wakes it).
/datum/system/tgui/reactions()
	. = ..()
	. += every(9, PROC_REF(refresh_autoupdating), phase = KERNEL_PHASE_K, when = PROC_REF(work_ready), lane = LANE_URGENT)

/datum/system/tgui/proc/refresh_autoupdating(dt)
	if(!length(autoupdating))
		return STEP_PARK
	for(var/datum/tgui/ui as anything in autoupdating.Copy())
		if(QDELETED(ui) || ui.closing)
			autoupdating -= ui
			continue
		ui.process()
	return STEP_DONE

/// Registers or drops `ui` from the autoupdate pass to match its autoupdate flag (only while it is open).
/datum/system/tgui/proc/sync_autoupdate(datum/tgui/ui)
	if(!(ui in all_uis))
		return
	if(ui.autoupdate && !QDELETED(ui) && !ui.closing)
		if(!(ui in autoupdating))
			autoupdating += ui
			log_tgui(ui.user, "autoupdate on", context = "SStgui/sync_autoupdate")
		kernel_wake_work("[type]:refresh_autoupdating")
	else
		autoupdating -= ui

/**
 * public
 *
 * Requests a usable tgui window from the pool.
 * Returns null if pool was exhausted.
 *
 * required user mob
 * return datum/tgui
 */
/datum/system/tgui/proc/request_pooled_window(mob/user)
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
		// An idle shell from an older publication must not be reused with the new
		// manifest. Mark it for a fresh browse() initialization on acquisition.
		if(window.status == TGUI_WINDOW_READY && window.asset_generation() != get_current_asset_generation())
			window.status = TGUI_WINDOW_CLOSED
		if(window.status == TGUI_WINDOW_READY)
			if(!after_pending(src, "prewarm:[REF(user.client)]"))
				after(src, 1 SECOND, PROC_REF(maintain_client_prewarm), key = "prewarm:[REF(user.client)]", with = list(user.client))
			return window
		if(window.status == TGUI_WINDOW_CLOSED)
			window.status = TGUI_WINDOW_LOADING
			window_found = TRUE
			break
	if(!window_found)
		log_tgui(user, "Error: Pool exhausted",
			context = "SStgui/request_pooled_window")
		return null
	if(!after_pending(src, "prewarm:[REF(user.client)]"))
		after(src, 1 SECOND, PROC_REF(maintain_client_prewarm), key = "prewarm:[REF(user.client)]", with = list(user.client))
	return window

/**
 * Warm the reusable browser pool for a newly connected client.
 *
 * Slots are staggered by the caller so asset delivery and browser startup do
 * not create one large login spike. A slot already opened or acquired by a
 * real UI is left untouched.
 */
/datum/system/tgui/proc/prewarm_client_window(client/client, pool_index)
	if(!client || QDELETED(client) || pool_index < 1 || pool_index > TGUI_WINDOW_SOFT_LIMIT)
		return
	var/window_id = TGUI_WINDOW_ID(pool_index)
	var/datum/tgui_window/window = client.tgui_windows[window_id]
	if(!window)
		window = new(client, window_id, pooled = TRUE)
	if(window.locked || window.status != TGUI_WINDOW_CLOSED)
		return
	window.prewarmed = TRUE
	EXPIRY_STAMP(window, prewarm_started_at, CLOCK_WORLD)
	window.initialize(
		strict_mode = TRUE,
		fancy = client.prefs?.read_preference(/datum/preference/toggle/tgui_fancy),
		assets = list(get_current_asset_generation().shell_assets()),
	)
	var/flush_queue = window.send_asset(get_asset_datum(/datum/asset/simple/namespaced/fontawesome))
	flush_queue |= window.send_asset(get_asset_datum(/datum/asset/simple/namespaced/tgfont))
	flush_queue |= window.send_asset(get_asset_datum(/datum/asset/simple/namespaced/tgui_extra_fonts))
	flush_queue |= window.send_asset(get_asset_datum(/datum/asset/json/icon_ref_map))
	if(flush_queue)
		client.session?.flush_assets()

/** Keep a small idle reserve warm, starting at most one browser per call. */
/datum/system/tgui/proc/maintain_client_prewarm(client/client)
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
		// A prewarmed shell that never reported `ready` (browser hung, page lost)
		// would otherwise count toward the reserve forever. Tear it down so the
		// slot is rebuilt.
		if(!window.locked && window.prewarmed && window.status == TGUI_WINDOW_LOADING \
			&& window.prewarm_started_at && ELAPSED(window, prewarm_started_at, CLOCK_WORLD) > TGUI_PREWARM_LOAD_TIMEOUT)
			log_tgui(client, "Prewarmed shell never became ready after [DisplayTimeText(world.time - window.prewarm_started_at)]; replacing it.", window = window)
			window.prewarmed = FALSE
			window.prewarm_started_at = 0
			window.close(can_be_suspended = FALSE)
		if(!window.locked && (window.status == TGUI_WINDOW_READY || (window.prewarmed && window.status == TGUI_WINDOW_LOADING)))
			reserve_count++
		else if(!window.locked && window.status == TGUI_WINDOW_CLOSED && !closed_index)
			closed_index = index
	if(reserve_count < prewarm_window_reserve && closed_index)
		prewarm_client_window(client, closed_index)

/datum/system/tgui/proc/schedule_client_prewarm(client/client)
	if(!client)
		return
	for(var/index in 1 to prewarm_window_reserve)
		after((1 + ((index - 1) * 2)) SECONDS, PROC_REF(maintain_client_prewarm), src, clock = CLOCK_WORLD, with = list(client))

/**
 * public
 *
 * Force closes all tgui windows.
 *
 * required user mob
 */
/datum/system/tgui/proc/force_close_all_windows(mob/user)
	log_tgui(user, context = "SStgui/force_close_all_windows")
	var/client/client = user?.client
	if(!client)
		return
	// Only the pooled slots are torn down. Dedicated windows (tgui_say, tgui_shock,
	// browseroutput, mapwindow.tooltip, rpane.mediapanel, lobby_browser, ...) share
	// this registry and must stay registered, exactly as reconcile_client_windows does.
	for(var/i in 1 to TGUI_WINDOW_HARD_LIMIT)
		var/window_id = TGUI_WINDOW_ID(i)
		var/datum/tgui_window/window = client.tgui_windows[window_id]
		if(window)
			// Drop any UI still attached so it does not keep a dead window around.
			if(window.locked_by())
				window.locked_by().close(can_be_suspended = FALSE)
			window.release_lock()
			window.status = TGUI_WINDOW_CLOSED
			window.message_queue = null
			client.tgui_windows.Remove(window_id)
		if(winexists(client, window_id)) // ALLOW(scheduler): tgui window setup/teardown winexists (asset/window setup)
			winset(client, window_id, "alpha=0")
			winshow(client, window_id, FALSE)
		client << browse(null, "window=[window_id]")

/// DreamSeeker keeps cloned native windows across reconnects and server process
/// restarts. Hide and close those shells before this client builds a fresh pool,
/// otherwise an old page can surface without a matching server-side datum.
/datum/system/tgui/proc/reconcile_client_windows(client/client)
	if(!client)
		return
	client.tgui_chunk_warm_started = FALSE
	for(var/index in 1 to TGUI_WINDOW_HARD_LIMIT)
		var/window_id = TGUI_WINDOW_ID(index)
		// Dedicated windows (statbrowser, browseroutput, tgui_say, etc.) share
		// this registry but do not use TGUI_WINDOW_ID and must remain registered.
		var/datum/tgui_window/stale_window = client.tgui_windows[window_id]
		if(stale_window)
			client.tgui_windows.Remove(window_id)
		if(winexists(client, window_id)) // ALLOW(scheduler): tgui window setup/teardown winexists (asset/window setup)
			winset(client, window_id, "alpha=0")
			winshow(client, window_id, FALSE)
		client << browse(null, "window=[window_id]")

/**
 * public
 *
 * Force closes the tgui window by window_id.
 *
 * required user mob
 * required window_id string
 */
/datum/system/tgui/proc/force_close_window(mob/user, window_id)
	log_tgui(user, context = "SStgui/force_close_window")
	// Close all tgui datums based on window_id.
	for(var/datum/tgui/ui in user.tgui_open_uis)
		if(ui.window() && ui.window().id == window_id)
			ui.close(can_be_suspended = FALSE)
	// Close window directly just to be sure.
	if(winexists(user.client, window_id)) // ALLOW(scheduler): tgui window setup/teardown winexists (asset/window setup)
		winset(user.client, window_id, "alpha=0")
		winshow(user.client, window_id, FALSE)
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
/datum/system/tgui/proc/try_update_ui(
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
/datum/system/tgui/proc/get_open_ui(mob/user, datum/src_object)
	RETURN_TYPE(/datum/tgui)
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
 * Pushes are coalesced (one per UI per OM_UI_THROTTLE window). `now_ui` is the UI
 * whose user just acted: it is pushed inline so the click feels instant.
 *
 * required src_object datum The object/datum which owns the UIs.
 * optional now_ui datum/tgui A UI to push immediately instead of coalescing.
 *
 * return int The number of UIs updated.
 */
/datum/system/tgui/proc/update_uis(datum/src_object, datum/tgui/now_ui)
	// No UIs opened for this src_object
	if(!LAZYLEN(src_object?.open_tguis))
		return 0
	var/count = 0
	for(var/datum/tgui/ui in src_object.open_tguis)
		// Check if UI is valid.
		if(ui?.src_object() && ui.user && ui.src_object().tgui_host(ui.user))
			if(ui == now_ui)
				ui.process(TRUE)
			else
				ui.request_push()
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
/datum/system/tgui/proc/close_uis(datum/src_object)
	// No UIs opened for this src_object
	if(!LAZYLEN(src_object?.open_tguis))
		return 0
	var/count = 0
	for(var/datum/tgui/ui in src_object.open_tguis)
		// Check if UI is valid.
		if(ui?.src_object() && ui.user && ui.src_object().tgui_host(ui.user))
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
/datum/system/tgui/proc/close_all_uis()
	var/count = 0
	for(var/datum/tgui/ui in all_uis)
		// Check if UI is valid.
		if(ui?.src_object() && ui.user && ui.src_object().tgui_host(ui.user))
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
/datum/system/tgui/proc/update_user_uis(mob/user, datum/src_object)
	var/count = 0
	if(length(user?.tgui_open_uis) == 0)
		return count
	for(var/datum/tgui/ui in user.tgui_open_uis)
		if(isnull(src_object) || (ui.src_object == src_object))
			ui.process(TRUE)
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
/datum/system/tgui/proc/close_user_uis(mob/user, datum/src_object, logout = FALSE)
	var/count = 0
	if(length(user?.tgui_open_uis) == 0)
		return count
	for(var/datum/tgui/ui in user.tgui_open_uis)
		if((isnull(src_object) || (ui.src_object == src_object)) && ui.closeable)
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
/datum/system/tgui/proc/on_open(datum/tgui/ui)
	ui.user?.tgui_open_uis |= ui
	LAZYOR(ui.src_object().open_tguis, ui)
	all_uis |= ui
	sync_autoupdate(ui)

/**
 * private
 *
 * Remove a UI from the list of open UIs.
 *
 * required ui datum/tgui The UI to be removed.
 *
 * return bool If the UI was removed or not.
 */
/datum/system/tgui/proc/on_close(datum/tgui/ui)
	// Remove it from the list of processing UIs.
	all_uis -= ui
	autoupdating -= ui
	// If the user exists, remove it from them too.
	if(ui.user)
		ui.user.tgui_open_uis -= ui
	if(ui.src_object())
		LAZYREMOVE(ui.src_object().open_tguis, ui)
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
/datum/system/tgui/proc/on_logout(mob/user)
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
/datum/system/tgui/proc/on_transfer(mob/source, mob/target)
	// The old mob had no open UIs.
	if(length(source?.tgui_open_uis) == 0 || QDELETED(target))
		return FALSE
	// Transfer all the UIs.
	for(var/datum/tgui/ui in source.tgui_open_uis)
		transfer_ui(ui, target)
	// Clear the old list.
	source.tgui_open_uis.Cut()
	return TRUE

/**
 * private
 *
 * Re-home one UI onto a different mob, keeping both mobs' open-UI lists coherent.
 *
 * required ui datum/tgui The UI to move.
 * required target mob The UI's new user.
 *
 * return bool If the UI was transferred.
 */
/datum/system/tgui/proc/transfer_ui(datum/tgui/ui, mob/target)
	if(QDELETED(ui) || ui.closing || QDELETED(target))
		return FALSE
	var/mob/source = ui.user
	if(source == target)
		return FALSE
	if(source && islist(source.tgui_open_uis))
		source.tgui_open_uis -= ui
	ui.user = target
	if(!islist(target.tgui_open_uis))
		target.tgui_open_uis = list()
	target.tgui_open_uis |= ui
	om_ui_status_bind(ui)
	return TRUE

/**
 * public
 *
 * Re-home every UI a src_object has open onto the given mob. Used by persistent,
 * client-scoped UIs (tooltip, media panel) whose window belongs to the client
 * rather than to any one mob, so they follow the client across mob changes
 * (lobby -> spawn, ghosting, respawn) instead of being left bound to a dead mob.
 *
 * required src_object datum The object whose UIs should follow the client.
 * required target mob The client's current mob.
 *
 * return int The number of UIs transferred.
 */
/datum/system/tgui/proc/rehome_uis(datum/src_object, mob/target)
	var/count = 0
	if(!LAZYLEN(src_object?.open_tguis) || QDELETED(target))
		return count
	for(var/datum/tgui/ui in src_object.open_tguis)
		if(transfer_ui(ui, target))
			count++
	return count

/// The shell asset bundle of this generation: its own for a live build, else the registry singleton.
/datum/tgui_asset_generation/proc/shell_assets() as /datum/asset/simple
	return live_shell_assets || get_asset_datum(/datum/asset/simple/tgui)

/// The chunk asset bundle of this generation: its own for a live build, else the registry singleton.
/datum/tgui_asset_generation/proc/chunk_assets() as /datum/asset/simple/namespaced
	return live_chunk_assets || get_asset_datum(/datum/asset/simple/namespaced/tgui_chunks)
