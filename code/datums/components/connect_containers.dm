/// This component behaves similar to connect_loc_behalf, but it's nested and hooks a signal onto all MOVABLES containing this atom.
/datum/component/connect_containers
	dupe_mode = COMPONENT_DUPE_SELECTIVE

	/// An assoc list of signal -> procpath to register to the loc this object is on.
	var/list/connections
	/**
	 * The atom the component is tracking. The component will delete itself if the tracked is deleted.
	 * Signals will also be updated whenever it moves.
	 */
	var/atom/movable/tracked

/datum/component/connect_containers/Initialize(atom/movable/tracked, list/connections)
	. = ..()
	if (!ismovable(tracked))
		return COMPONENT_INCOMPATIBLE

	src.connections = connections
	set_tracked(tracked)

/datum/component/connect_containers/Destroy()
	set_tracked(null)
	return ..()

/datum/component/connect_containers/CheckDupeComponent(datum/component/connect_containers/new_component, atom/movable/tracked, list/connections)
	// Not equivalent. Checks if they are not the same list via shallow comparison.
	if(!compare_list(src.connections, connections))
		return FALSE // Different set of connections.
	if(src.tracked != tracked)
		set_tracked(tracked) // Different target for the same set of connections, track the new target.
	return TRUE // No new component.

/datum/component/connect_containers/proc/set_tracked(atom/movable/new_tracked)
	if(tracked)
		UnregisterSignal(tracked, COMSIG_QDELETING)
		unregister_signals(tracked)
		ObserveSet(null, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved))
	tracked = new_tracked
	if(!tracked)
		return
	RegisterSignal(tracked, COMSIG_QDELETING, PROC_REF(handle_tracked_qdel))
	update_signals(tracked)

/datum/component/connect_containers/proc/handle_tracked_qdel()
	SIGNAL_HANDLER
	qdel(src)

/datum/component/connect_containers/proc/update_signals(atom/movable/listener)
	var/list/movement_sources = list(listener)
	if(!ismovable(listener.loc))
		ObserveSet(movement_sources, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved))
		return

	for(var/atom/movable/container as anything in get_nested_locs(listener))
		movement_sources |= container
	if(!ObserveSet(movement_sources, COMSIG_MOVABLE_MOVED, PROC_REF(on_moved)))
		return
	for(var/atom/movable/container as anything in movement_sources)
		if(container == listener)
			continue
		for(var/signal in connections)
			parent.RegisterSignal(container, signal, connections[signal])

/datum/component/connect_containers/proc/unregister_signals(atom/movable/location)
	if(!ismovable(location))
		return

	for(var/atom/movable/target as anything in (get_nested_locs(location) + location))
		parent.UnregisterSignal(target, connections)

/datum/component/connect_containers/proc/on_moved(atom/movable/listener, atom/old_loc)
	SIGNAL_HANDLER
	unregister_signals(old_loc)
	update_signals(listener)
