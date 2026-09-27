/** Owned scheduling entries for the object model. The reactor remains the only clock. */
/datum/object_model/schedule_entry
	var/datum/entity
	var/datum/handler
	var/key
	var/token
	var/period = 0
	var/random_mean = 0
	var/pending_reason
	var/kind
	var/callback_proc
	var/proc_keyed = FALSE

/datum/object_model/schedule_entry/proc/unkey()
	if(!proc_keyed || !entity || !callback_proc)
		return
	var/datum/object_model/state/state = entity.om_state
	if(state?.proc_timers && state.proc_timers[callback_proc] == src)
		state.proc_timers -= callback_proc
		if(!length(state.proc_timers))
			state.proc_timers = null

/datum/object_model/schedule_entry/proc/start(datum/new_entity, datum/new_handler, new_key, delay, new_kind, new_period = 0)
	if(!new_entity || QDELETED(new_entity) || !new_handler || QDELETED(new_handler))
		return FALSE
	entity = new_entity
	handler = new_handler
	key = new_key
	kind = new_kind
	period = new_period
	if(!om_claim(entity, "om:schedule", src))
		return FALSE
	RegisterSignal(entity, COMSIG_QDELETING, PROC_REF(on_participant_deleting))
	if(handler != entity)
		RegisterSignal(handler, COMSIG_QDELETING, PROC_REF(on_participant_deleting))
	if(kind == "periodic" || kind == "callback_periodic")
		token = REACT_EVERY(src, period, "object model periodic behaviour")
	else
		token = REACT_AT(src, world.time + delay)
	return TRUE

/datum/object_model/schedule_entry/proc/on_participant_deleting(datum/source)
	SIGNAL_HANDLER
	qdel(src)

/datum/object_model/schedule_entry/on_react(reason, source, source_kind)
	if(!(reason & REACT_REASON_TIMER) || !entity || QDELETED(entity) || !handler || QDELETED(handler))
		return
	if(kind == "wake")
		handler.om_on_wake(entity, pending_reason)
	else if(kind == "callback")
		unkey()
		call(handler, callback_proc)()
	else
		handler.om_on_timer(entity, key)
	if(kind == "random" && !QDELETED(src))
		token = REACT_AT(src, world.time + om_random_delay(random_mean))
	else if(kind != "callback_periodic")
		qdel(src)

/datum/object_model/schedule_entry/react_every(seconds, react_token)
	if(!entity || QDELETED(entity) || !handler || QDELETED(handler))
		qdel(src)
		return
	if(kind == "callback_periodic")
		call(handler, callback_proc)(seconds)
	else
		handler.om_on_periodic(entity, seconds)

/datum/object_model/schedule_entry/Destroy(force = FALSE)
	unkey()
	if(kind == "wake" && entity && entity.om_state?.pending_wakes)
		var/list/wakes = entity.om_state.pending_wakes
		if(wakes[handler] == src)
			wakes -= handler
			if(!length(wakes))
				entity.om_state.pending_wakes = null
	if(entity && !QDELETED(entity))
		UnregisterSignal(entity, COMSIG_QDELETING)
	if(handler && handler != entity && !QDELETED(handler))
		UnregisterSignal(handler, COMSIG_QDELETING)
	entity = null
	handler = null
	pending_reason = null
	key = null
	callback_proc = null
	return ..()

/// Compatibility entry for /atom/movable/expire(). It is owned by the atom,
/// so deletion and rearming cancel the timer through the same lifetime tree.
/datum/object_model/schedule_entry/lifetime_expiry/on_react(reason, source, source_kind)
	if(!(reason & REACT_REASON_TIMER))
		return
	var/atom/movable/expiring = entity
	if(expiring && !QDELETED(expiring))
		qdel(expiring)
	if(!QDELETED(src))
		qdel(src)

/datum/object_model/schedule_entry/lifetime_expiry/Destroy(force = FALSE)
	var/atom/movable/expiring = entity
	if(expiring && expiring.lifecycle_lifetime_timer == src)
		expiring.lifecycle_lifetime_timer = null
	return ..()

/datum/proc/om_on_timer(datum/entity, key)
	return

/datum/proc/om_on_wake(datum/entity, reason)
	return

/datum/proc/om_on_periodic(datum/entity, seconds)
	return

