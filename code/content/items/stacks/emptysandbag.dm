// Empty bags. Yes, you need to fill them.

/obj/item/stack/emptysandbag
	name = "sandbag"
	desc = "Empty sandbags. You know what must be done."
	singular_name = "sandbag"
	icon = 'icons/obj/sandbags.dmi'
	icon_state = "sandbag_e"
	w_class = ITEMSIZE_LARGE

	strict_color_stacking = TRUE
	max_amount = 30
	stacktype = /obj/item/stack/emptysandbag

	pass_color = TRUE

	var/bag_material = MAT_CLOTH

/// A bag of a material that does not exist is discarded (keeps_if()).
/obj/item/stack/emptysandbag/proc/has_material()
	return !!get_material_by_name("[bag_material]")

/// It takes its material's colour (derives(), at init).
/obj/item/stack/emptysandbag/proc/material_colour()
	var/datum/material/M = get_material_by_name("[bag_material]")
	return M ? M.icon_colour : color

CAPABILITIES(/obj/item/stack/emptysandbag)
	keeps_if(PROC_REF(has_material))
	derives(nameof(color), PROC_REF(material_colour))
	without("ui_open")
	// A bag is filled each second while the user stays put; the series stops when the pile is gone or the ground is no longer outdoors.
	op("emptysandbag_self", in_hand(), label("Fill"), wait(1 SECOND, repeats = PROC_REF(fill_more), after_step = PROC_REF(fill_bag_done)))
	param(nameof(bag_material), pos = 2)

/// Another bag follows while there is a bag left and the ground is outdoors.
/obj/item/stack/emptysandbag/proc/fill_more(datum/act/op/A)
	return read_once(!QDELETED(src) && can_use(1) && istype(get_turf(src), /turf/simulated/floor/outdoors))

/// A bag filled: one used, one sandbag made where the pile lies.
/obj/item/stack/emptysandbag/proc/fill_bag_done(datum/act/op/A)
	if(!can_use(1) || !istype(get_turf(src), /turf/simulated/floor/outdoors))
		return
	var/mob/user = A.actor
	use(1)
	var/obj/item/stack/sandbags/SB = new (get_turf(src), 1, bag_material)
	SB.set_color(color)
	if(user)
		to_chat(user, span_notice("You fill a sandbag."))
