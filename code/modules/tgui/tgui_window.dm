/*!
 * Copyright (c) 2020 Aleksej Komarov
 * SPDX-License-Identifier: MIT
 */

/datum/tgui_window
	var/id
	var/tmp/client/client
	var/pooled
	var/pool_index
	var/is_browser = FALSE
	var/status = TGUI_WINDOW_CLOSED
	var/locked = FALSE
	var/visible = FALSE
	/// TRUE when the shared browser shell was initialized before a UI acquired it.
	var/prewarmed = FALSE
	/// Monotonic token identifying the current use of this reusable shell.
	var/generation = 0
	/// Immutable shell/manifest/chunk publication loaded by this browser window.
	var/tmp/datum/tgui_asset_generation/asset_generation
	/// TRUE when this pooled shell was cloned from the hidden native skin template.
	var/native_shell = FALSE
	/// TRUE when acquire_lock applied a generated or previously observed size while hidden.
	var/geometry_preapplied = FALSE
	/// Exact native geometry applied by acquire_lock, included in the initial
	/// browser payload so React does not repeat an asynchronous storage lookup.
	var/list/preapplied_geometry
	/// Rate limit for automatic local-development browser telemetry.
	COOLDOWN_DECLARE(perf_log_cooldown)
	/// Opaque token for the page most recently browse()'d into this window. Every
	/// message the page sends carries it, so a late message from a superseded page
	/// (e.g. its `ready` arriving after a reinitialize) cannot be mistaken for the
	/// current page's.
	var/document_id
	/// world.time at which a prewarm initialize() was issued, so an idle shell that
	/// never reports `ready` can be timed out and replaced.
	EXPIRY_DECLARE(prewarm_started_at)
	/// Ends the current one-second payload chunk budget window.
	COOLDOWN_DECLARE(payload_chunk_window_cooldown)
	/// payloadChunk topics accepted during the current accounting window.
	var/payload_chunks_this_window = 0
	var/tmp/datum/tgui/locked_by
	var/tmp/datum/subscriber_object
	var/subscriber_delegate
	var/fatally_errored = FALSE
	var/message_queue
	var/sent_assets
	// Vars passed to initialize proc (and saved for later)
	var/initial_strict_mode
	var/initial_fancy
	var/initial_assets
	var/initial_inline_html
	var/initial_inline_js
	var/initial_inline_css

	var/list/oversized_payloads

/**
 * public
 *
 * Create a new tgui window.
 *
 * required client /client
 * required id string A unique window identifier.
 */
/datum/tgui_window/New(client/client, id, pooled = FALSE)
	src.id = id
	rel_set(src, nameof(client), client)
	src.client().tgui_windows[id] = src
	src.pooled = pooled
	if(pooled)
		src.pool_index = TGUI_WINDOW_INDEX(id)

/**
 * public
 *
 * Initializes the window with a fresh page. Puts window into the "loading"
 * state. You can begin sending messages right after initializing. Messages
 * will be put into the queue until the window finishes loading.
 *
 * optional strict_mode bool - Enables strict error handling and BSOD.
 * optional fancy bool - If TRUE and if this is NOT a panel, will hide the window titlebar.
 * optional assets list - List of assets to load during initialization.
 * optional inline_html string - Custom HTML to inject.
 * optional inline_js string - Custom JS to inject.
 * optional inline_css string - Custom CSS to inject.
 */
