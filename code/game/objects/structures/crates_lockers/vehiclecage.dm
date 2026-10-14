/obj/structure/vehiclecage
	name = "vehicle cage"
	desc = "A large metal lattice that seems to exist solely to annoy consumers."
	icon = 'icons/obj/storage.dmi'
	icon_state = "vehicle_cage"
	density = TRUE
	var/obj/vehicle/my_vehicle
	var/my_vehicle_type
	var/paint_color = "#666666"

TRACKED(/obj/structure/vehiclecage, paint_color)

// C11: one slot for the caged vehicle. No custom Destroy() overrides the
// base /atom/movable one, so the default spill policy (not SLOT_DROP_HOLDER)
// is correct here: disassemble() already moves the vehicle out before
// qdel(src), so the slot is empty by then, but any other qdel path needs the
// generic drop-policy pass to actually place the vehicle instead of losing it.
/datum/relation_definition/slot/vehicle_cage
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
		for(var/obj/I in get_turf(src))
			if(I.density || I.anchored || I == src || !I.simulated || !istype(I, my_vehicle_type))
				continue
			load_vehicle(I)

MSG_DEF(vehiclecage/unbolting, "You begin loosening %T%'s bolts.", "%U% begins loosening %T%'s bolts.")
MSG_DEF(vehiclecage/cutting, "You begin cutting %T%'s bolts.", "%U% begins cutting %T%'s bolts.")

CAPABILITIES(/obj/structure/vehiclecage)
	owns_one(nameof(my_vehicle), /obj/vehicle, starts = nameof(my_vehicle_type), on_destroy = ON_DESTROY_SPILL) // a cage destroyed any other way than taken apart puts its vehicle out
	op("unbolt", tool(TOOL_WRENCH), label("Take apart"), wait(6 SECONDS), begins(MSG(vehiclecage/unbolting)), then(PROC_REF(taken_apart)))
	op("cut_bolts", tool(TOOL_WIRECUTTER), label("Cut apart"), wait(7 SECONDS), begins(MSG(vehiclecage/cutting)), then(PROC_REF(taken_apart)))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("drag", item(/atom/movable), gesture(GESTURE_DRAG), label("Load vehicle"), then(PROC_REF(interaction_drag)))

/obj/structure/vehiclecage/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You need a wrench to take this apart!"))
	return TRUE

/// The wrench or the cutters, after their wait: the cage comes apart.
/obj/structure/vehiclecage/proc/taken_apart(datum/act/op/A)
	disassemble(A.held, A.actor)
	return OP_OK

/// The cage's frame in the vehicle's paint, and the caged vehicle shown behind it.
/obj/structure/vehiclecage/draw(datum/look/look)
	..()
	look.overlay(look_overlay_image('icons/obj/storage.dmi', "[initial(icon_state)]_a", layer = MOB_LAYER + 1.1, plane = MOB_PLANE, color = paint_color))
	for(var/obj/vehicle/V as anything in look.things_in(src, CONTAINER_SLOT_VEHICLE_CAGE, /obj/vehicle))
		look.show_copy_of(V, layer = layer - 0.1)

/obj/structure/vehiclecage/proc/interaction_drag(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/C = A.held
	if(user && (user?.buckled_to() || user.stat || user.restrained() || !Adjacent(user) || !user.Adjacent(C)))
		return OP_PASS

	var/obj/vehicle/V
	if(istype(C, /obj/vehicle))
		V = C
	if(!V)
		return OP_PASS

	if(!my_vehicle())
		load_vehicle(V, user)
	return OP_PASS

/obj/structure/vehiclecage/proc/load_vehicle(obj/vehicle/V, mob/user as mob)
	if(user)
		act_message(user, V, MSG_SELF(span_notice("You load %T% into \the [src].")), \
			MSG_OTHERS(span_notice("%U% loads %T% into \the [src].")), \
			MSG_BLIND(span_notice("You hear creaking metal.")))

	V.forceMove(src)

	set_paint_color(V.paint_color)

/obj/structure/vehiclecage/proc/disassemble(obj/item/W as obj, mob/user as mob)
	var/turf/T = get_turf(src)
	new /obj/item/stack/material/steel(src.loc, 5)

	for(var/atom/movable/AM in slot_contents(CONTAINER_SLOT_VEHICLE_CAGE))
		if(AM.simulated)
			AM.forceMove(T)

	rel_take(src, nameof(my_vehicle)) // released, not deleted: it was moved out above
	act_message(user, src, MSG_SELF(span_notice("You finally release %T%.")), \
		MSG_OTHERS(span_notice("%U% release %T%.")), \
		MSG_BLIND(span_notice("You hear creaking metal.")))
	consume(src, user)

/obj/structure/vehiclecage/spacebike
	my_vehicle_type = /obj/vehicle/bike/random

/obj/structure/vehiclecage/quadbike
	my_vehicle_type = /obj/vehicle/train/engine/quadbike/random

/obj/structure/vehiclecage/quadtrailer
	my_vehicle_type = /obj/vehicle/train/trolley/trailer/random

/// Relation view: my vehicle (reads null once it is gone).
/obj/structure/vehiclecage/proc/my_vehicle() as /obj/vehicle
	return my_vehicle
