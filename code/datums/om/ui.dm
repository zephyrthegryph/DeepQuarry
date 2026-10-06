// Object-model core: UI binding (doc/rewrite/object_model_core.md section J),
// Rust-owned watches (A.6) and dt helpers (K).

/// Minimum deciseconds between two pushes to one session.
#define OM_UI_THROTTLE (2)

/// Binds a UI session to `target`: a watch edge on `mask` that raises the
/// target to RELEVANCE_WATCHED (STAT_RELEVANCE) while bound. Changes are coalesced and pushed
/// at most once per OM_UI_THROTTLE per session via session.om_ui_push().
/proc/om_ui_bind(datum/session, datum/target, mask)
	var/datum/om/behaviour/B = om_registry().ui_behaviour
	om_attach(session, B)
	om_watch(session, target, mask, B)
	hold(target, STAT_RELEVANCE, RELEVANCE_WATCHED, session)

/proc/om_ui_unbind(datum/session, datum/target)
	var/datum/om/behaviour/B = om_registry().ui_behaviour
	om_unwatch(session, target, B)
	release(target, STAT_RELEVANCE, session)
	if(!length(session.om_rec?.watching))
		om_detach(session, B)

/// Binds every ui row of `E`'s decls (target proc, watch mask) for `session`.
/proc/om_ui_bind_table(datum/session, datum/E)
	var/datum/om/rec/rec = om_rec_of(E)
	if(!rec)
		return
	for(var/list/row as anything in rec.table.ui)
		var/datum/target = row["target"] ? call(E, row["target"])() : E
		if(target)
			om_ui_bind(session, target, row["watch"] || CHANGE_GENERIC_MASK)

/// Called on the session when a bound target changed. /datum/tgui pushes an update.
/datum/proc/om_ui_push()
	return

/datum/tgui/om_ui_push()
	if(closing || QDELETED(src))
		return
	if(push_reinteract)
		// An update_uis() request: re-run tgui_interact, as the old inline push did.
		push_reinteract = FALSE
		process(TRUE)
		return
	// A watched change: validate the status, then send data only.
	if(process_status() && status <= STATUS_CLOSE)
		close()
		return
	send_update()

/datum/om/behaviour/internal/ui_push
	name = "om: ui push"
	lane = LANE_PRESENTATION

/datum/om/behaviour/internal/ui_push/on_wake(datum/session, changes)
	var/datum/om/rec/rec = session.om_rec
	var/t = rec.sched.now()
	var/wait = rec.ui_last_push + OM_UI_THROTTLE - t
	if(rec.ui_last_push && wait > 0)
		if(!om_deadline_pending(session, src))
			om_deadline(session, wait, src)
		return
	rec.ui_last_push = t
	session.om_ui_push()

/datum/om/behaviour/internal/ui_push/on_deadline(datum/session)
	var/datum/om/rec/rec = session.om_rec
	rec.ui_last_push = rec.sched.now()
	session.om_ui_push()

// ---- the window's status: event-driven, never polled

/// Minimum deciseconds between two status re-checks of one window (a walking user raises LOC every step).
#define OM_UI_STATUS_THROTTLE (2)

/// What can change a window's status on the USER: moving, hands, worn gear, consciousness, stuns,
/// the client (logout/disconnect), body conditions and movement ability.
#define UI_STATUS_USER_CHANNELS (CHANGE_MOB_LOC | CHANGE_MOB_HANDS | CHANGE_MOB_EQUIPMENT | CHANGE_MOB_STAT | CHANGE_MOB_STATUS | CHANGE_MOB_CLIENT | CHANGE_MOB_CONDITIONS | CHANGE_MOB_CAN_MOVE)

/// The channel that announces a move of a window's host (the physical object `tgui_host()` names).
/proc/om_ui_status_host_mask(datum/host)
	if(ismob(host))
		return CHANGE_MOB_LOC
	if(isitem(host))
		return CHANGE_ITEM_LOC
	if(ismovable(host))
		return CHANGE_EXPLICIT
	return 0

/// Binds window `ui`'s status check to its user and to its host where the host can move. Re-callable (a transfer to
/// another mob): the old user's watch is dropped first.
/proc/om_ui_status_bind(datum/tgui/ui)
	var/mob/user = ui.user
	if(QDELETED(ui) || QDELETED(user))
		return
	var/datum/om/behaviour/B = om_registry().behaviour(/datum/om/behaviour/internal/ui_status)
	om_attach(ui, B)
	for(var/datum/old as anything in ui.om_rec?.watching?.Copy())
		om_unwatch(ui, old, B)
	om_watch(ui, user, UI_STATUS_USER_CHANNELS, B)
	var/datum/owner_obj = ui.src_object()
	var/datum/host = QDELETED(owner_obj) ? null : owner_obj.tgui_host(user)
	if(host && host != user)
		var/mask = om_ui_status_host_mask(host)
		if(mask)
			om_watch(ui, host, mask, B)
	log_tgui(user, "status bound to user[host ? " and host [host]" : ""]", context = "om_ui_status_bind")