/datum/tgui_window/proc/initialize(
		strict_mode = FALSE,
		fancy = FALSE,
		assets = list(),
		inline_html = "",
		inline_js = "",
		inline_css = "")
	#ifdef TGUI_DEBUGGING
	log_tgui(client(), "[id]/initiailize ([src])")
	#endif
	if(!client())
		return
	rel_set(src, nameof(asset_generation), SStgui.get_current_asset_generation())
	var/list/resolved_assets = list()
	var/include_tgui_shell = FALSE
	for(var/datum/asset/asset in assets)
		if(asset == get_asset_datum(/datum/asset/simple/tgui) || istype(asset, /datum/asset/simple/tgui_live_generation))
			include_tgui_shell = TRUE
			continue
		resolved_assets += asset
	if(include_tgui_shell && asset_generation()?.shell_assets())
		resolved_assets += asset_generation().shell_assets()
	src.initial_strict_mode = strict_mode
	src.initial_fancy = fancy
	src.initial_assets = resolved_assets
	src.initial_inline_html = inline_html
	src.initial_inline_js = inline_js
	src.initial_inline_css = inline_css
	status = TGUI_WINDOW_LOADING
	fatally_errored = FALSE
	// A fresh page gets a fresh document token; see on_message().
	var/static/document_sequence = 0
	document_id = "[id]-[world.time]-[++document_sequence]"
	// browse() popup options cannot make a newly-created native window hidden.
	// Clone an already-hidden skin window first, so browse() targets its existing
	// browser control without ever painting a default popup on screen.
	if(pooled)
		if(!winexists(client(), id)) // ALLOW(scheduler): tgui window initialize() winexists (asset/window setup)
			winclone(client(), "tgui_window_template", id)
		native_shell = winexists(client(), id) == "MAIN" // ALLOW(scheduler): tgui window initialize() winexists (asset/window setup)
		if(native_shell)
			winshow(client(), id, FALSE)
			winset(client(), id, "alpha=0;titlebar=[!fancy];can-resize=[!fancy];can-minimize=false;on-close=\"uiclose [id]\"")
	// Build window options
	var/options = "file=[id].html;can_minimize=0;auto_format=0;"
	// Remove titlebar and resize handles for a fancy window
	if(fancy)
		options += "titlebar=0;can_resize=0;"
	else
		options += "titlebar=1;can_resize=1;"
	// Open pooled (normal interface) windows hidden so BYOND doesn't paint the
	// freshly-browse()'d window at its default geometry for the window lifetime
	// before React mounts — that's the "bigger box flashes then resizes" flicker.
	// The window is revealed tgui-side once content is ready: a <Window> interface
	// reveals itself AFTER applying geometry (layouts/Window.tsx), the route-level
	// fallback reveals everything else on mount (routes.tsx), and resume()
	// (events/handlers/update.ts) is a delayed failsafe. All paths fire for a fresh
	// (suspended) window regardless of layout, so this can't strand a window hidden.
	// Scoped to pooled windows only — dedicated windows (lobby, media, tooltip)
	// manage their own visibility and are left alone.
	// Generate page html
	var/html = asset_generation()?.basehtml || tgui_basehtml()
	html = replacetextEx(html, "\[tgui:windowId]", id)
	html = replacetextEx(html, "\[tgui:strictMode]", strict_mode)
	// Inject assets
	var/inline_assets_str = ""
	for(var/datum/asset/asset in resolved_assets)
		var/mappings = asset.get_url_mappings()
		for(var/name in mappings)
			var/url = mappings[name]
			// Not encoding since asset strings are considered safe
			if(copytext(name, -4) == ".css")
				inline_assets_str += "Byond.loadCss('[url]', true);\n"
			else if(copytext(name, -3) == ".js")
				inline_assets_str += "Byond.loadJs('[url]', true);\n"
		asset.send(client())
	if(length(inline_assets_str))
		inline_assets_str = "<script>\n" + inline_assets_str + "</script>\n"
	html = replacetextEx(html, "<!-- tgui:assets -->\n", inline_assets_str)
	// Inject inline HTML
	if (inline_html)
		html = replacetextEx(html, "<!-- tgui:inline-html -->", isfile(inline_html) ? file2text(inline_html) : inline_html)
	// Inject inline JS. The document shim runs first: it tags every tgui topic this
	// page sends with the page's document_id (helpers.js is already loaded at this
	// point, and both the shell's own `ready` and all React-side messages route
	// through Byond.topic), so the server can reject messages from a stale page.
	var/document_shim = "<script>\n(function(){var documentId=\"[document_id]\";var topic=Byond.topic;Byond.topic=function(params){if(params&&params.tgui){params.document_id=documentId;}return topic.call(Byond,params);};})();\n</script>\n"
	if (inline_js)
		inline_js = "<script>\n'use strict';\n[isfile(inline_js) ? file2text(inline_js) : inline_js]\n</script>"
	else
		inline_js = ""
	html = replacetextEx(html, "<!-- tgui:inline-js -->", document_shim + inline_js)
	// Inject inline CSS
	if (inline_css)
		inline_css = "<style>\n[isfile(inline_css) ? file2text(inline_css) : inline_css]\n</style>"
		html = replacetextEx(html, "<!-- tgui:inline-css -->", inline_css)
	// Open the window
	client() << browse(html, "window=[id];[options]")
	if(native_shell)
		// Defensive across client versions: only the JS geometry transaction may
		// make a reusable shell visible.
		winshow(client(), id, FALSE)
	// Detect whether the control is a browser
	is_browser = winexists(client(), id) == "BROWSER" // ALLOW(scheduler): tgui window initialize() winexists (asset/window setup)
	// Instruct the client to signal UI when the window is closed.
	if(!is_browser)
		winset(client(), id, "on-close=\"uiclose [id]\"")

