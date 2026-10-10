

/obj/mecha
	// Show the pilot.
	var/show_pilot = FALSE

	// The state of the 'face', or the thing that overlays on the pilot. If this isn't set, it will probably look really weird.
	var/face_state = null
	// How many pixels do we bump the pilot upward?
	var/pilot_lift = 0

/obj/mecha/update_transform()
	// Now for the regular stuff.
	var/matrix/M = matrix()
	M.Scale(icon_scale_x, icon_scale_y)
	M.Translate(0, 16*(icon_scale_y-1))
	animate(src, transform = M, time = 10)
	return

/// The state of the mech's own sprite: its type's, or the one a paint kit gave it.
/obj/mecha/proc/mecha_base_state()
	return initial_icon ? initial_icon : initial(icon_state)

/// The pilot as the mech shows it (its four faces, cut by the mech's own cutter mask), or null for a pilot that is not drawn (a brain).
/obj/mecha/proc/pilot_picture(mob/living/carbon/pilot)
	if(istype(pilot, /mob/living/carbon/brain))
		return null
	var/icon/picture = getCompoundIcon(pilot)
	if(icon_exists(icon, "[mecha_base_state()]_cutter"))
		picture.Blend(icon(icon, "[mecha_base_state()]_cutter"), ICON_MULTIPLY, y = (-1 * pilot_lift))
	return picture

/// The mech with or without a pilot (its open state when empty), the pilot a paint kit made visible, its face and what is bolted on.
/obj/mecha/draw(datum/look/look)
	..()
	var/base = mecha_base_state()
	var/occupied
	if(show_pilot)
		for(var/mob/living/carbon/pilot in look.things_in(src, MECHA_SLOT_PILOT, /mob/living/carbon))
			occupied = TRUE
			var/icon/picture = pilot_picture(pilot)
			if(picture)
				look.overlay(look_overlay_image(picture, null, pixel_y = pilot_lift))
			break
	else
		occupied = length(look.contents_of(src, MECHA_SLOT_PILOT, /mob/living/carbon)) > 0
	look.state(occupied ? base : "[base]-open")
	look.overlay(face_state, face_state)
	for(var/obj/item/mecha_parts/mecha_equipment/ME in equipment)
		ME.equip_look(look)

TRACKED(/obj/mecha, show_pilot)
TRACKED(/obj/mecha, face_state)
TRACKED(/obj/mecha, pilot_lift)
TRACKED(/obj/mecha, initial_icon)
