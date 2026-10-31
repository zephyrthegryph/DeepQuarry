/// Tells the automatic shutoff valves that border `network` to look for leaks again, once the change that moved them has settled. With no network
/// (a change whose network is not known yet, such as new construction) every valve looks. Several calls before the check runs make one check.
/proc/wake_automatic_shutoff_valves(datum/pipe_network/network)
	for(var/obj/machinery/atmospherics/valve/shutoff/V as anything in REGISTRY_MEMBERS(REGISTRY_SHUTOFF_VALVES))
		if(!network || V.network_node1 == network || V.network_node2 == network)
			V.leaks_changed()

/obj/machinery/atmospherics/valve/shutoff
	icon = 'icons/atmos/clamp.dmi'
	icon_state = "map_vclamp0"
	pipe_state = "vclamp"

	name = "automatic shutoff valve"
	desc = "An automatic valve with control circuitry and pipe integrity sensor, capable of automatically isolating damaged segments of the pipe network."
	var/close_on_leaks = TRUE	// If false it will be always open
	level = 1

/obj/machinery/atmospherics/valve/shutoff/draw(datum/look/look)
	..()
	look.state("vclamp[open]")

/obj/machinery/atmospherics/valve/shutoff/examine(mob/user)
	. = ..()
	. += "The automatic shutoff circuit is [close_on_leaks ? "enabled" : "disabled"]."


MSG_DEF_SELF(shutoff/automatic, "You try to turn the valve by hand, but its automatic circuit turns it back.")
MSG_DEF_SELF(shutoff/circuit_on, "You enable the automatic shutoff circuit.")
MSG_DEF_SELF(shutoff/circuit_off, "You disable the automatic shutoff circuit.")
MSG_DEF_SELF(shutoff/opened, "You manually open the valve.")
MSG_DEF_SELF(shutoff/closed, "You manually close the valve.")


CAPABILITIES(/obj/machinery/atmospherics/valve/shutoff)
	setup(PROC_REF(open_initial_valve))
	silicon_hand()
	membership(joins = REGISTRY_SHUTOFF_VALVES)
	without("toggle")
	op("circuit", hand(), label("Toggle automatic control"), wait(0), says(PROC_REF(circuit_message)), then(PROC_REF(circuit_toggled)))
	op("manual", hand(), gesture(GESTURE_ALT), label("Manually toggle valve"), wait(0), when(PROC_REF(actor_living)),
		needs(req(PROC_REF(circuit_off))), says(PROC_REF(manual_message)), then(PROC_REF(manual_toggled)))

/obj/machinery/atmospherics/valve/shutoff/proc/open_initial_valve()
	open()
	hide(1)
	leaks_changed()

/obj/machinery/atmospherics/valve/shutoff/proc/circuit_toggled(datum/act/op/A)
	animate_toggle()
	set_close_on_leaks(!close_on_leaks)
	if(close_on_leaks)
		check_leaks()
	return OP_OK

/obj/machinery/atmospherics/valve/shutoff/proc/circuit_message(datum/act/A)
	return close_on_leaks ? /datum/msg/shutoff/circuit_on : /datum/msg/shutoff/circuit_off

/obj/machinery/atmospherics/valve/shutoff/proc/actor_living(datum/act/op/A)
	return isliving(A.actor)

/obj/machinery/atmospherics/valve/shutoff/proc/circuit_off(datum/act/A)
	return close_on_leaks ? /datum/msg/shutoff/automatic : null

/obj/machinery/atmospherics/valve/shutoff/proc/manual_toggled(datum/act/op/A)
	if(open)
		close()
	else
		open()
	return OP_OK

/obj/machinery/atmospherics/valve/shutoff/proc/manual_message(datum/act/A)
	return open ? /datum/msg/shutoff/opened : /datum/msg/shutoff/closed

// A network change re-checks: the new network may already leak.
/obj/machinery/atmospherics/valve/shutoff/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	. = ..()
	leaks_changed()

/obj/machinery/atmospherics/valve/shutoff/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	leaks_changed()

/obj/machinery/atmospherics/valve/shutoff/disconnect(obj/machinery/atmospherics/reference)
	. = ..()
	leaks_changed()

/// Its networks or their leaks changed: it checks on the next timer pass, once the rebuild that moved it has finished.
/obj/machinery/atmospherics/valve/shutoff/proc/leaks_changed()
	if(QDELETED(src))
		return
	after(src, 0, PROC_REF(check_leaks), key = "leak_check")

