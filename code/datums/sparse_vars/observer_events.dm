// Per-atom observer-event listener lists: one lazy tmp assoc list on /atom
// (observer event -> list of listeners), a sparse slot.
// Global helpers (not /atom methods) to avoid bloating proc-tables of every /atom subtype.
//
// An atom whose list exists refuses serialization (/atom/state_refusal()).

/// observer event -> list of listeners. Unset until something asks for a listener list.
sparse(/atom, observer_listeners, type = list)

/proc/dq_get_listener_list_from_event(atom/a, observer_event)
	if(!a || QDELING(a))
		return list()
	var/list/by_event = sparse_get(a, observer_listeners)
	if(!by_event)
		by_event = sparse_set(a, observer_listeners, list())
	var/list/listeners = by_event[observer_event]
	if(!listeners)
		listeners = list()
		by_event[observer_event] = listeners
	return listeners

/// Read-only variant for hot paths that must not allocate storage when none
/// exists yet (e.g. /atom/Destroy()). Returns null when nothing is stored.
/proc/dq_peek_listener_list_from_event(atom/a, observer_event)
	var/list/by_event = sparse_get(a, observer_listeners)
	return by_event?[observer_event]