/**
 * public
 *
 * Reinitializes the panel with previous data used for initialization.
 */
/datum/tgui_window/proc/reinitialize()
	initialize(
		strict_mode = initial_strict_mode,
		fancy = initial_fancy,
		assets = initial_assets,
		inline_html = initial_inline_html,
		inline_js = initial_inline_js,
		inline_css = initial_inline_css)
	// Resend assets
	for(var/datum/asset/asset in sent_assets)
		send_asset(asset)

/**
 * public
 *
 * Checks if the window is ready to receive data.
 *
 * return bool
 */
/datum/tgui_window/proc/is_ready()
	return status == TGUI_WINDOW_READY

/**
 * public
 *
 * Checks if the window can be sanely suspended.
 *
 * return bool
 */
/datum/tgui_window/proc/can_be_suspended()
	return !fatally_errored \
		&& pooled \
		&& pool_index > 0 \
		&& pool_index <= TGUI_WINDOW_SOFT_LIMIT \
		&& status == TGUI_WINDOW_READY

/**
 * public
 *
 * Acquire the window lock. Pool will not be able to provide this window
 * to other UIs for the duration of the lock.
 *
 * Can be given an optional tgui datum, which will be automatically
 * subscribed to incoming messages via the on_message proc.
 *
 * optional ui /datum/tgui
 */
/datum/tgui_window/proc/acquire_lock(datum/tgui/ui, list/default_geometry)
	// A READY pooled window may still be visibly painting its previous interface:
	// close() sends the browser-side suspend asynchronously, and a rapid reopen can
	// acquire the shell before that message is processed. Hide it synchronously on
	// the server before the new owner can send content, otherwise the new content
	// flashes at the previous interface's geometry and React hides it a frame later.
	if(client() && pooled)
		geometry_preapplied = FALSE
		preapplied_geometry = null
		#ifdef TGUI_DEV_DIAGNOSTICS
		log_tgui(client(), "TGUI transition: stage=server-acquire-hide-sending generation=[generation + 1] previous_visible=[visible] status=[status] native_shell=[native_shell].", window = src)
		#endif
		if(native_shell)
			winset(client(), id, "alpha=0")
		winshow(client(), id, FALSE)
		var/list/resolved_geometry = LAZYACCESS(client().tgui_resolved_geometries, ui?.interface)
		if(islist(resolved_geometry))
			var/list/native_settings = list()
			if(resolved_geometry["size"])
				native_settings["size"] = resolved_geometry["size"]
			if(resolved_geometry["pos"])
				native_settings["pos"] = resolved_geometry["pos"]
			if(length(native_settings))
				winset(client(), id, native_settings)
				preapplied_geometry = native_settings.Copy()
			geometry_preapplied = TRUE
		else if(islist(default_geometry))
			var/width = default_geometry["width"]
			var/height = default_geometry["height"]
			if(isnum(width) && isnum(height))
				var/default_size = "[width]x[height]"
				winset(client(), id, "size=[default_size]")
				preapplied_geometry = list("size" = default_size)
				geometry_preapplied = TRUE
		#ifdef TGUI_DEV_DIAGNOSTICS
		log_tgui(client(), "TGUI transition: stage=server-acquire-hide-sent generation=[generation + 1].", window = src)
		#endif
	generation++
	locked = TRUE
	rel_set(src, nameof(locked_by), ui)
	visible = FALSE

