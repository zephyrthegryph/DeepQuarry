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
// so it can be vetoed; emitting one on an entity that is already delivering
// a before_* event is an error, reported loudly and answered with a veto,
// never silently dropped.

/proc/om_emit(datum/E, datum/om/event/event)
	var/datum/om/rec/rec = E?.om_rec
	if(!rec || rec.torn_down)
		return null
	var/datum/om/scheduler/sched = rec.sched
	event.entity = E
	if(sched.bulk_depth && event.skip_in_bulk)
		return null
	if(event.before)
		if(rec.in_veto)
			sched.error("re-entrant [event.type] on [E]: vetoed")
			return EVENT_VETO
		rec.in_veto = TRUE
		. = null
		try
			. = om_deliver(rec, event, TRUE)
		catch(var/exception/e1)
			sched.error("[event.type]: [e1]")
		rec.in_veto = FALSE
		return
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
		sched.error("[event.type]: [e2]")
	while(length(sched.event_queue))
		var/datum/om/rec/next_rec = sched.event_queue[1]
		var/datum/om/event/next = sched.event_queue[2]
		sched.event_queue.Cut(1, 3)
		if(next_rec.torn_down)
			continue
		try
			om_deliver(next_rec, next, FALSE)
		catch(var/exception/e3)
			sched.error("[next.type]: [e3]")
	sched.emit_depth = 0
	return null

/proc/om_deliver(datum/om/rec/rec, datum/om/event/event, veto)
	var/datum/om/registry/reg = om_registry()
	var/e = reg.event_idx[event.type]
	var/list/flags = e ? reg.event_handlers[e] : null
	var/datum/E = rec.owner
	if(flags)
		for(var/i in 1 to length(rec.att))
			var/datum/om/behaviour/B = rec.att[i]
			if(!flags[B.id] || !(rec.att_state[i] & OM_ATT_STARTED))
				continue
			var/result = event.dispatch(B, E)
			if(veto && result == EVENT_VETO)
				return EVENT_VETO
			if(rec.torn_down)
				return null
	if(rec.tasks)
		for(var/datum/om/task/T as anything in rec.tasks.Copy())
			for(var/path in T.def.interrupted_by)
				if(istype(event, path))
					om_task_cancel(T, "interrupted")
					break
	return null
