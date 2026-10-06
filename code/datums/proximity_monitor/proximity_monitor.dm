/datum/proximity_monitor
	///The atom we are tracking
	var/atom/host
	///The atom that will receive HasProximity calls.
	var/atom/hasprox_receiver
	///The range of the proximity monitor. Things moving wihin it will trigger HasProximity calls.
	var/current_range
	///If we don't check turfs in range if the host's loc isn't a turf
	var/ignore_if_not_on_turf
	///What the range connector tells the monitor about the turfs in range.
	var/static/list/loc_connections = list(
		RANGE_ENTERED = PROC_REF(on_entered),
		RANGE_EXITED = PROC_REF(on_uncrossed),
		RANGE_INITIALIZED = PROC_REF(on_initialized_on),
	)
	/// Hooks the containers of the host (owned).
	var/datum/connect_containers/containers_connector
	/// Hooks the turfs in range of the host (owned).
	var/datum/connect_range/range_connector

CAPABILITIES(/datum/proximity_monitor)
	owns_one(nameof(containers_connector), /datum/connect_containers)
	owns_one(nameof(range_connector), /datum/connect_range)


/datum/proximity_monitor/New(atom/_host, range, _ignore_if_not_on_turf = TRUE)
	ignore_if_not_on_turf = _ignore_if_not_on_turf
	current_range = range
	set_host(_host)

/datum/proximity_monitor/proc/set_host(atom/new_host, atom/new_receiver)
	if(new_host == host())
		return
	if(host()) //No need to delete the range and containers connectors. They'll be updated with the new tracked host.
		unobserve(host(), /datum/notice/moved, src)
		unobserve(host(), /datum/notice/qdeleting, src)
	if(hasprox_receiver())
		unobserve(hasprox_receiver(), /datum/notice/qdeleting, src)
	if(new_receiver)
		rel_set(src, nameof(hasprox_receiver), new_receiver)
		if(new_receiver != new_host)
			observe(new_receiver, /datum/notice/qdeleting, src, then(PROC_REF(on_host_or_receiver_del)))
	else if(hasprox_receiver() == host()) //Default case
		rel_set(src, nameof(hasprox_receiver), new_host)
	rel_set(src, nameof(host), new_host)
	observe(new_host, /datum/notice/qdeleting, src, then(PROC_REF(on_host_or_receiver_del)))
	var/static/list/containers_connections = list(/datum/notice/moved = PROC_REF(on_moved), /datum/notice/movable_z_changed = PROC_REF(on_z_change))
	if(containers_connector && !QDELETED(containers_connector))
		containers_connector.update(host(), containers_connections)
	else if(ismovable(host()))
		rel_set(src, nameof(containers_connector), new /datum/connect_containers(src, host(), containers_connections))
	observe(host(), /datum/notice/moved, src, then(PROC_REF(on_moved)))
	observe(host(), /datum/notice/movable_z_changed, src, then(PROC_REF(on_z_change)))
	set_range(current_range, TRUE)

/datum/proximity_monitor/proc/on_host_or_receiver_del(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	ended_with(src)

/datum/proximity_monitor/proc/set_range(range, force_rebuild = FALSE)
	if(!force_rebuild && range == current_range)
		return FALSE
	. = TRUE
	current_range = range

	//If the range connector exists already, this will just update its range. No errors or duplicates.
	update_range_connector(!ignore_if_not_on_turf)

/// Creates the range connector, or updates the live one with the current host and range.
/datum/proximity_monitor/proc/update_range_connector(works_in_containers)
	if(range_connector && !QDELETED(range_connector))
		range_connector.update(host(), loc_connections, current_range, works_in_containers)
		return
	rel_set(src, nameof(range_connector), new /datum/connect_range(src, host(), loc_connections, current_range, works_in_containers))

/datum/proximity_monitor/proc/on_moved(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/movable/source = N.target
	if(source == host())
		hasprox_receiver()?.HasProximity(host())

/datum/proximity_monitor/proc/on_z_change(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/proximity_monitor/proc/set_ignore_if_not_on_turf(does_ignore = TRUE)
	if(ignore_if_not_on_turf == does_ignore)
		return
	ignore_if_not_on_turf = does_ignore
	//Update the ignore_if_not_on_turf
	update_range_connector(ignore_if_not_on_turf)

/datum/proximity_monitor/proc/on_uncrossed(atom/source, atom/movable/gone, atom/new_loc)
	SHOULD_NOT_SLEEP(TRUE)
	uncrossed(source, gone, new_loc)

/// Something left a turf in range. Used by the advanced subtype for effect fields.
/datum/proximity_monitor/proc/uncrossed(atom/source, atom/movable/gone, atom/new_loc)
	return

/datum/proximity_monitor/proc/on_entered(atom/source, atom/movable/arrived, atom/old_loc)
	SHOULD_NOT_SLEEP(TRUE)
	entered(source, arrived)

/datum/proximity_monitor/proc/on_initialized_on(atom/source, atom/movable/created, mapload)
	SHOULD_NOT_SLEEP(TRUE)
	entered(source, created)

/// Something entered (or was created on) a turf in range.
/datum/proximity_monitor/proc/entered(atom/source, atom/movable/arrived)
	if(source != host())
		hasprox_receiver()?.HasProximity(arrived)

/datum/proximity_monitor/mobspawner

/datum/proximity_monitor/mobspawner/uncrossed(atom/source, atom/movable/AM, atom/new_loc)
	var/obj/structure/mob_spawner/scanner/scanner = host()
	scanner.CheckProximity(AM,new_loc)

/datum/proximity_monitor/mobspawner/entered(atom/source, atom/movable/arrived)
	var/obj/structure/mob_spawner/scanner/scanner = host()
	if(source != host())
		scanner.NewProximity(arrived)

/// The atom this monitor follows (a relation view).
/datum/proximity_monitor/proc/host() as /atom
	return host

/// The atom told about proximity (a relation view).
/datum/proximity_monitor/proc/hasprox_receiver() as /atom
	return hasprox_receiver