/**
 * public
 *
 * Release the window lock.
 */
/datum/tgui_window/proc/release_lock()
	// Clean up assets sent by tgui datum which requested the lock
	if(locked)
		sent_assets = null
	locked = FALSE
	rel_clear(src, nameof(locked_by))

/**
 * public
 *
 * Subscribes the datum to consume window messages on a specified proc.
 *
 * Note, that this supports only one subscriber, because code for that
 * is simpler and therefore faster. If necessary, this can be rewritten
 * to support multiple subscribers.
 */
/datum/tgui_window/proc/subscribe(datum/object, delegate)
	rel_set(src, nameof(subscriber_object), object)
	subscriber_delegate = delegate

/**
 * public
 *
 * Unsubscribes the datum. Do not forget to call this when cleaning up.
 */
/datum/tgui_window/proc/unsubscribe(datum/object)
	rel_clear(src, nameof(subscriber_object))
	subscriber_delegate = null

/**
 * public
 *
 * Close the UI.
 *
 * optional can_be_suspended bool
 */
/datum/tgui_window/proc/close(can_be_suspended = TRUE)
	if(!client())
		release_lock()
		status = TGUI_WINDOW_CLOSED
		message_queue = null
		return
	if(can_be_suspended && can_be_suspended())
		#ifdef TGUI_DEBUGGING
		log_tgui(client(), "[id]/close: suspending")
		#endif
		// Do not rely on the asynchronous browser suspend handler to hide the shell.
		// The pool can hand this READY window to another UI immediately after return.
		if(pooled)
			#ifdef TGUI_DEV_DIAGNOSTICS
			log_tgui(client(), "TGUI transition: stage=server-release-hide-sending generation=[generation] previous_visible=[visible] status=[status] native_shell=[native_shell].", window = src)
			#endif
			if(native_shell)
				winset(client(), id, "alpha=0")
			winshow(client(), id, FALSE)
			#ifdef TGUI_DEV_DIAGNOSTICS
			log_tgui(client(), "TGUI transition: stage=server-release-hide-sent generation=[generation].", window = src)
			#endif
		visible = FALSE
		status = TGUI_WINDOW_READY
		send_message("suspend")
		return
	#ifdef TGUI_DEBUGGING
	log_tgui(client(), "[id]/close")
	#endif
	release_lock()
	visible = FALSE
	status = TGUI_WINDOW_CLOSED
	message_queue = null
	// Do not close the window to give user some time
	// to read the error message.
	if(!fatally_errored)
		client() << browse(null, "window=[id]")

/**
 * public
 *
 * Sends a message to tgui window.
 *
 * required type string Message type
 * required payload list Message payload
 * optional force bool Send regardless of the ready status.
 */
/datum/tgui_window/proc/send_message(type, payload, force)
	if(!client())
		return
	var/message = TGUI_CREATE_MESSAGE(type, payload)
	// Place into queue if window is still loading
	if(!force && status != TGUI_WINDOW_READY)
		if(!message_queue)
			message_queue = list()
		message_queue += list(message)
		return
	client() << output(message, is_browser \
		? "[id]:update" \
		: "[id].browser:update")

/**
 * public
 *
 * Sends a raw payload to tgui window.
 *
 * required message string JSON+urlencoded blob to send.
 * optional force bool Send regardless of the ready status.
 */
