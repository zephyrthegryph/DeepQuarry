/// Behaves like a loc hook, but nested: hooks events on all MOVABLES containing the tracked atom,
/// on behalf of a separate listener.
/// A plain datum owned by whoever creates it (hold it in a declared var); it deletes itself
/// when the tracked movable is deleted.
/datum/connect_containers
	/// Who the connection hooks are made for (their procs are called).
	var/datum/listener
	/// An assoc list of /datum/om/event path -> proc ref (on listener) to hook onto each container.
	var/list/connections
	/**
	 * The atom being tracked. The datum deletes itself if the tracked is deleted.
	 * Hooks are also updated whenever it moves.
	 */
	var/tracked_handle

REF_BACK(/datum/connect_containers, list("listener" = null))

/datum/connect_containers/New(datum/listener, atom/movable/tracked, list/connections)
	..()
	if(!ismovable(tracked))
		log_runtime("CONNECT_CONTAINERS: [listener?.type] tried to track non-movable [tracked] ([tracked?.type])")
		return
	src.listener = listener
	src.connections = connections
	set_tracked(tracked)

// ALLOW(lifecycle): owned state datum (was a component) unhooks and detaches from its owner.
/datum/connect_containers/Destroy()
	if(tracked())
		om_unhook(tracked(), list(/datum/om/event/moved, /datum/om/event/qdeleting), src)
		unregister_hooks(tracked())
	om_unhook_all(src)
	listener = null
	tracked_handle = null
	return ..()

/// Was the dupe check of AddComponent: same connections, maybe a new target.
/// Returns FALSE when `new_connections` differ from ours (the caller needs another instance).
/datum/connect_containers/proc/update(atom/movable/tracked, list/new_connections)
	// Not equivalent. Checks if they are not the same list via shallow comparison.
	if(!compare_list(connections, new_connections))
		return FALSE // Different set of connections.
	if(src.tracked() != tracked)
		set_tracked(tracked) // Different target for the same set of connections, track the new target.
	return TRUE

/datum/connect_containers/proc/set_tracked(atom/movable/new_tracked)
	if(tracked())
		om_unhook(tracked(), list(/datum/om/event/moved, /datum/om/event/qdeleting), src)
		unregister_hooks(tracked())
	tracked_handle = om_handle(new_tracked)
	if(!tracked())
		return
	om_hook(tracked(), /datum/om/event/moved, src, PROC_REF(on_moved))
	om_hook(tracked(), /datum/om/event/qdeleting, src, PROC_REF(handle_tracked_qdel))
	update_hooks(tracked())

/datum/connect_containers/proc/handle_tracked_qdel(datum/source, datum/om/event/qdeleting/event)
	EVENT_HANDLER
	qdel(src)

/datum/connect_containers/proc/update_hooks(atom/movable/moved_thing)
	if(!ismovable(moved_thing.loc) || !listener)
		return

	for(var/atom/movable/container as anything in get_nested_locs(moved_thing))
		om_hook(container, /datum/om/event/moved, src, PROC_REF(on_moved))
		for(var/event_path in connections)
			om_hook(container, event_path, listener, connections[event_path])

/datum/connect_containers/proc/unregister_hooks(atom/movable/location)
	if(!ismovable(location))
		return

	var/list/paths = list()
	for(var/event_path in connections)
		paths += event_path
	for(var/atom/movable/target as anything in (get_nested_locs(location) + location))
		om_unhook(target, /datum/om/event/moved, src)
		if(listener)
			om_unhook(target, paths, listener)

/datum/connect_containers/proc/on_moved(atom/movable/moved_thing, datum/om/event/moved/event)
	EVENT_HANDLER
	unregister_hooks(event.old_loc)
	update_hooks(moved_thing)

/// LC-refs: the movable being tracked -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/connect_containers/proc/tracked() as /atom/movable
	return om_resolve(tracked_handle)
