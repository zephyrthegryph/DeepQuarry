// One /datum/client_session per connection. It owns the connection-scoped datums (panels,
// the tgui say/shock windows, the tgui window pool, tooltips, media, the loot panel, the
// interaction menu, the keybind editor, the volume panel) and the asset-delivery jobs, so
// client/Destroy is qdel(session) and nothing is missed. /datum/persistent_client stays per
// player; the session is per connection.

/// How long an asset flush waits for the client's ack before continuing anyway.
#define ASSET_FLUSH_TIMEOUT (5 SECONDS)

/client/var/tmp/datum/client_session/session

/datum/client_session
	/// The connection this session belongs to. A /client isn't a datum, so this is a plain ref
	/// that Destroy() drops.
	var/tmp/client/client
	/// job id text -> TRUE, for acked asset jobs.
	var/tmp/list/completed_asset_jobs
	var/tmp/last_asset_job = 0
	var/tmp/last_completed_asset_job = 0
	/// job id text -> list(target, proc_ref, args): who continues when the ack arrives.
	var/tmp/list/asset_waiters

// The client's own hrefs (the stat panel, the Discord link, the command bar): ops of its session, so they run as every other link does. Each does
// what the matching /client/proc/topic_* proc says.
CAPABILITIES(/datum/client_session)
	op("priv_msg", topic("priv_msg", arg("priv_msg", schema_text(64), optional = TRUE)), then(PROC_REF(topic_priv_msg)))
	op("mentorhelp_msg", topic("mentorhelp_msg", arg("mentorhelp_msg", schema_text(64), optional = TRUE)), then(PROC_REF(topic_mentorhelp_msg)))
	op("discord_reg", topic("discord_reg", arg("discord_reg", schema_text(128), optional = TRUE)), then(PROC_REF(topic_discord_reg)))
	op("reload_statbrowser", topic("reload_statbrowser"), then(PROC_REF(topic_reload_statbrowser)))
	op("asset_cache_preload_data", topic("asset_cache_preload_data", arg("asset_cache_preload_data", schema_text(), optional = TRUE)), then(PROC_REF(topic_asset_cache_preload_data)))
	op("commandbar_typing", topic("commandbar_typing", arg("verb", schema_text(64), optional = TRUE), arg("argument_length", num(), optional = TRUE)), then(PROC_REF(topic_commandbar_typing)))
	op("open_link", topic("action=openLink", arg("link", schema_text(1024), optional = TRUE)), then(PROC_REF(topic_open_link)))

/datum/client_session/proc/topic_priv_msg(datum/act/op/A, href_priv_msg)
	client?.topic_priv_msg(A.actor, href_priv_msg)

/datum/client_session/proc/topic_mentorhelp_msg(datum/act/op/A, href_mentorhelp_msg)
	client?.topic_mentorhelp_msg(A.actor, href_mentorhelp_msg)

/datum/client_session/proc/topic_discord_reg(datum/act/op/A, href_discord_reg)
	client?.topic_discord_reg(A.actor, href_discord_reg)

/datum/client_session/proc/topic_reload_statbrowser(datum/act/op/A)
	client?.topic_reload_statbrowser(A.actor)

/datum/client_session/proc/topic_asset_cache_preload_data(datum/act/op/A, href_asset_cache_preload_data)
	client?.topic_asset_cache_preload_data(A.actor, href_asset_cache_preload_data)

/datum/client_session/proc/topic_commandbar_typing(datum/act/op/A, href_verb, href_argument_length)
	client?.topic_commandbar_typing(A.actor, href_verb, href_argument_length)

/datum/client_session/proc/topic_open_link(datum/act/op/A, href_link)
	client?.topic_open_link(A.actor, href_link)

/datum/client_session/New(client/C)
	..()
	client = C

/// Deletes every connection-scoped datum the client holds, then drops the waiters.
/datum/client_session/on_destroy(force)
	if(client)
		var/static/list/owned_vars = list("stat_panel", "tgui_say", "tgui_shocker", "tgui_panel", "loot_panel", "tooltips", "media", "interaction_menu", "keybind_editor", "volume_panel", "fakeConversations")
		for(var/var_name in owned_vars)
			var/datum/owned = client.vars[var_name]
			if(owned)
				ended_with(owned, src)
			client.vars[var_name] = null // ALLOW(api): clears a fixed static list of client-owned panel vars on session teardown
		for(var/window_id in client.tgui_windows)
			var/datum/tgui_window/window = client.tgui_windows[window_id]
			if(window)
				ended_with(window, src)
		client.tgui_windows = list()
	asset_waiters = null
	completed_asset_jobs = null
	client = null
	..()

/// Sends the verify page: the client's browse queue is FIFO, so its ack means every browse_rsc
/// sent before it has arrived. With a `target`, `proc_ref` (with any extra args) runs when the
/// ack arrives, or after ASSET_FLUSH_TIMEOUT if it never does. Nothing sleeps or polls.
/// Returns the job id.
/datum/client_session/proc/flush_assets(datum/target, proc_ref, ...)
	var/job = ++last_asset_job
	client << browse({"<script>window.location.href="byond://?asset_cache_confirm_arrival=[job]"</script>"}, "window=asset_cache_browser&file=asset_cache_send_verify.htm")
	if(target && proc_ref)
		LAZYSET(asset_waiters, "[job]", list(target, proc_ref, length(args) > 2 ? args.Copy(3) : null))
		after(src, ASSET_FLUSH_TIMEOUT, PROC_REF(asset_job_finished), with = list(job))
	return job

/// A job's ack arrived, or its timeout fired: runs the waiter, once.
/datum/client_session/proc/asset_job_finished(job)
	var/list/waiter = LAZYACCESS(asset_waiters, "[job]")
	if(!waiter)
		return
	LAZYREMOVE(asset_waiters, "[job]")
	var/datum/target = waiter[1]
	if(QDELETED(target))
		return
	var/list/waiter_args = waiter[3]
	call(target, waiter[2])(arglist(waiter_args || list())) // the continuation of an asset flush, run from the ack topic or the timeout

/// Process asset cache client topic calls for `"asset_cache_confirm_arrival=[INT]"`.
/// Returns null for a valid arrival (handled), else the job id (or TRUE) for the caller to reject.
/datum/client_session/proc/confirm_asset_arrival(job_id)
	var/asset_cache_job = round(text2num(job_id))
	// Because we skip the limiter, this must be a valid arrival and not somebody tricking us
	// into letting them append to a list without limit.
	if(asset_cache_job > 0 && asset_cache_job <= last_asset_job && !LAZYACCESS(completed_asset_jobs, "[asset_cache_job]"))
		LAZYSET(completed_asset_jobs, "[asset_cache_job]", TRUE)
		last_completed_asset_job = max(last_completed_asset_job, asset_cache_job)
		asset_job_finished(asset_cache_job)
		return null
	return asset_cache_job || TRUE
