
/// Tells the automatic shutoff valves that border `network` about a leak or split there
/// (Q14, reactor.md §9): it publishes the network's REACT_KEY_PIPE_NETWORK key, which only
/// that network's valves subscribe to. With no network (a change whose network is not
/// known yet, such as new construction) the global key wakes every valve. Publications
/// merge per tick, so a bulk blast needs no batching of its own.
/proc/wake_automatic_shutoff_valves(datum/pipe_network/network)
	REACT_PUBLISH(REACT_KEY_PIPE_NETWORK, network ? REACT_ID(network) : REACT_ID_GLOBAL, REACT_PIPE_LEAKS)

/obj/machinery/atmospherics/valve/shutoff
	icon = 'icons/atmos/clamp.dmi'
	icon_state = "map_vclamp0"
	pipe_state = "vclamp"

	name = "automatic shutoff valve"
	desc = "An automatic valve with control circuitry and pipe integrity sensor, capable of automatically isolating damaged segments of the pipe network."
	var/close_on_leaks = TRUE	// If false it will be always open
	level = 1
	/// REACT_KEY_PIPE_NETWORK subscriptions: the global key, and one per bordering network
	/// with the network ids they were made for.
	var/tmp/global_leak_token
	var/tmp/network1_token
	var/tmp/network1_id = 0
	var/tmp/network2_token
	var/tmp/network2_id = 0

/obj/machinery/atmospherics/valve/shutoff/update_icon()
	icon_state = "vclamp[open]"

/obj/machinery/atmospherics/valve/shutoff/examine(mob/user)
	. = ..()
	. += "The automatic shutoff circuit is [close_on_leaks ? "enabled" : "disabled"]."

REGISTRY_MEMBERSHIP(/obj/machinery/atmospherics/valve/shutoff, REGISTRY_SHUTOFF_VALVES)

/obj/machinery/atmospherics/valve/shutoff/Initialize(mapload)
	. = ..()
	open()
	hide(1)
	global_leak_token = REACT_ON_KEY(src, REACT_KEY_PIPE_NETWORK, REACT_ID_GLOBAL, REACT_PIPE_LEAKS)
	subscribe_network_keys()

/obj/machinery/atmospherics/valve/shutoff/Destroy()
	. = ..()

/obj/machinery/atmospherics/valve/shutoff/attack_ai(mob/user as mob)
	return src.attack_hand(user)

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
	var/id1 = network_node1 ? REACT_ID(network_node1) : 0
	var/id2 = network_node2 ? REACT_ID(network_node2) : 0
	if(id1 != network1_id)
		if(!isnull(network1_token))
			REACT_CANCEL(src, network1_token)
		network1_id = id1
		network1_token = id1 ? REACT_ON_KEY(src, REACT_KEY_PIPE_NETWORK, id1, REACT_PIPE_LEAKS) : null
	if(id2 != network2_id)
		if(!isnull(network2_token))
			REACT_CANCEL(src, network2_token)
		network2_id = id2
		network2_token = id2 ? REACT_ON_KEY(src, REACT_KEY_PIPE_NETWORK, id2, REACT_PIPE_LEAKS) : null

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
	if(QDELETED(src) || !reactor_id)
		return // Not initialized yet: Initialize() subscribes.
	subscribe_network_keys()
	// Check on the next dispatch, once the rebuild that moved us has finished.
	REACT_AT(src, world.time)

/obj/machinery/atmospherics/valve/shutoff/on_react(reason, source, source_kind)
	. = ..()
	subscribe_network_keys()
	check_leaks()

/obj/machinery/atmospherics/valve/shutoff/react_sleep_violation()
	var/id1 = network_node1?.reactor_id || 0
	var/id2 = network_node2?.reactor_id || 0
	if((network_node1 && (isnull(network1_token) || id1 != network1_id)) || (network_node2 && (isnull(network2_token) || id2 != network2_id)))
		return "not subscribed to its networks' keys"
	if(isnull(global_leak_token))
		return "not subscribed to the global leak key"
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
