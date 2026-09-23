// Per-atom observer-event listener list. Component-backed, sparse.
// Global helpers (not /atom methods) to avoid bloating proc-tables of every /atom subtype.
/datum/component/observer_events
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/list/events

/datum/component/observer_events/Initialize()
	. = ..()
	events = list()

/datum/component/observer_events/Destroy(force)
	if(events)
		for(var/list/listeners in events)
			listeners.Cut()
		events = null
	return ..()

/proc/dq_get_listener_list_from_event(atom/a, observer_event)
	if(!a || QDELING(a))
		return list()
	var/datum/component/observer_events/c = a.GetComponent(/datum/component/observer_events)
	if(!c)
		c = a.AddComponent(/datum/component/observer_events)
		if(!c)
			return list()
	var/list/listeners = c.events[observer_event]
	if(!listeners)
		listeners = list()
		c.events[observer_event] = listeners
	return listeners

/// Read-only variant for hot paths that must not allocate a component when
/// none exists yet (e.g. /atom/Destroy()). Returns null when there's no
/// observer-events component attached.
/proc/dq_peek_listener_list_from_event(atom/a, observer_event)
	if(!a)
		return null
	var/datum/component/observer_events/c = a.GetComponent(/datum/component/observer_events)
	if(!c)
		return null
	return c.events[observer_event]
