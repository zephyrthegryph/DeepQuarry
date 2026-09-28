/**
 * Hooks events on all turfs in range of a tracked atom, on behalf of a separate listener
 * (like a loc hook, but for every turf in range).
 * A plain datum owned by whoever creates it (hold it in a declared var); it deletes itself
 * when the tracked atom is deleted.
 */
/datum/connect_range
	/// Who the connection hooks are made for (their procs are called).
	var/datum/listener
	/// An assoc list of /datum/om/event path -> proc ref (on listener) to hook onto each turf in range.
	var/list/connections
	/// The turfs currently connected.
	var/list/turfs = list() // ALLOW(instance_list): d: the tracked turf set; always populated while live
	/**
	 * The atom being tracked. The datum deletes itself if the tracked is deleted.
	 * Hooks are also updated whenever it moves (if it's a movable).
	 */
	var/tracked_handle

	/// Hooks are made only on turfs not farther from tracked than this.
	var/range
	/// Whether this works when the movable isn't directly located on a turf.
	var/works_in_containers

DECLARE_REF(/datum/connect_range, "listener", BACK, null)

/datum/connect_range/New(datum/listener, atom/tracked, list/connections, range, works_in_containers = TRUE)
	..()
	if(!isatom(tracked) || isarea(tracked) || range < 0)
		log_runtime("CONNECT_RANGE: [listener?.type] passed an invalid target [tracked] ([tracked?.type]) or range [range]")
		return
	src.listener = listener
	src.connections = connections
	src.range = range
	src.works_in_containers = works_in_containers
	set_tracked(tracked)

// owned state datum (was a component) unhooks and detaches from its owner.
// The listener's hooks on the turfs go before phase 4 nulls listener; our own hooks go with our record.
/datum/connect_range/lifecycle_prerelease()
	..()
	var/atom/T = tracked()
	if(T)
		unregister_hooks(isturf(T) ? T : T.loc, turfs)
	turfs = null

/// Was re-adding the component: update the target, range and container setting in place.
/datum/connect_range/proc/update(atom/tracked, list/new_connections, new_range, new_works_in_containers = TRUE)
	// Not equivalent. Checks if they are not the same list via shallow comparison.
	if(!compare_list(connections, new_connections))
		stack_trace("connect_range for [listener?.type] tried to update with different connections")
		return
	if(src.tracked() != tracked)
		set_tracked(tracked)
	if(range == new_range && works_in_containers == new_works_in_containers)
		return
	//Unhook with the old settings.
	unregister_hooks(isturf(tracked) ? tracked : tracked.loc, turfs)
	range = new_range
	works_in_containers = new_works_in_containers
	//Re-hook with the new settings.
	update_hooks(src.tracked())

/datum/connect_range/proc/set_tracked(atom/new_tracked)
	if(tracked()) //Unhook the old tracked and its surroundings
		unregister_hooks(isturf(tracked()) ? tracked() : tracked().loc, turfs)
		om_unhook(tracked(), list(/datum/om/event/moved, /datum/om/event/qdeleting), src)
	tracked_handle = om_handle(new_tracked)
	if(!tracked())
		return
	//Hook the new tracked atom and its surroundings.
	om_hook(tracked(), /datum/om/event/moved, src, PROC_REF(on_moved))
	om_hook(tracked(), /datum/om/event/qdeleting, src, PROC_REF(handle_tracked_qdel))
	update_hooks(tracked())

/datum/connect_range/proc/handle_tracked_qdel(datum/source, datum/om/event/qdeleting/event)
	EVENT_HANDLER
	qdel(src)

/datum/connect_range/proc/update_hooks(atom/target, atom/old_loc)
	var/turf/current_turf = get_turf(target)
	if(isnull(current_turf))
		unregister_hooks(old_loc, turfs)
		turfs = list()
		return

	var/loc_is_movable = ismovable(target.loc)

	if(loc_is_movable)
		if(!works_in_containers)
			unregister_hooks(old_loc, turfs)
			turfs = list()
			return

	//Only hook/unhook turfs if it's moved to a new turf.
	if(current_turf == get_turf(old_loc))
		unregister_hooks(old_loc, null)
		return
	var/list/old_turfs = turfs
	turfs = RANGE_TURFS(range, current_turf)
	unregister_hooks(old_loc, old_turfs - turfs)
	if(loc_is_movable)
		//Keep track of possible movement of all movables the target is in.
		for(var/atom/movable/container as anything in get_nested_locs(target))
			om_hook(container, /datum/om/event/moved, src, PROC_REF(on_moved))
	if(!listener)
		return
	for(var/turf/target_turf as anything in turfs - old_turfs)
		for(var/event_path in connections)
			om_hook(target_turf, event_path, listener, connections[event_path])

/datum/connect_range/proc/unregister_hooks(atom/location, list/remove_from)
	//The location is null or is a container and we shouldn't have hooks on it
	if(isnull(location) || (!works_in_containers && !isturf(location)))
		return

	if(ismovable(location))
		for(var/atom/movable/target as anything in (get_nested_locs(location) + location))
			om_unhook(target, /datum/om/event/moved, src)

	if(!length(remove_from) || !listener)
		return
	var/list/paths = list()
	for(var/event_path in connections)
		paths += event_path
	for(var/turf/target_turf as anything in remove_from)
		om_unhook(target_turf, paths, listener)

/datum/connect_range/proc/on_moved(atom/movable/moved_thing, datum/om/event/moved/event)
	EVENT_HANDLER
	update_hooks(moved_thing, event.old_loc)

/// LC-refs: the atom being tracked -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/connect_range/proc/tracked() as /atom
	return om_resolve(tracked_handle)
