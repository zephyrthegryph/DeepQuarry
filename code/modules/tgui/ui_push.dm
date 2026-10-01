// Coalesced UI pushes (doc/rewrite/operations_and_actions.md "UI"; G14 of the framework gap plan).
//
// What an open window shows is its host's tgui_data(). When state it reads changes, the framework pushes it: a
// tracked write marks the host (changed() / publish_change() -> the refresh engine's DEP_UI output, from the
// generated ui_from() reads of its tgui_data() body, or a declared ui_from()), and refresh_ui() queues each of the
// host's open windows here. The queue is drained once per tick in the kernel's phase R, after the lanes (so after
// the presentation lane's refresh drain has marked everything this tick changed): each window gets at most ONE data
// push per tick however many of its reads changed, with its status re-checked first.
//
// So inside a converted type (its window data comes from tgui_data() and the vars it reads are tracked), a
// `SStgui.update_uis(src)` after a state change is redundant: delete it. An act_<x>() handler that returns TRUE
// updates the acting window already (tgui_act()). SStgui.update_uis() itself is unchanged for legacy callers (it
// re-runs the declared UI's refresh through the OM push behaviour).
//
// Tests and admin tools: refresh_flush() drains this queue too (ui_push_flush()).

SYSTEM_DEF(ui_push)
	name = "UI Push"
	wait = 1
	/// Windows waiting for their push this tick (window -> TRUE), or null when none is.
	var/list/pending

/datum/system/ui_push/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(push_step), when = nameof(pending), phase = KERNEL_PHASE_R, lane = LANE_PRESENTATION)

/// The phase R step: one push per pending window.
/datum/system/ui_push/proc/push_step(dt)
	ui_push_flush()

/// Queues a coalesced push of every open window of `host` (delivered in phase R). Returns how many were queued.
/proc/ui_push_mark(datum/host)
	. = 0
	if(!LAZYLEN(host?.open_tguis))
		return
	var/datum/system/ui_push/S = SSui_push
	if(!S)
		// Before the systems exist (early boot): push now, as the refresh engine used to.
		SStgui.update_uis(host)
		return
	for(var/datum/tgui/ui as anything in host.open_tguis)
		LAZYSET(S.pending, ui, TRUE)
		.++

/// Delivers every queued push now (the phase R step; refresh_flush() for tests and admin tools).
/proc/ui_push_flush()
	var/datum/system/ui_push/S = SSui_push
	var/list/batch = S?.pending
	if(!batch)
		return 0
	S.pending = null // a push that marks another window queues it for the next pass
	. = 0
	for(var/datum/tgui/ui as anything in batch)
		if(ui.push_coalesced())
			.++

/// One coalesced data push: the status is re-checked (a window whose host or user went away closes), then the data is
/// sent. tgui_data() runs inside it, as an output: it must not write state. TRUE when data went out.
/datum/tgui/proc/push_coalesced()
	if(closing || QDELETED(src))
		return FALSE
	var/datum/host = src_object()
	if(QDELETED(host) || QDELETED(user))
		return FALSE
	if(process_status() && status <= STATUS_CLOSE)
		close()
		return FALSE
	GLOB.ui_push_count++
	DERIVED_EVAL_BEGIN
	send_update()
	DERIVED_EVAL_END
	return TRUE

/// Coalesced pushes delivered since boot (tests read it).
GLOBAL_VAR_INIT(ui_push_count, 0)
