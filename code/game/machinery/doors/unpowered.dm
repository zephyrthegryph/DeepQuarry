/obj/machinery/door/unpowered
	autoclose = 0
	locked = 0

/// A locked door ignores whatever walks into it.
/obj/machinery/door/unpowered/door_bumped(datum/act/A)
	if(src.locked)
		return
	..()

// A door with no power and no lock of its own: it takes no emag, and a held item does nothing to it while it is locked (an energy blade never does).
CAPABILITIES(/obj/machinery/door/unpowered)
	without(CAP_EMAG)
	op("block", item(/obj/item), when(req(PROC_REF(item_blocked))), priority(OP_PRIORITY_SUBVERT), then(PROC_REF(item_swallowed)))

/// Energy blades, and anything at all while the door is locked.
/obj/machinery/door/unpowered/proc/item_blocked(datum/act/op/A)
	return (istype(A.held, /obj/item/melee/energy/blade) || locked) ? null : MSG(req_failed)

/obj/machinery/door/unpowered/proc/item_swallowed(datum/act/op/A)
	return OP_OK

/obj/machinery/door/unpowered/shuttle
	icon = 'icons/turf/shuttle_white.dmi'
	name = "door"
	icon_state = "door1"
	opacity = 1
	density = TRUE
