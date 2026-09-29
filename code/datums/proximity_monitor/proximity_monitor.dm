/datum/proximity_monitor
	///The atom we are tracking
	var/host_handle
	///The atom that will receive HasProximity calls.
	var/hasprox_receiver_handle
	///The range of the proximity monitor. Things moving wihin it will trigger HasProximity calls.
	var/current_range
	///If we don't check turfs in range if the host's loc isn't a turf
	var/ignore_if_not_on_turf
	///The hooks of the range connector, needed to monitor the turfs in range.
	var/static/list/loc_connections = list(
		/datum/om/event/atom_entered = PROC_REF(on_entered),
		/datum/om/event/atom_exited = PROC_REF(on_uncrossed),
		/datum/om/event/atom_after_successful_initialized_on = PROC_REF(on_initialized_on),
	)
	/// Hooks the containers of the host (owned).
	var/datum/connect_containers/containers_connector
	/// Hooks the turfs in range of the host (owned).
	var/datum/connect_range/range_connector


/datum/proximity_monitor/New(atom/_host, range, _ignore_if_not_on_turf = TRUE)
	ignore_if_not_on_turf = _ignore_if_not_on_turf
	current_range = range
	set_host(_host)

/datum/proximity_monitor/proc/set_host(atom/new_host, atom/new_receiver)
	if(new_host == host())
		return
	if(host()) //No need to delete the range and containers connectors. They'll be updated with the new tracked host.
		om_unhook(host(), list(/datum/om/event/moved, /datum/om/event/qdeleting), src)
	if(hasprox_receiver())
		om_unhook(hasprox_receiver(), /datum/om/event/qdeleting, src)
	if(new_receiver)
		hasprox_receiver_handle = om_handle(new_receiver)
		if(new_receiver != new_host)
			om_hook(new_receiver, /datum/om/event/qdeleting, src, PROC_REF(on_host_or_receiver_del))
	else if(hasprox_receiver() == host()) //Default case
		hasprox_receiver_handle = om_handle(new_host)
	host_handle = om_handle(new_host)
	om_hook(new_host, /datum/om/event/qdeleting, src, PROC_REF(on_host_or_receiver_del))
	var/static/list/containers_connections = list(/datum/om/event/moved = PROC_REF(on_moved), /datum/om/event/before/movable_z_changed = PROC_REF(on_z_change))
	if(containers_connector && !QDELETED(containers_connector))
		containers_connector.update(host(), containers_connections)
	else if(ismovable(host()))
		containers_connector = new /datum/connect_containers(src, host(), containers_connections)
	om_hook(host(), /datum/om/event/moved, src, PROC_REF(on_moved))
	om_hook(host(), /datum/om/event/before/movable_z_changed, src, PROC_REF(on_z_change))
	set_range(current_range, TRUE)

/datum/proximity_monitor/proc/on_host_or_receiver_del(datum/source, datum/om/event/qdeleting/event)
	EVENT_HANDLER
	qdel(src)

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
	range_connector = new /datum/connect_range(src, host(), loc_connections, current_range, works_in_containers)

/datum/proximity_monitor/proc/on_moved(atom/movable/source, datum/om/event/moved/event)
	EVENT_HANDLER
	if(source == host())
		hasprox_receiver()?.HasProximity(host())

/datum/proximity_monitor/proc/on_z_change(datum/source, datum/om/event/before/movable_z_changed/event)
	EVENT_HANDLER
	return

/datum/proximity_monitor/proc/set_ignore_if_not_on_turf(does_ignore = TRUE)
	if(ignore_if_not_on_turf == does_ignore)
		return
	ignore_if_not_on_turf = does_ignore
	//Update the ignore_if_not_on_turf
	update_range_connector(ignore_if_not_on_turf)

/datum/proximity_monitor/proc/on_uncrossed(atom/source, datum/om/event/atom_exited/event)
	EVENT_HANDLER
	uncrossed(source, event.gone, event.new_loc)

/// Something left a turf in range. Used by the advanced subtype for effect fields.
/datum/proximity_monitor/proc/uncrossed(atom/source, atom/movable/gone, atom/new_loc)
	return

/datum/proximity_monitor/proc/on_entered(atom/source, datum/om/event/atom_entered/event)
	EVENT_HANDLER
	entered(source, event.arrived)

/datum/proximity_monitor/proc/on_initialized_on(atom/source, datum/om/event/atom_after_successful_initialized_on/event)
	EVENT_HANDLER
	entered(source, event.created)

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

/// LC-refs: the atom this monitor follows -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/proximity_monitor/proc/host() as /atom
	return om_resolve(host_handle)

/// LC-refs: the atom told about proximity -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/proximity_monitor/proc/hasprox_receiver() as /atom
	return om_resolve(hasprox_receiver_handle)