/// Closes on a leak it can see, reopens once both sides are sealed.
/obj/machinery/atmospherics/valve/shutoff/proc/check_leaks()
	if(!network_node1 || !network_node2 || !node1 || !node2)
		if(open && close_on_leaks)
			close()
		return

	if(close_on_leaks)
		if(open && (network_node1.leaks.len || network_node2.leaks.len))
			var/started = TICK_USAGE
			find_leaks()	// If we can see the leak, then this will find it, close the valve, and cut off that network
							// If we cannot see the leak, then this will not close the valve, and any valves that can see the leak will cut it off from us
			var/search_ms = TICK_USAGE_TO_MS(started)
			if(search_ms >= 25)
				log_world("SHUTOFF_SEARCH: [src] at ([x],[y],[z]) searched for a leak for [round(search_ms, 0.1)] ms (open now [open]; leaks on its sides [network_node1.leaks.len]/[network_node2.leaks.len])")
		else if(!open && !network_node1.leaks.len && !network_node2.leaks.len)
			var/opening_started = TICK_USAGE
			open()
			var/open_ms = TICK_USAGE_TO_MS(opening_started)
			if(open_ms >= 25)
				log_world("SHUTOFF_SEARCH: [src] at ([x],[y],[z]) reopened (both sides sealed) in [round(open_ms, 0.1)] ms")

// Breadth-first search for any leaking pipes that we can directly see
/obj/machinery/atmospherics/valve/shutoff/proc/find_leaks()
	var/list/obj/machinery/atmospherics/search = list()
	// What the search has queued, as a keyed list: `search |= x` scanned the whole queue for every node it met, which on a network of thousands of
	// pipes made the first check of a leaking network take a second (SLOW CALL check_leaks 1038 ms).
	var/list/queued = list()

	// We're the leak!
	if(!node1 || !node2)
		close()
		return

	// Only searching pipes
	if(istype(node1, /obj/machinery/atmospherics))
		search += node1
		queued[node1] = TRUE
	if(istype(node2, /obj/machinery/atmospherics) && !queued[node2])
		search += node2
		queued[node2] = TRUE

	// Breadth-first search
	for(var/i = 1, i <= search.len, i++) // wooo, proper for loop syntax!
		var/obj/machinery/atmospherics/A = search[i]
		if(!A)
			continue
		var/list/next // the nodes this one leads on to (null: a dead end)

		if(istype(A, /obj/machinery/atmospherics/pipe))
			var/obj/machinery/atmospherics/pipe/L = A
			if(L.leaking)
				close() // Found the leak!
				return

		if(istype(A, /obj/machinery/atmospherics/valve/shutoff))
			var/obj/machinery/atmospherics/valve/shutoff/S = A
			if(S.close_on_leaks || !S.open)
				continue 										// Either it will close, or it is closed. We don't care what's on the other side
			next = list(S.node1, S.node2)

		else if(istype(A, /obj/machinery/atmospherics/valve))	// Putting the shutoff before this means this won't catch shutoffs
			var/obj/machinery/atmospherics/valve/V = A
			if(V.open)
				next = list(V.node1, V.node2)
			else
				continue // Closed valve, dead end

		else if(istype(A, /obj/machinery/atmospherics/tvalve))
			var/obj/machinery/atmospherics/tvalve/T = A
			if(T.state)
				next = list(T.node1, T.node2)
			else
				next = list(T.node1, T.node3)

		else if(istype(A, /obj/machinery/atmospherics/pipe/zpipe))
			var/obj/machinery/atmospherics/pipe/zpipe/P = A
			next = list(P.node1, P.node2)

		else if(istype(A, /obj/machinery/atmospherics/pipe/simple))
			var/obj/machinery/atmospherics/pipe/P = A
			next = list(P.node1, P.node2)

		else if(istype(A, /obj/machinery/atmospherics/pipe/manifold))
			var/obj/machinery/atmospherics/pipe/manifold/M = A
			next = list(M.node1, M.node2, M.node3)

		else if(istype(A, /obj/machinery/atmospherics/pipe/manifold4w))
			var/obj/machinery/atmospherics/pipe/manifold4w/M = A
			next = list(M.node1, M.node2, M.node3, M.node4)

		// else continue, dead end
		for(var/obj/machinery/atmospherics/node in next)
			if(!queued[node])
				queued[node] = TRUE
				search += node
	// We broke out of the loop, so we see no leaks
	// The leaks therefore must be on the other side of another shutoff valve
	return
