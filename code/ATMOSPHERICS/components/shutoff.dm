
/// Tells the automatic shutoff valves that border `network` about a leak or split there
/// (Q14): it raises the network's CHANGE_PIPE_LEAKS, which only that
/// network's valves watch. With no network (a change whose network is not known yet, such as
/// new construction) GLOB.new_pipe_networks wakes every valve. Wakes merge per drain, so a bulk
/// blast needs no batching of its own.
/proc/wake_automatic_shutoff_valves(datum/pipe_network/network)
	om_changed(network || GLOB.new_pipe_networks, CHANGE_PIPE_LEAKS)

/// Raises CHANGE_PIPE_LEAKS for changes whose network is not known yet (new construction).
GLOBAL_DATUM_INIT(new_pipe_networks, /datum, new)

/// Leaks on a bordering network (or new construction anywhere).
/datum/om/behaviour/sleeper/shutoff_valve
	name = "shutoff valve"

/datum/om/behaviour/sleeper/shutoff_valve/on_wake(obj/machinery/atmospherics/valve/shutoff/V, changes)
	if(QDELETED(V))
		return
	V.subscribe_network_keys()
	V.check_leaks()

/obj/machinery/atmospherics/valve/shutoff
	silicon_use = SILICON_USE_HAND
	icon = 'icons/atmos/clamp.dmi'
	icon_state = "map_vclamp0"
	pipe_state = "vclamp"

	name = "automatic shutoff valve"
	desc = "An automatic valve with control circuitry and pipe integrity sensor, capable of automatically isolating damaged segments of the pipe network."
	var/close_on_leaks = TRUE	// If false it will be always open
	level = 1
	/// CHANGE_PIPE_LEAKS watches: TRUE once it watches GLOB.new_pipe_networks, and the network
	/// watched on each side.
	var/tmp/global_leak_token
	var/tmp/datum/pipe_network/network1_token
	var/tmp/datum/pipe_network/network2_token

DECLARE_APPEARANCE_PROC(/obj/machinery/atmospherics/valve/shutoff, PROC_REF(appearance_overlays), list())
/obj/machinery/atmospherics/valve/shutoff/appearance_overlays()
	. = list()
	icon_state = "vclamp[open]"

/obj/machinery/atmospherics/valve/shutoff/examine(mob/user)
	. = ..()
	. += "The automatic shutoff circuit is [close_on_leaks ? "enabled" : "disabled"]."

REGISTRY_MEMBERSHIP(/obj/machinery/atmospherics/valve/shutoff, REGISTRY_SHUTOFF_VALVES)

/obj/machinery/atmospherics/valve/shutoff/Initialize(mapload)
	. = ..()
	open()
	hide(1)
	om_attach(src, /datum/om/behaviour/sleeper/shutoff_valve)
	om_watch(src, GLOB.new_pipe_networks, CHANGE_PIPE_LEAKS, /datum/om/behaviour/sleeper/shutoff_valve)
	global_leak_token = TRUE
	subscribe_network_keys()

/obj/machinery/atmospherics/valve/shutoff/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/shutoff_toggle_auto,
		/datum/interaction/machine_alt/shutoff_manual,
	)
	..()

/// Toggle the automatic shutoff circuit.
/datum/interaction/machine_hand/ungated/shutoff_toggle_auto
	id = "shutoff_toggle_auto"
	name = "Toggle automatic control"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/atmospherics/valve/shutoff/proc/interaction_toggle_auto