/proc/om_ui_status_unbind(datum/tgui/ui)
	var/datum/om/behaviour/B = om_registry().behaviour(/datum/om/behaviour/internal/ui_status)
	for(var/datum/target as anything in ui.om_rec?.watching?.Copy())
		om_unwatch(ui, target, B)
	om_detach(ui, B)

/// Called on the window when something that decides its status changed (or its user/host/window was deleted).
/datum/proc/om_ui_status()
	return

/datum/tgui/om_ui_status()
	if(closing || QDELETED(src))
		return
	if(!ui_participants_alive())
		return
	var/was = status
	if(process_status() && status <= STATUS_CLOSE)
		log_tgui(user, "status [was] -> [status]: closing", context = "om_ui_status")
		close()
		return
	if(status != was)
		log_tgui(user, "status [was] -> [status]", context = "om_ui_status")
		send_status_update()

/datum/om/behaviour/internal/ui_status
	name = "om: ui status"
	lane = LANE_PRESENTATION

/datum/om/behaviour/internal/ui_status/on_wake(datum/session, changes)
	var/datum/om/rec/rec = session.om_rec
	var/t = rec.sched.now()
	var/wait = rec.ui_status_last + OM_UI_STATUS_THROTTLE - t
	if(rec.ui_status_last && wait > 0)
		if(!om_deadline_pending(session, src))
			om_deadline(session, wait, src)
		return
	rec.ui_status_last = t
	session.om_ui_status()

/datum/om/behaviour/internal/ui_status/on_deadline(datum/session)
	var/datum/om/rec/rec = session.om_rec
	rec.ui_status_last = rec.sched.now()
	session.om_ui_status()

#undef OM_UI_STATUS_THROTTLE

#undef OM_UI_THROTTLE

// ---------------------------------------------------------------- native (Rust) watches

// The DM half of Rust-owned watches. A behaviour declares wake_on_native
// bits; when it attaches, om_native_watch() tells the bridge which bits this
// entity needs. The reactor's drain calls om_native_deliver(E, bits) once per
// tick per entity, which runs on_native(E, bits) on each started behaviour
// declaring any of those bits. The bridge procs below are the stub interface:
// the reactor track replaces their bodies with its generated bindings.

/// Stub: register interest in native `bits` for `E` (reactor binding goes here).
/proc/om_native_bridge_watch(datum/E, bits)
	return FALSE

/// Stub: tell the native side `E`'s relevance level (reactor binding goes here).
/proc/om_native_bridge_relevance(datum/E, level)
	return FALSE

/proc/om_native_watch(datum/om/rec/rec)
	var/bits = 0
	for(var/datum/om/behaviour/B as anything in rec.att)
		bits |= B.wake_on_native
	if(bits != rec.native_bits)
		rec.native_bits = bits
		om_native_bridge_watch(rec.owner, bits)

/// Called by the reactor drain.
/proc/om_native_deliver(datum/E, bits)
	var/datum/om/rec/rec = E?.om_rec
	if(!rec || rec.torn_down)
		return
	for(var/i in 1 to length(rec.att))
		var/datum/om/behaviour/B = rec.att[i]
		if((B.wake_on_native & bits) && (rec.att_state[i] & OM_ATT_STARTED))
			rec.sched.call_hook(rec, B, OM_HOOK_NATIVE, B.wake_on_native & bits)

/proc/om_native_relevance(datum/E, level)
	if(E)
		om_native_bridge_relevance(E, level)

// ---------------------------------------------------------------- dt helpers

/// Exponential approach of `x` toward `target` with rate `k` per second over `dt` seconds.
/// Exact for any dt: two half-steps equal one full step.
/proc/approach(x, target, k, dt)
	return target + (x - target) * NUM_E ** (-k * dt)

/// Exponential decay of `x` at `rate` per second over `dt` seconds.
/proc/decay(x, rate, dt)
	return x * NUM_E ** (-rate * dt)

/// TRUE with the probability that an event of `p_per_second` (0-1) happens within `dt` seconds.
/proc/chance_over(p_per_second, dt)
	if(p_per_second <= 0 || dt <= 0)
		return FALSE
	if(p_per_second >= 1)
		return TRUE
	return rand() < 1 - (1 - p_per_second) ** dt

/// Linear move of `x` toward `target` by at most `speed * dt`.
/proc/move_toward(x, target, speed, dt)
	var/delta = speed * dt
	if(abs(target - x) <= delta)
		return target
	return x + (target > x ? delta : -delta)

/proc/clamp01(x)
	return clamp(x, 0, 1)