/datum/tgui_window/proc/send_raw_message(message, force)
	if(!client())
		return
	// Place into queue if window is still loading
	if(!force && status != TGUI_WINDOW_READY)
		if(!message_queue)
			message_queue = list()
		message_queue += list(message)
		return
	client() << output(message, is_browser \
		? "[id]:update" \
		: "[id].browser:update")

/**
 * public
 *
 * Makes an asset available to use in tgui.
 *
 * required asset datum/asset
 *
 * return bool - TRUE if any assets had to be sent to the client
 */
/datum/tgui_window/proc/send_asset(datum/asset/asset)
	if(!client() || !asset)
		return
	LAZYOR(sent_assets, list(asset))
	. = asset.send(client())
	if(istype(asset, /datum/asset/spritesheet))
		var/datum/asset/spritesheet/spritesheet = asset
		send_message("asset/stylesheet", spritesheet.css_filename())
	else if(istype(asset, /datum/asset/spritesheet_batched))
		var/datum/asset/spritesheet_batched/spritesheet = asset
		send_message("asset/stylesheet", spritesheet.css_filename())
	send_raw_message(asset.get_serialized_url_mappings())

/**
 * private
 *
 * Sends queued messages if the queue wasn't empty.
 */
/datum/tgui_window/proc/flush_message_queue()
	if(!client() || !message_queue)
		return
	for(var/message in message_queue)
		client() << output(message, is_browser \
			? "[id]:update" \
			: "[id].browser:update")
	message_queue = null

/**
 * public
 *
 * Replaces the inline HTML content.
 *
 * required inline_html string HTML to inject
 */
/datum/tgui_window/proc/replace_html(inline_html = "")
	client() << output(url_encode(inline_html), is_browser \
		? "[id]:replaceHtml" \
		: "[id].browser:replaceHtml")

/** Verify a newly-warmed native shell never became visible on the client. */
/datum/tgui_window/proc/audit_prewarmed_hidden()
	if(!client() || locked || !prewarmed)
		return
	dx_winget(src, client(), id, "is-visible", PROC_REF(prewarmed_visibility_read))

/// dx_winget() callback for audit_prewarmed_hidden(): re-checks, then hides a shown shell.
/datum/tgui_window/proc/prewarmed_visibility_read(is_visible)
	if(!client() || locked || !prewarmed)
		return
	if(is_visible == "true")
		log_tgui(client(), "Prewarmed shell became visible; forcing it hidden.", window = src)
		winshow(client(), id, FALSE)

/**
 * private
 *
 * Callback for handling incoming tgui messages.
 */
