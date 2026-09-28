/// This component behaves similar to connect_loc_behalf, but working off clients and mobs instead of loc
/// To be clear, we hook into a signal on a tracked client's mob
/// We retain the ability to react to that signal on a seperate listener, which makes this quite powerful
/datum/component/connect_mob_behalf
	dupe_mode = COMPONENT_DUPE_UNIQUE

	/// An assoc list of signal -> procpath to register to the mob our client "owns"
	var/list/connections
	/// The master client we're working with
	var/tracked_handle
	/// The mob we're currently tracking
	var/tracked_mob_handle

/datum/component/connect_mob_behalf/Initialize(client/tracked, list/connections)
	. = ..()
	if (!istype(tracked))
		return COMPONENT_INCOMPATIBLE
	src.connections = connections
	src.tracked_handle = om_handle(tracked)

/datum/component/connect_mob_behalf/RegisterWithParent()
	RegisterSignal(tracked(), COMSIG_QDELETING, PROC_REF(handle_tracked_qdel))
	update_signals()

/datum/component/connect_mob_behalf/UnregisterFromParent()
	unregister_signals()
	UnregisterSignal(tracked(), COMSIG_QDELETING)

	tracked_handle = null
	tracked_mob_handle = null

/datum/component/connect_mob_behalf/proc/handle_tracked_qdel()
	SIGNAL_HANDLER
	qdel(src)

/datum/component/connect_mob_behalf/proc/update_signals()
	unregister_signals()
	// Yes this is a runtime silencer
	// We could be in a position where logout is sent to two things, one thing intercepts it, then deletes the client's new mob
	// It's rare, and the same check in connect_loc_behalf is more fruitful, but it's still worth doing
	if(QDELETED(tracked()?.mob))
		return
	tracked_mob_handle = om_handle(tracked().mob)
	RegisterSignal(tracked_mob(), COMSIG_MOB_LOGOUT, PROC_REF(on_logout))
	for (var/signal in connections)
		parent.RegisterSignal(tracked_mob(), signal, connections[signal])

/datum/component/connect_mob_behalf/proc/unregister_signals()
	if(isnull(tracked_mob()))
		return

	parent.UnregisterSignal(tracked_mob(), connections)
	UnregisterSignal(tracked_mob(), COMSIG_MOB_LOGOUT)

	tracked_mob_handle = null

/datum/component/connect_mob_behalf/proc/on_logout(mob/source)
	SIGNAL_HANDLER
	update_signals()

/// LC-refs: the client being tracked -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/component/connect_mob_behalf/proc/tracked() as /client
	return om_resolve(tracked_handle)

/// LC-refs: the tracked client's mob -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/component/connect_mob_behalf/proc/tracked_mob() as /mob
	return om_resolve(tracked_mob_handle)
