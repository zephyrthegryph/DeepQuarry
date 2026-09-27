// Event definitions dispatch to static archetype tables. Subtypes override
// deliver() for typed hooks; the default goes through behaviour.on_event().
#define OM_EVENT_AFTER 0
#define OM_EVENT_BEFORE 1
#define OM_EVENT_IMMEDIATE 0
#define OM_EVENT_DEFERRED_COALESCED 1

/datum/object_model/event
	var/phase = OM_EVENT_AFTER
	var/delivery = OM_EVENT_IMMEDIATE
	var/bubbles = FALSE

/datum/object_model/event/proc/deliver(datum/object_model/behaviour/B, datum/source, a, b, c, d, list/config)
	return B.on_event(source, src, a, b, c, d, config)

/proc/om_event(path)
	if(!ispath(path, /datum/object_model/event))
		return null
	var/static/list/cache = list()
	var/datum/object_model/event/E = cache[path]
	if(!E)
		E = new path
		cache[path] = E
	return E

/// The first non-null BEFORE result vetoes; AFTER results are ignored.
/// Four payload arguments cover the common event forms without allocating a
/// list on the emit path. More involved events can pass one context datum.
/proc/om_emit(datum/source, event_path, a, b, c, d)
	if(!source)
		return null
	var/datum/object_model/event/E = om_event(event_path)
	if(!E)
		CRASH("unknown object-model event [event_path]")
	if(E.delivery == OM_EVENT_DEFERRED_COALESCED)
		return om_queue_event(source, event_path, a, b, c, d)
	om_behaviour_refresh(source, event_path)
	return om_deliver_event(source, E, a, b, c, d)

/proc/om_deliver_event(datum/source, datum/object_model/event/E, a, b, c, d)
	var/static/list/active = list()
	var/static/depth = 0
	var/key = "[REF(source)]|[E.type]"
	if(active[key] || depth >= 32)
		return null
	active[key] = TRUE
	depth++
	var/datum/object_model/archetype/A = om_archetype_for(source.type, source)
	var/result
	if(A && om_required_relations_ready(source, A))
		for(var/path in A.event_handlers[E.type])
			var/datum/object_model/behaviour/B = om_behaviour(path)
			var/datum/object_model/behaviour_runtime/R = source.om_state?.behaviour_runtime
			if(R ? !R.active[path] : !A.behaviour_ready(source, B))
				continue
			result = E.deliver(B, source, a, b, c, d, A.behaviours[path])
			if(E.phase == OM_EVENT_BEFORE && !isnull(result))
				break
	if(A && om_required_relations_ready(source, A) && (isnull(result) || E.phase != OM_EVENT_BEFORE))
		var/datum/object_model/behaviour_runtime/runtime = source.om_state?.behaviour_runtime
		if(runtime)
			for(var/path in runtime.grants)
				if(path in A.behaviours || !runtime.active[path])
					continue
				var/datum/object_model/behaviour/B = om_behaviour(path)
				if(!B.events || !(E.type in B.events))
					continue
				result = E.deliver(B, source, a, b, c, d, runtime.config_for(path))
				if(E.phase == OM_EVENT_BEFORE && !isnull(result))
					break
	if(isnull(result) || E.phase != OM_EVENT_BEFORE)
		var/subscription_result = om_deliver_subscriptions(source, E, a, b, c, d)
		if(E.phase == OM_EVENT_BEFORE && !isnull(subscription_result))
			result = subscription_result
	depth--
	active -= key
	if(!QDELETED(source) && (E.phase != OM_EVENT_BEFORE || isnull(result)))
		om_behaviour_wake_event(source, E.type, A)
	if(E.bubbles && (E.phase != OM_EVENT_BEFORE || isnull(result)))
		var/datum/owner = om_owner(source)
		if(owner)
			var/parent_result = om_deliver_event(owner, E, a, b, c, d)
			if(E.phase == OM_EVENT_BEFORE && !isnull(parent_result))
				return parent_result
	return E.phase == OM_EVENT_BEFORE ? result : null

/// Last payload wins when the same source emits this event again in one tick.
/proc/om_queue_event(datum/source, event_path, a, b, c, d)
	var/static/list/pending = list()
	var/key = "[REF(source)]|[event_path]"
	var/datum/object_model/event_pending/P = pending[key]
	if(!P)
		P = new
		P.source = source
		P.event_path = event_path
		P.key = key
		P.pending = pending
		pending[key] = P
		addtimer(CALLBACK(P, TYPE_PROC_REF(/datum/object_model/event_pending, fire)), 0)
	P.a = a
	P.b = b
	P.c = c
	P.d = d
	return null

/datum/object_model/event_pending
	var/datum/source
	var/event_path
	var/key
	var/list/pending
	var/a
	var/b
	var/c
	var/d

/datum/object_model/event_pending/proc/fire()
	SHOULD_NOT_SLEEP(TRUE)
	if(pending)
		pending -= key
	if(source && !QDELETED(source))
		om_behaviour_refresh(source, event_path)
		om_deliver_event(source, om_event(event_path), a, b, c, d)
	source = null
	pending = null
	qdel(src)

/datum/object_model/event_pending/Destroy(force = FALSE)
	source = null
	pending = null
	return ..()