/datum/tgui_window/proc/on_message(type, payload, href_list)
	// Drop messages from a page this window has since replaced. Without this a
	// superseded page's late `ready` would flip the window READY and flush the new
	// page's queued first update into the old document, where it is lost. Logs are
	// still collected so a stale page's errors remain visible.
	var/reported_document = href_list?["document_id"]
	if(document_id && reported_document && reported_document != document_id && type != "log")
		log_tgui(client(), "Ignored [type] from stale document [reported_document]; current document is [document_id].", window = src)
		return
	// A reusable shell's browser keeps retrying `suspend` until the server confirms
	// it. If the shell was reacquired by a new UI in the meantime, that retry must
	// not close the new occupant.
	if(type == "suspend")
		var/suspend_generation = text2num("[payload?["generation"]]")
		if(suspend_generation && suspend_generation != generation)
			log_tgui(client(), "Ignored stale suspend for generation [suspend_generation]; current generation is [generation].", window = src)
			return
	// Status can be READY if user has refreshed the window.
	if(type == "ready" && status == TGUI_WINDOW_READY)
		// Resend the assets
		for(var/asset in sent_assets)
			send_asset(asset)
	// Mark this window as fatally errored which prevents it from
	// being suspended.
	if(type == "log" && href_list["fatal"])
		fatally_errored = TRUE
	// Mark window as ready since we received this message from somewhere
	if(status != TGUI_WINDOW_READY)
		status = TGUI_WINDOW_READY
		flush_message_queue()
	if(type == "ready" && !client().tgui_chunk_warm_started)
		var/chunk_base_url = asset_generation()?.get_chunk_base_url()
		if((findtext(chunk_base_url, "http://") == 1 || findtext(chunk_base_url, "https://") == 1) && length(asset_generation()?.chunk_files))
			client().tgui_chunk_warm_started = TRUE
			send_message("chunk/warm", list(
				"url" = chunk_base_url,
				"files" = asset_generation().chunk_files,
			))
	if(type == "ready" && prewarmed && !locked)
		audit_prewarmed_hidden()
	// Pass message to UI that requested the lock
	if(locked && locked_by())
		var/prevent_default = locked_by().on_message(type, payload, href_list)
		if(prevent_default)
			return
	// Pass message to the subscriber
	else if(subscriber_object())
		var/prevent_default = call(
			subscriber_object(),
			subscriber_delegate)(type, payload, href_list)
		if(prevent_default)
			return
	// If not locked, handle these message types
	switch(type)
		if("ping")
			send_message("ping/reply", payload)
		if("visible")
			var/reported_generation = text2num("[payload?["generation"]]")
			if(reported_generation && reported_generation != generation)
				log_tgui(client(), "Ignored stale reveal for generation [reported_generation]; current generation is [generation].", window = src)
				return
			visible = TRUE
			var/reported_size = payload?["geometry"]?["size"]
			var/reported_pos = payload?["geometry"]?["pos"]
			if(locked_by()?.interface && istext(reported_size))
				var/static/regex/safe_size = regex(@"^\d+x\d+$")
				if(safe_size.Find(reported_size))
					var/list/safe_geometry = list("size" = reported_size)
					if(istext(reported_pos))
						var/static/regex/safe_pos = regex(@"^-?\d+,-?\d+$")
						if(safe_pos.Find(reported_pos))
							safe_geometry["pos"] = reported_pos
					var/client/geometry_client = client()
					LAZYSET(geometry_client.tgui_resolved_geometries, locked_by().interface, safe_geometry)
			PUBLISH_LEGACY(src, /datum/notice/tgui_window_visible, client())
		if("perf/flicker")
			if(!accept_perf_telemetry())
				return
			log_tgui(client(), "Automatic TGUI flicker telemetry: [truncated_perf_payload(payload)]", window = src)
		if("perf/status")
			if(!accept_perf_telemetry())
				return
			log_tgui(client(), "Automatic TGUI performance telemetry: [truncated_perf_payload(payload)]", window = src)
		if("perf/transition")
			if(!accept_perf_telemetry())
				return
			log_tgui(client(), "TGUI transition: [truncated_perf_payload(payload)]", window = src)
		if("suspend")
			close(can_be_suspended = TRUE)
		if("close")
			close(can_be_suspended = FALSE)
		if("openLink")
			client() << link(href_list["url"])
		if("cacheReloaded")
			reinitialize()
		if("chat/resend")
			SSchat.handle_resend(client(), payload)
		if("oversizedPayloadRequest")
			var/payload_id = payload["id"]
			var/chunk_count = text2num(payload["chunkCount"])
			// Cap both the size of one assembly and how many a single window may
			// hold open at once, so a client cannot park unbounded partial buffers.
			var/permit_payload = istext(payload_id) \
				&& chunk_count \
				&& chunk_count <= MAX_MESSAGE_CHUNKS \
				&& length(oversized_payloads) < TGUI_MAX_OVERSIZED_PAYLOADS \
				&& !oversized_payloads[payload_id]
			if(permit_payload)
				create_oversized_payload(payload_id, payload["type"], chunk_count)
			send_message("oversizePayloadResponse", list("allow" = permit_payload, "id" = payload_id))
		if("payloadChunk")
			if(!accept_payload_chunk())
				return
			var/payload_id = payload["id"]
			append_payload_chunk(payload_id, payload["chunk"])
			send_message("acknowledgePayloadChunk", list("id" = payload_id))

