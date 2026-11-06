// The Magazine //
/obj/item/ammo_magazine/cell_mag
	name = "microbattery magazine"
	desc = "A microbattery holder for a cell-based variable weapon."
	icon = 'icons/obj/ammo_vr.dmi'
	icon_state = "cell_mag"
	caliber = "nsfw"
	ammo_type = /obj/item/ammo_casing/microbattery
	initial_ammo = 0
	max_ammo = 3
	var/x_offset = 5  //for the magazine look- moved here so it can be adjusted for bigger mags
	var/capname = "nsfw_mag" //as above
	var/chargename = "nsfw_mag" //as above
	mag_type = MAGAZINE

	var/list/modes

CAPABILITIES(/obj/item/ammo_magazine/cell_mag)
	op("cell_mag_load", item(/obj/item), priority(OP_PRIORITY_NORMAL + 1), label("Load"), then(PROC_REF(cell_mag_interaction_item)))

/// Old attackby. It never called ..(): any item stops here, but afterattack still follows.
/obj/item/ammo_magazine/cell_mag/proc/cell_mag_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	. = OP_PASS
	make_rounds_real()
	if(istype(W, /obj/item/ammo_casing/microbattery))
		var/obj/item/ammo_casing/microbattery/B = W
		if(!istype(B, ammo_type))
			to_chat(user, span_warning("[B] does not fit into [src]."))
			return
		if(length(stored_ammo) >= max_ammo)
			to_chat(user, span_warning("[src] is full!"))
			return
		if(!move_into(src, nameof(src.stored_ammo), B, user))
			return
	play_sfx(src, SFX_WEAPONS_FLIPBLADE)
	if(istype(loc, /obj/item/gun/projectile/cell_loaded)) // Update the HUD if we're in a gun + have a user. Not that one should be able to reload the mag while it's in a gun, but just in caaaaase.
		var/obj/item/gun/projectile/cell_loaded/cell_load = loc
		var/mob/living/M = cell_load.loc
		if(istype(M))
			M?.hud_used?.update_ammo_hud(M, cell_load)

/// The look: a cap and a charge light per battery, in the battery's colour.
/obj/item/ammo_magazine/cell_mag/draw(datum/look/look)
	..()
	var/current = 0
	for(var/obj/item/ammo_casing/microbattery/batt as anything in stored_ammo)
		look.overlay(look_overlay_image(icon, "[capname]_cap", pixel_x = current * x_offset, color = batt.type_color)) //Caps don't need a pixel_y offset
		if(batt.shots_left)
			var/ratio = CEILING(((batt.shots_left / initial(batt.shots_left)) * 4), 1) //4 is how many lights we have a sprite for
			look.overlay(look_overlay_image(icon, "[chargename]_charge-[ratio]", pixel_x = current * x_offset, color = "#29EAF4")) //Could use battery color but eh.
		current++ //Increment for offsets

/obj/item/ammo_magazine/cell_mag/advanced
	name = "advanced microbattery magazine"
	desc = "A microbattery holder for a cell-based variable weapon. This one has much more cell capacity!"
	max_ammo = 6
	x_offset = 3
	icon_state = "cell_mag_extended"