/// Owned, cancellable proc timers. PROC_REF keeps the callback checked by the DM compiler.
/datum/proc/After(delay, callback_proc)
	if(!isnum(delay) || delay < 0 || !callback_proc)
		return null
	var/datum/object_model/schedule_entry/entry = new
	entry.callback_proc = callback_proc
	if(!entry.start(src, src, null, delay, "callback"))
		qdel(entry)
		return null
	return entry

/// Ensure at most one pending one-shot call for this owner and proc. Repeated calls
/// preserve the original deadline; use ReplaceAfter to move it.
/datum/proc/EnsureAfter(delay, callback_proc)
	if(!isnum(delay) || delay < 0 || !callback_proc || QDELETED(src))
		return null
	var/datum/object_model/state/state = om_state_for(src)
	var/datum/object_model/schedule_entry/pending = state.proc_timers?[callback_proc]
	if(pending && !QDELETED(pending))
		return pending
	var/datum/object_model/schedule_entry/entry = After(delay, callback_proc)
	if(!entry)
		return null
	entry.proc_keyed = TRUE
	if(!state.proc_timers)
		state.proc_timers = list()
	state.proc_timers[callback_proc] = entry
	return entry

/// Replace the pending deadline for this proc, or schedule it if absent.
/datum/proc/ReplaceAfter(delay, callback_proc)
	if(!isnum(delay) || delay < 0 || !callback_proc || QDELETED(src))
		return null
	CancelAfter(callback_proc)
	return EnsureAfter(delay, callback_proc)

/// Cancel only the keyed one-shot call for this proc; independent After calls survive.
/datum/proc/CancelAfter(callback_proc)
	if(!callback_proc)
		return FALSE
	var/datum/object_model/schedule_entry/pending = om_state?.proc_timers?[callback_proc]
	if(!pending)
		return FALSE
	qdel(pending)
	return TRUE

/datum/proc/PendingAfter(callback_proc)
	var/datum/object_model/schedule_entry/pending = om_state?.proc_timers?[callback_proc]
	return pending && !QDELETED(pending) ? pending : null

/datum/proc/Every(period, callback_proc)
	if(!isnum(period) || period <= 0 || !callback_proc)
		return null
	var/datum/object_model/schedule_entry/entry = new
	entry.callback_proc = callback_proc
	if(!entry.start(src, src, null, 0, "callback_periodic", period))
		qdel(entry)
		return null
	return entry

/// Returns an entry that can be qdel'd to cancel. Destruction of either endpoint also cancels it.
/proc/om_timer(datum/entity, delay, datum/handler, key)
	if(!isnum(delay) || delay < 0)
		return null
	var/datum/object_model/schedule_entry/entry = new
	if(!entry.start(entity, handler, key, delay, "timer"))
		qdel(entry)
		return null
	return entry

/// Poisson intervals have the requested mean in deciseconds.
/proc/om_timer_random(datum/entity, mean, datum/handler, key)
	if(!isnum(mean) || mean <= 0)
		return null
	var/datum/object_model/schedule_entry/entry = new
	entry.random_mean = mean
	if(!entry.start(entity, handler, key, om_random_delay(mean), "random"))
		qdel(entry)
		return null
	return entry

/proc/om_random_delay(mean)
	return max(world.tick_lag, -mean * log(max(0.000001, rand(1, 1000000) / 1000000)))

/// A pending wake per owner and handler is coalesced by this entry's reactor subscriber.
/proc/om_wake(datum/entity, datum/handler, reason)
	if(!entity || QDELETED(entity) || !handler || QDELETED(handler))
		return null
	var/datum/object_model/state/state = om_state_for(entity)
	if(!state.pending_wakes)
		state.pending_wakes = list()
	var/datum/object_model/schedule_entry/pending = state.pending_wakes[handler]
	if(pending && !QDELETED(pending))
		if(!islist(pending.pending_reason))
			pending.pending_reason = list(pending.pending_reason)
		var/list/reasons = pending.pending_reason
		if(!(reason in reasons))
			reasons += reason
		return pending
	var/datum/object_model/schedule_entry/entry = new
	entry.pending_reason = reason
	if(!entry.start(entity, handler, null, 0, "wake"))
		qdel(entry)
		return null
	state.pending_wakes[handler] = entry
	return entry

/proc/om_periodic(datum/entity, period, datum/handler)
	if(!isnum(period) || period <= 0)
		return null
	var/datum/object_model/schedule_entry/entry = new
	if(!entry.start(entity, handler, null, 0, "periodic", period))
		qdel(entry)
		return null
	return entry
