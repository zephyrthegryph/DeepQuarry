/// Behaves like a loc hook, but nested: hooks events on all MOVABLES containing the tracked atom,
/// on behalf of a separate listener.
/// A plain datum owned by whoever creates it (hold it in a declared var); it deletes itself
/// when the tracked movable is deleted.
/datum/connect_containers
	/// Who the connection hooks are made for (their procs are called).
	var/datum/listener
	/// An assoc list of /datum/notice path -> proc ref (on listener) to hook onto each container.
	var/list/connections
	/**
	 * The atom being tracked. The datum deletes itself if the tracked is deleted.
	 * Hooks are also updated whenever it moves.
	 */
	var/atom/movable/tracked


/datum/connect_containers/New(datum/listener, atom/movable/tracked, list/connections)
	..()
	if(!ismovable(tracked))
		log_runtime("CONNECT_CONTAINERS: [listener?.type] tried to track non-movable [tracked] ([tracked?.type])")
		return
	rel_set(src, nameof(listener), listener)
	src.connections = connections
	set_tracked(tracked)

// owned state datum (was a component) unhooks and detaches from its owner.
// The listener's hooks on the containers go before phase 4 nulls listener; our own hooks go with our record.
/datum/connect_containers/lifecycle_prerelease()
	..()
	var/atom/movable/T = tracked()
	if(T)
		unregister_hooks(T)

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
		unobserve(tracked(), /datum/notice/moved, src)
		unobserve(tracked(), /datum/notice/qdeleting, src)
		unregister_hooks(tracked())
	rel_set(src, nameof(tracked), new_tracked)
	if(!tracked())
		return
	observe(tracked(), /datum/notice/moved, src, then(PROC_REF(on_moved)))
	observe(tracked(), /datum/notice/qdeleting, src, then(PROC_REF(handle_tracked_qdel)))
	update_hooks(tracked())

/datum/connect_containers/proc/handle_tracked_qdel(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	ended_with(src)

/datum/connect_containers/proc/update_hooks(atom/movable/moved_thing)
	if(!ismovable(moved_thing.loc) || !listener)
		return

	for(var/atom/movable/container as anything in get_nested_locs(moved_thing))
		observe(container, /datum/notice/moved, src, then(PROC_REF(on_moved)))
		for(var/event_path in connections)
			observe(container, event_path, listener, then(connections[event_path]))

/datum/connect_containers/proc/unregister_hooks(atom/movable/location)
	if(!ismovable(location))
		return

	var/list/paths = list()
	for(var/event_path in connections)
		paths += event_path
	for(var/atom/movable/target as anything in (get_nested_locs(location) + location))
		unobserve(target, /datum/notice/moved, src)
		if(listener)
			for(var/event_path in paths)
				unobserve(target, event_path, listener)

/datum/connect_containers/proc/on_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/movable/moved_thing = A.target
	var/datum/notice/moved/event = A
	unregister_hooks(event.old_loc)
	update_hooks(moved_thing)

/// The movable being tracked (a relation view).
/datum/connect_containers/proc/tracked() as /atom/movable
	return tracked
