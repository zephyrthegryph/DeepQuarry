// Per-atom observer-event listener lists: one lazy tmp assoc list on /atom
// (observer event -> list of listeners). An unset var costs an instance nothing.
// Global helpers (not /atom methods) to avoid bloating proc-tables of every /atom subtype.
//
// An atom whose list exists refuses serialization (/atom/state_refusal()).

/atom
	/// observer event -> list of listeners. Null until something asks for a listener list.
	var/tmp/list/observer_event_listeners

/proc/dq_get_listener_list_from_event(atom/a, observer_event)
	if(!a || QDELING(a))
		return list()
	if(!a.observer_event_listeners)
		a.observer_event_listeners = list()
	var/list/listeners = a.observer_event_listeners[observer_event]
	if(!listeners)
		listeners = list()
		a.observer_event_listeners[observer_event] = listeners
	return listeners

/// Read-only variant for hot paths that must not allocate storage when none
/// exists yet (e.g. /atom/Destroy()). Returns null when nothing is stored.
/proc/dq_peek_listener_list_from_event(atom/a, observer_event)
	if(!a || !a.observer_event_listeners)
		return null
	return a.observer_event_listeners[observer_event]
