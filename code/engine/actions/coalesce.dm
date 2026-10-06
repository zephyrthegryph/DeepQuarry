// coalesce(interval): many triggers, one run (doc/rewrite/final_api.html, section 10 "After hooks"; doc/rewrite/ai_packs.md A1).
//
//	on_notice(/datum/notice/chunk_activity, coalesce(PROC_REF(perceive_interval)), then(PROC_REF(perceive)))
//	on_change(nameof(target), ANY, coalesce(2 SECONDS), then(PROC_REF(retarget)))
//
// A part of an on_notice() or on_change() entry. Parts before it (when(), chance()) gate each trigger; the parts after it run once per window:
// the first trigger of a quiet period arms one timer an interval long (after_unique(), keyed by the holder and the hook), every trigger inside
// the window is absorbed by that timer, and when it fires the parts after coalesce() run once. A trigger after the run arms the next window, so
// sustained triggers give one run per interval. Nothing is scheduled while nothing triggers.
//
// `interval` is deciseconds of the holder's clock, or a PROC_REF of a holder proc x(datum/act/A) answering them, asked when the window opens.
// The window is cancelled with the holder (the timer's owner) and with the hook's activation: a revoked capability's pending run never happens.
//
// The run's context is a fresh /datum/act/notice: A.holder is the holder, A.target the holder (a pooled notice from the trigger is gone by then, so
// its typed fields are not available: read the state the trigger changed, not the trigger).

/// coalesce(interval): the part. The interval is a positive number of deciseconds or a PROC_REF.
/proc/coalesce(interval)
	if(!(istext(interval) && length(interval)) && (!isnum(interval) || interval <= 0))
		declare_report("coalesce(): the interval must be a positive number of deciseconds or a PROC_REF, got [isnull(interval) ? "null" : "[interval]"]")
		return null
	return entry_make(ENTRY_COALESCE, null, list("interval" = interval))

/datum/hook
	/// TRUE once the activation that brought the hook ended (hooks_detach / the on_change remove): a coalesced run still pending for it never happens.
	var/detached = FALSE

/// How many coalesce windows opened, and how many triggers one absorbed (what a test and the trace read).
GLOBAL_VAR_INIT(coalesce_windows, 0)
GLOBAL_VAR_INIT(coalesce_absorbed, 0)
GLOBAL_VAR_INIT(coalesce_runs, 0)

/// Logs one line of the forms trace (GLOB.forms_trace).
/proc/forms_trace(channel, message)
	if(GLOB.forms_trace)
		log_world("FORMS/[channel]: [message]")

/// A trigger reached a coalesce() part of hook H: open the window, or note that one is open. Called from hook_run_parts().
/proc/coalesce_trigger(datum/hook/H, datum/act/A, datum/entry/part)
	if(!H || (H.kind != HOOK_NOTICE && H.kind != HOOK_CHANGE))
		declare_report("coalesce() belongs in an on_notice() or on_change() entry, not in [H ? H.kind : "an every() or a timer"]")
		return
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder) || H.detached)
		return
	if(coalesce_pending(holder, H))
		GLOB.coalesce_absorbed++
		forms_trace("coalesce", "trigger on [holder.type] absorbed by the open window of hook [H.serial]")
		return
	var/interval = every_interval(holder, part, H.activation)
	after_unique(holder, interval, TYPE_PROC_REF(/datum, coalesce_window_fire), list(H))
	GLOB.coalesce_windows++
	forms_trace("coalesce", "window opened on [holder.type] for hook [H.serial]: [interval] ds")

/// TRUE while a window of hook H is open on holder.
/proc/coalesce_pending(datum/holder, datum/hook/H)
	return after_unique_pending(holder, TYPE_PROC_REF(/datum, coalesce_window_fire), list(H))

/// The window of hook H on holder is cancelled (its activation ended): the pending run never happens.
/proc/coalesce_cancel(datum/holder, datum/hook/H)
	H.detached = TRUE
	if(holder && cancel_after_unique(holder, TYPE_PROC_REF(/datum, coalesce_window_fire), list(H)))
		forms_trace("coalesce", "window of hook [H.serial] on [holder.type] cancelled with its activation")

/// The parts of a hook's entry after its coalesce() part.
/proc/coalesce_rest(list/parts)
	. = list()
	var/seen = FALSE
	for(var/datum/entry/part in parts)
		if(seen)
			. += part
		else if(part.kind == ENTRY_COALESCE)
			seen = TRUE

/// The window closed: one run of the parts after coalesce().
/datum/proc/coalesce_window_fire(datum/hook/H)
	coalesce_fire(src, H)

/proc/coalesce_fire(datum/holder, datum/hook/H)
	if(!holder || QDELETED(holder) || !H || H.detached)
		return
	if(H.activation && (H.activation.dead || !H.activation.runs))
		return
	var/list/rest = coalesce_rest(H.entry.children)
	if(!length(rest))
		return
	var/datum/act/notice/N = take(/datum/act/notice)
	N.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	N.target = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	N.outcome = ACT_COMMITTED
	hook_context(N, H)
	GLOB.coalesce_runs++
	forms_trace("coalesce", "run on [holder.type] for hook [H.serial]")
	var/depth = GLOB.act_depth
	GLOB.act_chain += "coalesce:[holder.type]"
	try
		hook_run_parts(H, N, rest)
	catch(var/exception/fault)
		dq_report_caught(fault, "coalesced hook on [holder.type]")
	GLOB.act_depth = depth
	GLOB.act_chain.len--
	N.release()
