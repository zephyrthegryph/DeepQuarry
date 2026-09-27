// Opt-in bridge for legacy COMSIG producers. The signal keeps its return-bit
// semantics, while object-model observers receive the matching typed event.
/datum/object_model/signal_bridge
	var/datum/source
	var/signal_name
	var/event_path

/datum/object_model/signal_bridge/proc/on_signal(datum/sender, a, b, c, d)
	SIGNAL_HANDLER
	if(sender == source && !om_is_dying(sender))
		om_emit(sender, event_path, a, b, c, d)
	return NONE

/datum/object_model/signal_bridge/Destroy(force = FALSE)
	if(source && !QDELETED(source))
		UnregisterSignal(source, signal_name)
	source = null
	signal_name = null
	event_path = null
	return ..()

/// Installs at most one bridge for this source, signal, and typed event.
/// The source owns its bridge, so ordinary qdel removes the registration.
/proc/om_bridge_signal(datum/source, signal_name, event_path)
	if(!source || om_is_dying(source) || !istext(signal_name) || !om_event(event_path))
		return null
	for(var/datum/object_model/signal_bridge/existing as anything in om_children(source, "om:signal_bridges"))
		if(existing.signal_name == signal_name && existing.event_path == event_path)
			return existing
	var/datum/object_model/signal_bridge/B = new
	B.source = source
	B.signal_name = signal_name
	B.event_path = event_path
	if(!om_claim(source, "om:signal_bridges", B))
		qdel(B)
		return null
	B.RegisterSignal(source, signal_name, TYPE_PROC_REF(/datum/object_model/signal_bridge, on_signal))
	return B
