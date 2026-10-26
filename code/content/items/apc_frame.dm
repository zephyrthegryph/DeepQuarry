// APC HULL

MATERIAL_MIX(/obj/item/frame/apc, list(MAT_STEEL = 100, MAT_GLASS = 30))
/obj/item/frame/apc
	name = "\improper APC frame"
	desc = "Used for repairing or building APCs"
	icon = 'icons/obj/apc_repair.dmi'
	icon_state = "apc_frame"
	refund_amt = 2
	build_wall_only = TRUE

MSG_DEF_SELF(apc_frame/bad_spot, "APC cannot be placed on this spot.")
MSG_DEF_SELF(apc_frame/bad_area, "APC cannot be placed in this area.")
MSG_DEF_SELF(apc_frame/area_has_one, "This area already has an APC.")
MSG_DEF_SELF(apc_frame/terminal_taken, "There is another network terminal here.")
MSG_DEF_SELF(apc_frame/cut_terminal, "You cut the cables and disassemble the unused power terminal.")

/// An APC frame is only ever an APC: the generic wall-frame choice of what to build is not asked.
/obj/item/frame/apc/wall_type_needed(datum/act/op/A)
	return FALSE

/// An APC faces the wall it hangs on (its back to the builder).
/obj/item/frame/apc/mount_dir(atom/wall, mob/user)
	return get_dir(user, wall)

/// One APC to an area, on a floor of an area that takes power, and no terminal of another machine under it.
/obj/item/frame/apc/mount_refusal(datum/act/op/A)
	var/turf/spot = get_turf(A.actor)
	var/area/where = spot?.loc
	if(!istype(spot, /turf/simulated/floor))
		return /datum/msg/apc_frame/bad_spot
	if(where.requires_power == 0 || istype(where, /area/space))
		return /datum/msg/apc_frame/bad_area
	if(where.get_apc())
		return /datum/msg/apc_frame/area_has_one
	for(var/obj/machinery/power/terminal/T in turf_contents_of_type(spot, /obj/machinery/power/terminal))
		if(T.master())
			return /datum/msg/apc_frame/terminal_taken
	return null

/// The frame becomes an APC at the first stage of its build graph (a bare frame: no board, no cell, the cover open), facing the wall. A loose
/// terminal under it is cut up into its cable first.
/obj/item/frame/apc/mount_on(datum/act/op/A)
	var/mob/user = A.actor
	var/turf/spot = get_turf(user)
	for(var/obj/machinery/power/terminal/T in turf_contents_of_type(spot, /obj/machinery/power/terminal))
		new /obj/item/stack/cable_coil(spot, 10)
		op_tell(user, /datum/msg/apc_frame/cut_terminal)
		spent(T)
	user.drop_from_inventory(src, spot) // built on the wall, not in the hand: replace_with() hands the successor the original's slot
	replace_with(src, /obj/machinery/power/apc, mount_dir(A.target, user), TRUE)
	return OP_OK
