/obj/vehicle/boat
	name = "boat"
	desc = "It's a wooden boat. Looks like it'll hold two people. Oars not included."
	icon = 'icons/obj/vehicles_36x32.dmi'
	icon_state = "boat"
	max_integrity = 100
	charge_use = 0 // Boats use oars.
	pixel_x = -2
	move_delay = 3 // Rather slow, but still faster than swimming, and won't get you wet.
	max_buckled_mobs = 2
	anchored = FALSE
	var/tmp/datum/material/material_static
	var/riding_datum_type = /datum/riding/boat/small

TYPE_TABLE(/obj/vehicle/boat/sifwood, boat_forced_material, MAT_SIFWOOD)

/obj/vehicle/boat/dragon
	name = "dragon boat"
	desc = "It's a large wooden boat, carved to have a nordic-looking dragon on the front. Looks like it'll hold five people. Oars not included."
	icon = 'icons/obj/64x32.dmi'
	icon_state = "dragon_boat"
	max_integrity = 250
	pixel_x = -16
	max_buckled_mobs = 5
	riding_datum_type = /datum/riding/boat/big

/obj/vehicle/boat/dragon/build_of(material_name)
	..()
	var/image/I = image(icon, src, "dragon_boat_underlay", BELOW_MOB_LAYER)
	underlays += I

TYPE_TABLE(/obj/vehicle/boat/dragon/sifwood, boat_forced_material, MAT_SIFWOOD)

// Oars, which must be held inhand while in a boat to move it.
/obj/item/oar
	name = "oar"
	icon = 'icons/obj/vehicles.dmi'
	desc = "Used to provide propulsion to a boat."
	icon_state = "oar"
	item_state = "oar"
	force = 12
	var/tmp/datum/material/material_static

TYPE_TABLE(/obj/item/oar/sifwood, oar_forced_material, MAT_SIFWOOD)

TYPE_TABLE_DECLARE(/obj/item/oar, oar_forced_material, null)

CAPABILITIES(/obj/item/oar)
	param(nameof(oar_material), pos = 1, apply = PROC_REF(carve))

/// The material an oar is made of (its constructor param), or the type's forced one, or wood.
/obj/item/oar/var/oar_material

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/item/oar/proc/carve(material_name)
	var/forced_material = TYPE_TABLE_GET(src, oar_forced_material)
	if(forced_material)
		material_name = forced_material
	if(!material_name)
		material_name = MAT_WOOD
	material_static = get_material_by_name("[material_name]")
	if(!material())
		spent(src)
		return
	color = material().icon_colour

CAPABILITIES(/obj/vehicle/boat)
	owns_one(nameof(riding_datum), /datum/riding, starts = nameof(riding_datum_type))
	op("boat_board", item(/atom/movable), gesture(GESTURE_DRAG), label("Board"), then(PROC_REF(interaction_boat_board)))
	param(nameof(boat_material), pos = 1, apply = PROC_REF(build_of))

TYPE_TABLE_DECLARE(/obj/vehicle/boat, boat_forced_material, null)

/// The material a boat is built of (its constructor param), or the type's forced one, or wood.
/obj/vehicle/boat/var/boat_material

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/vehicle/boat/proc/build_of(material_name)
	var/forced_material = TYPE_TABLE_GET(src, boat_forced_material)
	if(forced_material)
		material_name = forced_material
	if(!material_name)
		material_name = MAT_WOOD
	material_static = get_material_by_name("[material_name]")
	if(!material())
		spent(src)
		return
	color = material().icon_colour

// Boarding.

/// Old MouseDrop_T: drop a mob on the boat to seat it.
/obj/vehicle/boat/proc/interaction_boat_board(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/C = A.held
	if(!ismob(C))
		return OP_DECLINE
	user_buckle_mob(C, user)
	return TRUE

/obj/vehicle/boat/load(mob/living/L, mob/living/user)
	if(!istype(L)) // Only mobs on boats.
		return FALSE
	..(L, user)

/// Accessor for a shared definition.
/obj/vehicle/boat/proc/material() as /datum/material
	return material_static

/// Accessor for a shared definition.
/obj/item/oar/proc/material() as /datum/material
	return material_static
