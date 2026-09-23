//Good luck. --BlueNexus

//Static version of the clamp
/obj/machinery/clamp
	name = "stasis clamp"
	desc = "A magnetic clamp which can halt the flow of gas in a pipe, via a localised stasis field."
	icon = 'icons/atmos/clamp.dmi'
	icon_state = "pclamp0"
	anchored = TRUE
	var/obj/machinery/atmospherics/pipe/simple/target = null
	var/open = 1

	var/datum/pipe_network/network_node1
	var/datum/pipe_network/network_node2

/obj/machinery/clamp/Initialize(mapload, obj/machinery/atmospherics/pipe/simple/to_attach = null)
	. = ..()
	if(istype(to_attach))
		target = to_attach
	else
		target = locate(/obj/machinery/atmospherics/pipe/simple) in loc
	if(target)
		update_networks()
		dir = target.dir

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
	if(!target)
		return FALSE
	if(!open)
		open()
	else
		close()
	to_chat(user, span_notice("You turn [open ? "off" : "on"] \the [src]"))
	return TRUE

/obj/machinery/clamp/proc/update_networks()
	if(!target)
		return
	else
		var/obj/machinery/atmospherics/pipe/node1 = target.node1
		var/obj/machinery/atmospherics/pipe/node2 = target.node2
		if(istype(node1))
			var/datum/pipeline/P1 = node1.parent
			network_node1 = P1.network
		if(istype(node2))
			var/datum/pipeline/P2 = node2.parent
			network_node2 = P2.network

/obj/machinery/clamp/Destroy()
	if(!open)
		spawn(-1) open()
	. = ..()

/obj/machinery/clamp/proc/open()
	if(open || !target)
		return 0

	target.rust_set_physical_edges(TRUE)

	update_networks()

	open = 1
	icon_state = "pclamp0"
	target.in_stasis = 0
	return 1

/obj/machinery/clamp/proc/close()
	if(!open)
		return 0

	target.rust_set_physical_edges(FALSE)

	open = 0
	icon_state = "pclamp1"
	target.in_stasis = 1

	return 1

/obj/machinery/clamp/MouseDrop(obj/over_object as obj)
	if(!usr)
		return

	if(open && over_object == usr && Adjacent(usr))
		to_chat(usr, span_notice("You begin to remove \the [src]..."))
		if (do_after(usr, 3 SECONDS, target = src))
			to_chat(usr, span_notice("You have removed \the [src]."))
			var/obj/item/clamp/C = new/obj/item/clamp(src.loc)
			C.forceMove(usr.loc)
			if(ishuman(usr))
				usr.put_in_hands(C)
			qdel(src)
			return
	else
		to_chat(usr, span_warning("You can't remove \the [src] while it's active!"))

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
		var/C = locate(/obj/machinery/clamp) in get_turf(A)
		if (do_after(user, 3 SECONDS, target = src) && !C)
			if(!user.unEquip(src))
				return
			to_chat(user, span_notice("You have attached \the [src] to \the [A]."))
			new/obj/machinery/clamp(A.loc, A)
			qdel(src)
		if(C)
			to_chat(user, span_notice("\The [C] is already attached to the pipe at this location!"))
