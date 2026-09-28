/obj/structure/vehiclecage
	name = "vehicle cage"
	desc = "A large metal lattice that seems to exist solely to annoy consumers."
	icon = 'icons/obj/storage.dmi'
	icon_state = "vehicle_cage"
	density = TRUE
	var/my_vehicle_handle
	var/my_vehicle_type
	var/paint_color = "#666666"

// C11: one slot for the caged vehicle. No custom Destroy() overrides the
// base /atom/movable one, so the default spill policy (not SLOT_DROP_HOLDER)
// is correct here: disassemble() already moves the vehicle out before
// qdel(src), so the slot is empty by then, but any other qdel path needs the
// generic drop-policy pass to actually place the vehicle instead of losing it.
/datum/om/relation/slot/vehicle_cage
	holder = /obj/structure/vehiclecage
	slot_id = CONTAINER_SLOT_VEHICLE_CAGE
	name = "vehicle"
	exposure = SLOT_EXPOSURE_INTERNAL

/obj/structure/vehiclecage/examine(mob/user)
	. = ..()
	if(my_vehicle())
		. += span_notice("It seems to contain \the [my_vehicle()].")

/obj/structure/vehiclecage/Initialize(mapload)
	. = ..()
	if(my_vehicle_type)
		my_vehicle_handle = om_handle(new my_vehicle_type(src))
		for(var/obj/I in get_turf(src))
			if(I.density || I.anchored || I == src || !I.simulated || !istype(I, my_vehicle_type))
				continue
			load_vehicle(I)
	update_icon()

/obj/structure/vehiclecage/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/vehiclecage_hand,
	)
	..()

/// Old attack_hand: a hint that you need a wrench.
/datum/interaction/entry_hand/vehiclecage_hand
	id = "vehiclecage_hand"
	name = "Use"
	effect = /obj/structure/vehiclecage/proc/interaction_hand

/obj/structure/vehiclecage/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("You need a wrench to take this apart!"))
	return TRUE

/obj/structure/vehiclecage/proc/tool_disassemble(mob/user, obj/item/W, delay, quality)
	var/turf/T = get_turf(src)
	if(!T)
		to_chat(user, span_notice("You can't open this here!"))
		return TRUE
	use_tool(user, W, src, delay = delay, quality = quality, volume = 50, receiver = src, on_done = PROC_REF(tool_disassemble_tool_done), done_args = list(user, W))
	return TRUE

/obj/structure/vehiclecage/proc/tool_disassemble_tool_done(mob/user, obj/item/W)
	disassemble(W, user)

/obj/structure/vehiclecage/wrench_act(mob/user, obj/item/W)
	user.visible_message(span_notice("[user] begins loosening \the [src]'s bolts."))
	return tool_disassemble(user, W, 6 SECONDS, TOOL_WRENCH)

/obj/structure/vehiclecage/wirecutter_act(mob/user, obj/item/W)
	user.visible_message(span_notice("[user] begins cutting \the [src]'s bolts."))
	return tool_disassemble(user, W, 7 SECONDS, TOOL_WIRECUTTER)

/obj/structure/vehiclecage/update_icon()
	..()
	cut_overlays()
	underlays.Cut()

	var/image/framepaint = new(icon = 'icons/obj/storage.dmi', icon_state = "[initial(icon_state)]_a", layer = MOB_LAYER + 1.1)
	framepaint.plane = MOB_PLANE
	framepaint.color = paint_color
	add_overlay(framepaint)

	for(var/obj/vehicle/V in slot_contents(CONTAINER_SLOT_VEHICLE_CAGE))
		var/image/showcase = new(V)
		showcase.layer = src.layer - 0.1
		underlays += showcase

/obj/structure/vehiclecage/MouseDrop_T(atom/movable/C, mob/user as mob)
	if(user && (user?.buckled_to() || user.stat || user.restrained() || !Adjacent(user) || !user.Adjacent(C)))
		return

	var/obj/vehicle/V
	if(istype(C, /obj/vehicle))
		V = C
	if(!V)
		return

	if(!my_vehicle())
		load_vehicle(V, user)

/obj/structure/vehiclecage/proc/load_vehicle(obj/vehicle/V, mob/user as mob)
	if(user)
		user.visible_message(span_notice("[user] loads \the [V] into \the [src]."), \
								span_notice("You load \the [V] into \the [src]."), \
								span_notice("You hear creaking metal."))

	V.forceMove(src)

	paint_color = V.paint_color

	update_icon()

/obj/structure/vehiclecage/proc/disassemble(obj/item/W as obj, mob/user as mob)
	var/turf/T = get_turf(src)
	new /obj/item/stack/material/steel(src.loc, 5)

	for(var/atom/movable/AM in slot_contents(CONTAINER_SLOT_VEHICLE_CAGE))
		if(AM.simulated)
			AM.forceMove(T)

	my_vehicle_handle = null
	user.visible_message(span_notice("[user] release \the [src]."), \
							span_notice("You finally release \the [src]."), \
							span_notice("You hear creaking metal."))
	qdel(src)

/obj/structure/vehiclecage/spacebike
	my_vehicle_type = /obj/vehicle/bike/random

/obj/structure/vehiclecage/quadbike
	my_vehicle_type = /obj/vehicle/train/engine/quadbike/random

/obj/structure/vehiclecage/quadtrailer
	my_vehicle_type = /obj/vehicle/train/trolley/trailer/random

/// LC-refs: my vehicle -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/vehiclecage/proc/my_vehicle() as /obj/vehicle
	return om_resolve(my_vehicle_handle)
