/obj/machinery/door/unpowered
	autoclose = 0
	var/locked = 0

/obj/machinery/door/unpowered/Bumped(atom/AM)
	if(src.locked)
		return
	..()
	return

/obj/machinery/door/unpowered/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/unpowered_door_block,
	)
	..()

/// Old attackby: silently blocks energy blades and anything while locked, else falls through to the base door attackby.
/datum/interaction/machine_item/unpowered_door_block
	id = "unpowered_door_block"
	name = "Attack"
	held_type = /obj/item
	effect = /obj/machinery/door/unpowered/proc/interaction_block

/obj/machinery/door/unpowered/proc/interaction_block(mob/user, obj/item/held, datum/interaction/interaction)
	if(istype(held, /obj/item/melee/energy/blade))
		return TRUE
	if(locked)
		return TRUE
	return FALSE

/obj/machinery/door/unpowered/emag_act()
	return -1

/obj/machinery/door/unpowered/shuttle
	icon = 'icons/turf/shuttle_white.dmi'
	name = "door"
	icon_state = "door1"
	opacity = 1
	density = TRUE
