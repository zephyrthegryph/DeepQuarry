/**
 * Tells a listener what happens on every turf in range of a tracked atom (like a loc hook, but for every turf in range).
 * A plain datum owned by whoever creates it (hold it in a declared var); it deletes itself when the tracked atom is deleted.
 *
 * It is one entry in the range watcher's grid (code/datums/range_watch.dm), not a hook per turf: the listener's procs named in `connections`
 * are called as x(turf, thing, other) for RANGE_ENTERED, RANGE_EXITED and RANGE_INITIALIZED on any turf within `range` (a square) of the tracked
 * atom's turf. The atom's own movement, and the movement of every container it is nested in, moves the watcher.
 */
/datum/connect_range
	/// Who the connection is made for (their procs are called).
	var/datum/listener
	/// An assoc list of RANGE_* kind -> proc ref (on listener) called for it on each turf in range.
	var/list/connections
	/**
	 * The atom being tracked. The datum deletes itself if the tracked is deleted.
	 * The watcher is also moved whenever it moves (if it's a movable).
	 */
	var/atom/tracked

	/// The watcher is made only for turfs not farther from tracked than this.
	var/range
	/// Whether this works when the movable isn't directly located on a turf.
	var/works_in_containers

	/// Where the watcher is: the tracked atom's turf. cz is null while it is not in the grid.
	var/cx
	var/cy
	var/cz
	/// The grid buckets the watcher is in.
	var/list/buckets


/datum/connect_range/New(datum/listener, atom/tracked, list/connections, range, works_in_containers = TRUE)
	..()
	if(!isatom(tracked) || isarea(tracked) || range < 0)
		log_runtime("CONNECT_RANGE: [listener?.type] passed an invalid target [tracked] ([tracked?.type]) or range [range]")
		return
	rel_set(src, nameof(listener), listener)
	src.connections = connections
	src.range = range
	src.works_in_containers = works_in_containers
	set_tracked(tracked)

// owned state datum (was a component) leaves the grid and detaches from its owner.
/datum/connect_range/lifecycle_prerelease()
	..()
	var/atom/T = tracked()
	if(T)
		unobserve_containers(isturf(T) ? T : T.loc)
	range_unwatch()

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
	//Leave the grid with the old settings.
	unobserve_containers(isturf(tracked) ? tracked : tracked.loc)
	range_unwatch()
	range = new_range
	works_in_containers = new_works_in_containers
	//Join it again with the new settings.
	update_hooks(src.tracked())

/datum/connect_range/proc/set_tracked(atom/new_tracked)
	if(tracked()) //Leave the old tracked and its surroundings
		unobserve_containers(isturf(tracked()) ? tracked() : tracked().loc)
		range_unwatch()
		unobserve(tracked(), /datum/notice/moved, src)
		unobserve(tracked(), /datum/notice/qdeleting, src)
	rel_set(src, nameof(tracked), new_tracked)
	if(!tracked())
		return
	//Watch the new tracked atom and its surroundings.
	observe(tracked(), /datum/notice/moved, src, then(PROC_REF(on_moved)))
	observe(tracked(), /datum/notice/qdeleting, src, then(PROC_REF(handle_tracked_qdel)))
	update_hooks(tracked())

/datum/connect_range/proc/handle_tracked_qdel(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	ended_with(src)

/datum/connect_range/proc/update_hooks(atom/target, atom/old_loc)
	var/turf/current_turf = get_turf(target)
	if(isnull(current_turf))
		unobserve_containers(old_loc)
		range_unwatch()
		return

	var/loc_is_movable = ismovable(target.loc)

	if(loc_is_movable)
		if(!works_in_containers)
			unobserve_containers(old_loc)
			range_unwatch()
			return

	//Only move the watcher if it's moved to a new turf.
	if(current_turf == get_turf(old_loc))
		unobserve_containers(old_loc)
		return
	unobserve_containers(old_loc)
	if(loc_is_movable)
		//Keep track of possible movement of all movables the target is in.
		for(var/atom/movable/container as anything in get_nested_locs(target))
			observe(container, /datum/notice/moved, src, then(PROC_REF(on_moved)))
	if(!listener)
		return
	range_watch(current_turf)

/// Stops watching the movement of the containers around `location` (the places the tracked atom was nested in).
/datum/connect_range/proc/unobserve_containers(atom/location)
	//The location is null or is a container and we shouldn't have been watching it
	if(isnull(location) || (!works_in_containers && !isturf(location)))
		return
	if(ismovable(location))
		for(var/atom/movable/target as anything in (get_nested_locs(location) + location))
			unobserve(target, /datum/notice/moved, src)

/// Puts the watcher in the grid around `center`: in every bucket the square of its range touches, and out of the ones it no longer does.
/datum/connect_range/proc/range_watch(turf/center)
	cx = center.x
	cy = center.y
	var/was_watching = !isnull(cz)
	cz = center.z
	var/list/wanted = list()
	// Bit shifts are unsigned in DM: clamp to the first turf before shifting, never shift a negative coordinate.
	for(var/bx in (max(cx - range, 1) >> RANGE_BUCKET_SHIFT) to (max(cx + range, 1) >> RANGE_BUCKET_SHIFT))
		for(var/by in (max(cy - range, 1) >> RANGE_BUCKET_SHIFT) to (max(cy + range, 1) >> RANGE_BUCKET_SHIFT))
			wanted += RANGE_BUCKET_KEY(cz, bx, by)
	var/list/was_in = buckets || list()
	for(var/key in was_in - wanted)
		range_leave_bucket(key)
	for(var/key in wanted - was_in)
		var/list/bucket = range_watch_cell(round(key / 1000000), round((key % 1000000) / 1000), key % 1000, TRUE)
		bucket += src
	buckets = wanted
	if(!was_watching)
		GLOB.range_watch_count++

/// Takes the watcher out of the grid.
/datum/connect_range/proc/range_unwatch()
	for(var/key in buckets)
		range_leave_bucket(key)
	buckets = null
	if(!isnull(cz))
		cz = null
		GLOB.range_watch_count--

/datum/connect_range/proc/range_leave_bucket(key)
	var/list/bucket = range_watch_cell(round(key / 1000000), round((key % 1000000) / 1000), key % 1000)
	bucket?.Remove(src)

/// A turf in a bucket the watcher is in had `kind` happen to `thing`: if the turf is in range, the listener hears it.
/datum/connect_range/proc/notify(turf/location, kind, atom/movable/thing, other)
	if(location.z != cz || abs(location.x - cx) > range || abs(location.y - cy) > range)
		return
	var/handler = connections?[kind]
	if(!handler || QDELETED(listener))
		return
	call(listener, handler)(location, thing, other)

/datum/connect_range/proc/on_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/movable/moved_thing = A.target
	var/datum/notice/moved/event = A
	update_hooks(moved_thing, event.old_loc)

/// The atom being tracked (a relation view).
/datum/connect_range/proc/tracked() as /atom
	return tracked