/obj/machinery/atmospherics/valve/shutoff/proc/interaction_toggle_auto(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	update_icon(1)
	close_on_leaks = !close_on_leaks
	if(close_on_leaks)
		check_leaks()
	to_chat(user, "You [close_on_leaks ? "enable" : "disable"] the automatic shutoff circuit.")
	return TRUE

/// Alt+Click toggles the open/close function, when the autoseal is disabled.
/datum/interaction/machine_alt/shutoff_manual
	id = "shutoff_manual"
	name = "Manually toggle valve"
	consumes_input = FALSE
	effect = /obj/machinery/atmospherics/valve/shutoff/proc/interaction_manual_toggle

/obj/machinery/atmospherics/valve/shutoff/proc/interaction_manual_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	if(isliving(user))
		if(close_on_leaks)
			to_chat(user, "You try to manually [open ? "close" : "open"] the valve, but it [open ? "opens" : "closes"] automatically again.")
			return TRUE
		open ? close() : open()
		to_chat(user, "You manually [open ? "open" : "close"] the valve.")
	return TRUE

/// Subscribes to the keys of the networks on each side (again, if they changed).
/obj/machinery/atmospherics/valve/shutoff/proc/subscribe_network_keys()
	om_attach(src, /datum/om/behaviour/sleeper/shutoff_valve)
	if(network_node1 != network1_token)
		if(network1_token && network1_token != network_node2)
			om_unwatch(src, network1_token, /datum/om/behaviour/sleeper/shutoff_valve)
		network1_token = network_node1
		if(network1_token)
			om_watch(src, network1_token, CHANGE_PIPE_LEAKS, /datum/om/behaviour/sleeper/shutoff_valve)
	if(network_node2 != network2_token)
		if(network2_token && network2_token != network_node1)
			om_unwatch(src, network2_token, /datum/om/behaviour/sleeper/shutoff_valve)
		network2_token = network_node2
		if(network2_token)
			om_watch(src, network2_token, CHANGE_PIPE_LEAKS, /datum/om/behaviour/sleeper/shutoff_valve)

// A network change re-subscribes and re-checks: the new network may already leak.
/obj/machinery/atmospherics/valve/shutoff/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	. = ..()
	network_keys_changed()

/obj/machinery/atmospherics/valve/shutoff/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	network_keys_changed()

/obj/machinery/atmospherics/valve/shutoff/disconnect(obj/machinery/atmospherics/reference)
	. = ..()
	network_keys_changed()

/obj/machinery/atmospherics/valve/shutoff/proc/network_keys_changed()
	if(QDELETED(src) || isnull(global_leak_token))
		return // Not initialized yet: Initialize() subscribes.
	subscribe_network_keys()
	// Check on the next timer pass, once the rebuild that moved us has finished.
	om_after(src, 0, PROC_REF(recheck_leaks))

/obj/machinery/atmospherics/valve/shutoff/proc/recheck_leaks()
	subscribe_network_keys()
	check_leaks()

/obj/machinery/atmospherics/valve/shutoff/om_sleep_violation()
	if(network_node1 != network1_token || network_node2 != network2_token)
		return "not watching its networks' leaks"
	if(isnull(global_leak_token))
		return "not watching new pipe networks"
	if(close_on_leaks && !open && network_node1 && network_node2 && node1 && node2 && !length(network_node1.leaks) && !length(network_node2.leaks))
		return "closed with no leak on either side"
	return null

/// Closes on a leak it can see, reopens once both sides are sealed.
/obj/machinery/atmospherics/valve/shutoff/proc/check_leaks()
	if(!network_node1 || !network_node2 || !node1 || !node2)
		if(open && close_on_leaks)
			close()
		return

	if(close_on_leaks)
		if(open && (network_node1.leaks.len || network_node2.leaks.len))
			find_leaks()	// If we can see the leak, then this will find it, close the valve, and cut off that network
							// If we cannot see the leak, then this will not close the valve, and any valves that can see the leak will cut it off from us
		else if(!open && !network_node1.leaks.len && !network_node2.leaks.len)
			open()

// Breadth-first search for any leaking pipes that we can directly see
/obj/machinery/atmospherics/valve/shutoff/proc/find_leaks()
	var/list/obj/machinery/atmospherics/search = list()

	// We're the leak!
	if(!node1 || !node2)
		close()
		return

	// Only searching pipes
	if(istype(node1, /obj/machinery/atmospherics))
		search |= node1
	if(istype(node2, /obj/machinery/atmospherics))
		search |= node2

	// Breadth-first search
	for(var/i = 1, i <= search.len, i++) // wooo, proper for loop syntax!
		var/obj/machinery/atmospherics/A = search[i]
		if(!A)
			continue

		if(istype(A, /obj/machinery/atmospherics/pipe))
			var/obj/machinery/atmospherics/pipe/L = A
			if(L.leaking)
				close() // Found the leak!
				return

		if(istype(A, /obj/machinery/atmospherics/valve/shutoff))
			var/obj/machinery/atmospherics/valve/shutoff/S = A
			if(S.close_on_leaks || !S.open)
				continue 										// Either it will close, or it is closed. We don't care what's on the other side
			search |= list(S.node1, S.node2) 					// |= skips existing nodes, so we don't search loops infinitely

		else if(istype(A, /obj/machinery/atmospherics/valve))	// Putting the shutoff before this means this won't catch shutoffs
			var/obj/machinery/atmospherics/valve/V = A
			if(V.open)
				search |= list(V.node1, V.node2)
			else
				continue // Closed valve, dead end

		else if(istype(A, /obj/machinery/atmospherics/tvalve))
			var/obj/machinery/atmospherics/tvalve/T = A
			if(T.state)
				search |= list(T.node1, T.node2)
			else
				search |= list(T.node1, T.node3)

		else if(istype(A, /obj/machinery/atmospherics/pipe/zpipe))
			var/obj/machinery/atmospherics/pipe/zpipe/P = A
			search |= list(P.node1, P.node2)

		else if(istype(A, /obj/machinery/atmospherics/pipe/simple))
			var/obj/machinery/atmospherics/pipe/P = A
			search |= list(P.node1, P.node2)

		else if(istype(A, /obj/machinery/atmospherics/pipe/manifold))
			var/obj/machinery/atmospherics/pipe/manifold/M = A
			search |= list(M.node1, M.node2, M.node3)

		else if(istype(A, /obj/machinery/atmospherics/pipe/manifold4w))
			var/obj/machinery/atmospherics/pipe/manifold4w/M = A
			search |= list(M.node1, M.node2, M.node3, M.node4)

		// else continue, dead end
	// We broke out of the loop, so we see no leaks
	// The leaks therefore must be on the other side of another shutoff valve
	return

DECLARE_REF(/obj/machinery/atmospherics/valve/shutoff, "network1_token", HELD, null)
DECLARE_REF(/obj/machinery/atmospherics/valve/shutoff, "network2_token", HELD, null)
