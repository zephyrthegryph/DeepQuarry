// Coalesced UI pushes (doc/rewrite/final_api.html section 7 "outputs, reads, phase R" and section 13 "ui_data(A)"; G14 of the framework gap plan).
//
// What an open window shows is its host's ui_data(A) (tgui_data() merges it). When state it reads changes, the framework pushes it: a
// tracked write marks the host (changed() / publish_change() -> the refresh engine's DEP_UI output, from the generated ui_from() reads of its
// ui_data() body, or a declared ui_from()), and refresh_ui() queues each of the host's open windows here. The queue is drained once per tick
// in the kernel's phase R, after the lanes (so after the presentation lane's refresh drain has marked everything this tick changed): each
// window gets at most ONE push per tick however many of its reads changed, with its status re-checked first.
//
// A window's STATUS (interactive, update-only, closed) is the same: it is re-checked in phase R when something that decides it published a
// key (code/modules/tgui/ui_status.dm: the user's or the host's location, the user's stat, can-act stat, hands, equipment, conditions and
// client), or when a participant is deleted. A queued window carries what it is owed: its data (UI_PUSH_DATA), a re-run of the host's
// interact (UI_PUSH_INTERACT, an update_uis() request) or a status re-check only (UI_PUSH_STATUS).
//
// So inside a converted type (its window data comes from ui_data() and the vars it reads are tracked), a `SStgui.update_uis(src)` after a
// state change is redundant: delete it. A ui_act op handler that returns TRUE updates the acting window already (on_act_message()).
// SStgui.update_uis() itself stays for legacy callers; it queues here too.
//
// Tests and admin tools: refresh_flush() drains this queue too (ui_push_flush()).

SYSTEM_DEF(ui_push)
	name = "UI Push"
	wait = 1
	/// Windows waiting for their push this tick (window -> UI_PUSH_* bits), or null when none is.
	var/list/pending

/datum/system/ui_push/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(push_step), when = nameof(pending), phase = KERNEL_PHASE_R, lane = LANE_PRESENTATION)

/// The phase R step: one push per pending window.
/datum/system/ui_push/proc/push_step(dt)
	ui_push_flush()

/// Queues `ui` for the `owed` (UI_PUSH_* bits) work in phase R. Returns TRUE when the window was not queued yet.
/proc/ui_push_queue(datum/tgui/ui, owed = UI_PUSH_DATA)
	var/datum/system/ui_push/S = SSui_push
	if(!S)
		return FALSE
	. = !(ui in S.pending)
	LAZYSET(S.pending, ui, (S.pending?[ui] || 0) | owed) // ALLOW(ownership): the UI push system's pending set, written and drained only by this system

/// The datum whose windows an answer to a question this datum asked can change: itself, and for a window its host (a handler on /datum/tgui).
/datum/proc/ui_push_host()
	return src

/// An answered question can change what the asker's windows show: they are pushed once, in phase R.
/datum/request_answered(datum/request/R)
	ui_push_mark(ui_push_host())

/datum/tgui/ui_push_host()
	return src_object()

/// Queues a coalesced push of every open window of `host` (delivered in phase R). Returns how many were queued.
/proc/ui_push_mark(datum/host)
	. = 0
	if(!LAZYLEN(host?.open_tguis))
		return
	if(!SSui_push)
		return // before the systems exist (early boot) nothing is open
	for(var/datum/tgui/ui as anything in host.open_tguis)
		ui_push_queue(ui, UI_PUSH_DATA)
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
		if(ui.push_coalesced(batch[ui]))
			.++

/// One coalesced delivery: the status is re-checked (a window whose host or user went away closes), then what the window is owed goes out.
/// A data push runs ui_data() inside it, as an output: it must not write state. TRUE when data went out (or the interact re-ran).
/datum/tgui/proc/push_coalesced(owed = UI_PUSH_DATA)
	if(closing || QDELETED(src))
		return FALSE
	if((owed & UI_PUSH_STATUS) && !ui_participants_alive())
		return FALSE // an end of the window is gone: it closed (or followed its client)
	var/datum/host = src_object()
	if(QDELETED(host) || QDELETED(user))
		return FALSE
	if(owed & UI_PUSH_INTERACT)
		// An update_uis() request: re-run the host's interact, as the old inline push did.
		process(TRUE)
		return TRUE
	var/was = status
	if(process_status() && status <= STATUS_CLOSE)
		log_tgui(user, "status [was] -> [status]: closing", context = "ui_push/push_coalesced")
		close()
		return FALSE
	if(owed & UI_PUSH_DATA)
		GLOB.ui_push_count++
		DERIVED_EVAL_BEGIN
		send_update()
		DERIVED_EVAL_END
		return TRUE
	if(status != was)
		log_tgui(user, "status [was] -> [status]", context = "ui_push/push_coalesced")
		send_status_update()
	return FALSE

/// Coalesced pushes delivered since boot (tests read it).
GLOBAL_VAR_INIT(ui_push_count, 0)
