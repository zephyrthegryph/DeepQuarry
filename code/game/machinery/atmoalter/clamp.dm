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

/obj/machinery/clamp/Initialize(mapload, obj/machinery/atmospherics/pipe/simple/to_attach = null)
	. = ..()
	if(istype(to_attach))
		rel_set(src, nameof(target), to_attach)
	else
		rel_set(src, nameof(target), locate_within(loc, /obj/machinery/atmospherics/pipe/simple))
	if(target_ref())
		update_networks()
		dir = target_ref().dir

/obj/machinery/clamp/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/clamp_toggle,
	)
	..()

/// Toggle the clamp open/closed; declines (falls through) if not attached to a pipe.
/datum/interaction/machine_hand/ungated/clamp_toggle
	id = "clamp_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/clamp/proc/interaction_toggle

/obj/machinery/clamp/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	if(!target_ref())
		return FALSE
	if(!open)
		open()
	else
		close()
	to_chat(user, span_notice("You turn [open ? "off" : "on"] \the [src]"))
	return TRUE

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

	open = 1
	icon_state = "pclamp0"
	target_ref().in_stasis = 0
	return 1

/obj/machinery/clamp/proc/close()
	if(!open)
		return 0

	target_ref().rust_set_physical_edges(FALSE)

	open = 0
	icon_state = "pclamp1"
	target_ref().in_stasis = 1

	return 1

/obj/machinery/clamp/MouseDrop(obj/over_object as obj)
	if(!usr)
		return

	if(open && over_object == usr && Adjacent(usr))
		to_chat(usr, span_notice("You begin to remove \the [src]..."))
		om_task_timed(usr, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(MouseDrop_timed_done), done_args = list(usr))
	else
		to_chat(usr, span_warning("You can't remove \the [src] while it's active!"))

/obj/machinery/clamp/proc/MouseDrop_timed_done(mob/usr_mob)
	to_chat(usr_mob, span_notice("You have removed \the [src]."))
	var/obj/item/clamp/C = new/obj/item/clamp(src.loc)
	C.forceMove(usr_mob.loc)
	if(ishuman(usr_mob))
		usr_mob.put_in_hands(C)
	replace_with(src, C)
	return

/obj/item/clamp
	name = "stasis clamp"
	desc = "A magnetic clamp which can halt the flow of gas in a pipe, via a localised stasis field."
	icon = 'icons/atmos/clamp.dmi'
	icon_state = "pclamp0"

/obj/item/clamp/afterattack(atom/A, mob/user as mob, proximity)
	if(!proximity)
		return

	if (istype(A, /obj/machinery/atmospherics/pipe/simple))
		to_chat(user, span_notice("You begin to attach \the [src] to \the [A]..."))
		var/C = locate_within(get_turf(A), /obj/machinery/clamp)
		om_task_start(/datum/om/task/timed/clamp_afterattack, user, src, receiver = src, A = A, C = C)
		if(C)
			to_chat(user, span_notice("\The [C] is already attached to the pipe at this location!"))

/datum/om/task/timed/clamp_afterattack
	duration = 3 SECONDS
	complete_proc = /obj/item/clamp/proc/afterattack_timed_done
	var/atom/A
	var/C

/obj/item/clamp/proc/afterattack_timed_done(datum/om/task/timed/clamp_afterattack/task)
	var/atom/A = task.A
	var/mob/user = task.actor
	var/C = task.C
	if(!(!C))
		return
	if(!user.unEquip(src))
		return
	to_chat(user, span_notice("You have attached \the [src] to \the [A]."))
	new/obj/machinery/clamp(A.loc, A)
	qdel(src)

/// target (a relation view: it reads null once the target is deleted).
/obj/machinery/clamp/proc/target_ref() as /obj/machinery/atmospherics/pipe/simple
	return target

/// network node1 (a relation view: it reads null once the target is deleted).
/obj/machinery/clamp/proc/network_node1() as /datum/pipe_network
	return network_node1

/// network node2 (a relation view: it reads null once the target is deleted).
/obj/machinery/clamp/proc/network_node2() as /datum/pipe_network
	return network_node2
