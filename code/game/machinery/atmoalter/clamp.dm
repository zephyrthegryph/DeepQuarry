//Good luck. --BlueNexus

//Static version of the clamp
/obj/machinery/clamp
	name = "stasis clamp"
	desc = "A magnetic clamp which can halt the flow of gas in a pipe, via a localised stasis field."
	icon = 'icons/atmos/clamp.dmi'
	icon_state = "pclamp0"
	anchored = TRUE
	var/obj/machinery/atmospherics/pipe/simple/target
	var/open = 1

	var/datum/pipe_network/network_node1
	var/datum/pipe_network/network_node2

// ALLOW(init/INSTANCE_STATE): a clamp grips the pipe it was put on, or the one under it, and splits its network
/obj/machinery/clamp/Initialize(mapload)
	. = ..()
	if(!istype(target_ref(), /obj/machinery/atmospherics/pipe/simple))
		rel_set(src, nameof(target), locate_within(loc, /obj/machinery/atmospherics/pipe/simple))
	if(target_ref())
		update_networks()
		dir = target_ref().dir

TRACKED(/obj/machinery/clamp, open)

MSG_DEF_SELF(clamp/switched, "You switch the clamp.")
MSG_DEF_SELF(clamp/active, "You can't remove it while it's active!")
MSG_DEF(clamp/removed, "You have removed %T%.", "%U% removes %T%.")

CAPABILITIES(/obj/machinery/clamp)
	ref_one(nameof(target))
	ref_one(nameof(network_node1))
	ref_one(nameof(network_node2))
	op("toggle", hand(), label("Toggle"), wait(0), when(PROC_REF(attached)), says(MSG(clamp/switched)), then(PROC_REF(toggled)))
	// the clamp is dragged onto the one who takes it off
	op("remove", at_target(/mob/living), gesture(GESTURE_DRAG), label("Remove"), wait(3 SECONDS),
		needs(req(PROC_REF(dragged_by_self), because = MSG(op/not_available)), req(PROC_REF(released), because = MSG(clamp/active))), says(MSG(clamp/removed)), then(PROC_REF(removed)))
	param(nameof(target), pos = 1)

/obj/machinery/clamp/proc/attached(datum/act/op/A)
	return !!target_ref()

/obj/machinery/clamp/proc/toggled(datum/act/op/A)
	if(!open)
		open()
	else
		close()
	return OP_OK

/// The clamp is dragged onto the one dragging it.
/obj/machinery/clamp/proc/dragged_by_self(datum/act/op/A)
	return A.target == A.actor

/obj/machinery/clamp/proc/released(datum/act/A)
	return open

/// It comes off into the hands of whoever pulled it off.
/obj/machinery/clamp/proc/removed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/clamp/C = new /obj/item/clamp(user.loc)
	if(ishuman(user))
		user.put_in_hands(C)
	replace_with(src, C)
	return OP_OK

/obj/machinery/clamp/proc/update_networks()
	if(!target_ref())
		return
	else
		var/obj/machinery/atmospherics/pipe/node1 = target_ref().node1
		var/obj/machinery/atmospherics/pipe/node2 = target_ref().node2
		if(istype(node1))
			var/datum/pipeline/P1 = node1.parent
			rel_set(src, nameof(network_node1), P1.network)
		if(istype(node2))
			var/datum/pipeline/P2 = node2.parent
			rel_set(src, nameof(network_node2), P2.network)

// a closed clamp reopens its pipe.
/obj/machinery/clamp/on_destroy(force)
	if(!open)
		open()
	..()

/obj/machinery/clamp/proc/open()
	if(open || !target_ref())
		return 0

	target_ref().rust_set_physical_edges(TRUE)

	update_networks()

	set_open(1)
	icon_state = "pclamp0"
	target_ref().in_stasis = 0
	return 1

/obj/machinery/clamp/proc/close()
	if(!open)
		return 0

	target_ref().rust_set_physical_edges(FALSE)

	set_open(0)
	icon_state = "pclamp1"
	target_ref().in_stasis = 1

	return 1

/obj/item/clamp
	name = "stasis clamp"
	desc = "A magnetic clamp which can halt the flow of gas in a pipe, via a localised stasis field."
	icon = 'icons/atmos/clamp.dmi'
	icon_state = "pclamp0"

MSG_DEF_SELF(clamp/occupied, "A clamp is already attached to the pipe there!")
MSG_DEF(clamp/attached, "You attach %T% to the pipe.", "%U% attaches %T% to the pipe.")

CAPABILITIES(/obj/item/clamp)
	op("attach", at_target(/obj/machinery/atmospherics/pipe/simple), label("Attach clamp"), wait(3 SECONDS),
		needs(req_adjacent(), req(PROC_REF(pipe_free), because = MSG(clamp/occupied))), says(MSG(clamp/attached)), then(PROC_REF(attached_to)))

/obj/item/clamp/proc/pipe_free(datum/act/op/A)
	return !locate_within(get_turf(A.target), /obj/machinery/clamp)

/obj/item/clamp/proc/attached_to(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.unEquip(src))
		return OP_FAILED
	var/atom/pipe = A.target
	new /obj/machinery/clamp(pipe.loc, pipe)
	spent(src)
	return OP_OK

/// target (a relation view: it reads null once the target is deleted).
/obj/machinery/clamp/proc/target_ref() as /obj/machinery/atmospherics/pipe/simple
	return target

/// network node1 (a relation view: it reads null once the target is deleted).
/obj/machinery/clamp/proc/network_node1() as /datum/pipe_network
	return network_node1

/// network node2 (a relation view: it reads null once the target is deleted).
/obj/machinery/clamp/proc/network_node2() as /datum/pipe_network
	return network_node2
