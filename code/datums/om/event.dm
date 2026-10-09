// Object-model core: typed events (doc/rewrite/object_model_core.md section G).
//
// om_emit(E, new /datum/om/event/x(...)) delivers to every started behaviour
// on E that handles /datum/om/event/x or any of its ancestors (the boot
// table flattens inheritance, so a subtype event is never missed), in run
// order, by double dispatch: event.dispatch(B, E) calls B.on_x(E, event).
//
// Re-entrancy: an ordinary event emitted while another is being delivered
// is queued (coalesced per entity and type unless coalesce = FALSE) and
// delivered right after, in the same call. A before_* event is synchronous
// so it can be vetoed. The re-entrancy guard is keyed by event type: a
// before_* event may emit a DIFFERENT before_* event on the same entity (a
// before_move asking before_drop), but re-emitting the SAME type while it is
// being delivered, or nesting deeper than OM_VETO_DEPTH_MAX, is an error,
// reported loudly and answered with a veto, never silently dropped.

/// Deepest nesting of distinct before_* events on one entity before the next is vetoed.
#define OM_VETO_DEPTH_MAX 8

/proc/om_emit(datum/E, datum/om/event/event)
	var/datum/om/rec/rec = E?.om_rec
	if(!rec || rec.torn_down)
		return null
	var/datum/om/scheduler/sched = rec.sched
	event.entity = E
	if(sched.bulk_depth && event.skip_in_bulk)
		return null
	if(event.before)
		if(event.accumulate)
			try
				om_deliver(rec, event, FALSE)
			catch(var/exception/e0)
				sched.report_caught(e0, "[event.type]: [e0]")
			return event.result
		var/etype = event.type
		if(rec.in_veto && (etype in rec.in_veto))
			sched.error("re-entrant [etype] on [E]: vetoed")
			return EVENT_VETO
		if(length(rec.in_veto) >= OM_VETO_DEPTH_MAX)
			sched.error("before-event nesting deeper than [OM_VETO_DEPTH_MAX] on [E] ([etype] inside [jointext(rec.in_veto, ", ")]): vetoed")
			return EVENT_VETO
		LAZYADD(rec.in_veto, etype)
		. = null
		try
			. = om_deliver(rec, event, TRUE)
		catch(var/exception/e1)
			sched.report_caught(e1, "[etype]: [e1]")
		// Remove the innermost occurrence only (the list is a stack).
		if(rec.in_veto)
			var/at = length(rec.in_veto)
			while(at && rec.in_veto[at] != etype)
				at--
			if(at)
				rec.in_veto.Cut(at, at + 1)
			if(!length(rec.in_veto))
				rec.in_veto = null
		return
	if(event.sync)
		try
			om_deliver(rec, event, FALSE)
		catch(var/exception/e4)
			sched.report_caught(e4, "[event.type]: [e4]")
		return event.result
	if(sched.emit_depth)
		if(event.coalesce)
			var/list/Q = sched.event_queue
			for(var/i in 1 to length(Q) step 2)
				var/datum/om/event/queued = Q[i + 1]
				if(Q[i] == rec && queued.type == event.type)
					Q[i + 1] = event
					return null
		sched.event_queue += list(rec, event)
		return null
	sched.emit_depth = 1
	try
		om_deliver(rec, event, FALSE)
	catch(var/exception/e2)
		sched.report_caught(e2, "[event.type]: [e2]")
	while(length(sched.event_queue))
		var/datum/om/rec/next_rec = sched.event_queue[1]
		var/datum/om/event/next = sched.event_queue[2]
		sched.event_queue.Cut(1, 3)
		if(next_rec.torn_down)
			continue
		try
			om_deliver(next_rec, next, FALSE)
		catch(var/exception/e3)
			sched.report_caught(e3, "[next.type]: [e3]")
	sched.emit_depth = 0
	return null

/proc/om_deliver(datum/om/rec/rec, datum/om/event/event, veto)
	var/datum/om/registry/reg = definition_registry()
	var/etype = event.type
	var/e = reg.event_idx[etype]
	var/list/flags = e ? reg.event_handlers[e] : null
	var/datum/E = rec.owner
	if(rec.table.cache_events)
		om_cache_clear(E, rec.table.cache_events, etype)
	if(flags)
		// A handler may attach or detach behaviours: snapshot att_ver and re-find
		// the behaviour just run when it changes (as scheduler run_wakes() does).
		var/i = 1
		while(i <= length(rec.att))
			var/datum/om/behaviour/B = rec.att[i]
			if(!flags[B.id] || !(rec.att_state[i] & OM_ATT_STARTED))
				i++
				continue
			var/ver = rec.att_ver
			var/result = event.dispatch(B, E)
			if(isnum(result) && result)
				event.result |= result
				if(veto && result == EVENT_VETO)
					return EVENT_VETO
			if(rec.torn_down)
				return null
			if(rec.att_ver != ver)
				var/at = rec.att.Find(B)
				i = (at ? at : i - 1) + 1
			else
				i++
	return null