/**
 * private
 *
 * Gate for browser perf/... telemetry topics. Outside a diagnostics build only
 * localhost clients may submit them, and every window is limited to one accepted
 * topic per TGUI_PERF_LOG_COOLDOWN regardless of build.
 */
/datum/tgui_window/proc/accept_perf_telemetry()
	#ifndef TGUI_DEV_DIAGNOSTICS
	if(client()?.address != "127.0.0.1" && client()?.address != "::1")
		return FALSE
	#endif
	if(!COOLDOWN_FINISHED(src, perf_log_cooldown))
		return FALSE
	COOLDOWN_START(src, perf_log_cooldown, TGUI_PERF_LOG_COOLDOWN)
	return TRUE

/// Bounds a browser telemetry payload before it is written to the log.
/datum/tgui_window/proc/truncated_perf_payload(payload)
	var/encoded_payload = json_encode(payload)
	if(length(encoded_payload) > 8000)
		encoded_payload = copytext(encoded_payload, 1, 8001)
	return encoded_payload

/// Per-window, per-second budget for payloadChunk topics (which bypass the
/// client Topic rate limiter).
/datum/tgui_window/proc/accept_payload_chunk()
	if(!COOLDOWN_TIMELEFT(src, payload_chunk_window_cooldown))
		COOLDOWN_START(src, payload_chunk_window_cooldown, 1 SECOND)
		payload_chunks_this_window = 0
	if(payload_chunks_this_window >= TGUI_MAX_PAYLOAD_CHUNKS_PER_SECOND)
		return FALSE
	payload_chunks_this_window++
	return TRUE

/datum/tgui_window/vv_edit_var(var_name, var_value)
	return var_name != NAMEOF(src, id) && ..()

/datum/tgui_window/proc/create_oversized_payload(payload_id, message_type, chunk_count)
	if(LAZYACCESS(oversized_payloads, payload_id))
		stack_trace("Attempted to create oversized tgui payload with duplicate ID.")
		return
	LAZYINITLIST(oversized_payloads); oversized_payloads[payload_id] = list(
		"type" = message_type,
		"count" = chunk_count,
		"chunks" = list(),
	)
	after(src, 10 SECONDS, PROC_REF(remove_oversized_payload), key = "payload_timeout:[payload_id]", with = list(payload_id))

/datum/tgui_window/proc/append_payload_chunk(payload_id, chunk)
	var/list/payload = LAZYACCESS(oversized_payloads, payload_id)
	if(!payload)
		return
	var/list/chunks = payload["chunks"]
	chunks += chunk
	if(length(chunks) >= payload["count"])
		cancel_after(src, "payload_timeout:[payload_id]")
		var/message_type = payload["type"]
		var/final_payload = chunks.Join()
		remove_oversized_payload(payload_id)
		if (!rustg_json_is_valid(final_payload))
			log_tgui(client(), "Error: Invalid JSON in reassembled oversized payload", window = src)
			return
		on_message(message_type, json_decode(final_payload), list("type" = message_type, "payload" = final_payload, "tgui" = TRUE, "window_id" = id))
	else
		after(src, 10 SECONDS, PROC_REF(remove_oversized_payload), key = "payload_timeout:[payload_id]", with = list(payload_id))

/datum/tgui_window/proc/remove_oversized_payload(payload_id)
	LAZYREMOVE(oversized_payloads, payload_id)

/// The asset_generation this refers to (a relation view: null once that is deleted).
/datum/tgui_window/proc/asset_generation() as /datum/tgui_asset_generation
	return asset_generation

/// The subscriber_object this refers to (a relation view: null once that is deleted).
/datum/tgui_window/proc/subscriber_object() as /datum
	return subscriber_object

/// The locked_by this refers to (a relation view: null once that is deleted).
/datum/tgui_window/proc/locked_by() as /datum/tgui
	return locked_by

/// The client this refers to (a relation view: null once that is deleted).
/datum/tgui_window/proc/client() as /client
	return client
