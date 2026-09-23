/obj/item/clothing/shoes/magboots
	desc = "Magnetic boots, often used during extravehicular activity to ensure the user remains safely attached to the vehicle. They're large enough to be worn over other footwear."
	name = "magboots"
	icon_state = "magboots0"
	flags = PHORONGUARD
	item_state_slots = list(slot_r_hand_str = "magboots", slot_l_hand_str = "magboots")
	center_of_mass_x = 17
	center_of_mass_y = 12
	force = 3
	overshoes = 1
	shoes_under_pants = -1	//These things are huge
	preserve_item = 1
	var/magpulse = 0
	var/icon_base = "magboots"
	///The message that gets shown when we enable the magboots.
	var/mag_enable = "You enable the mag-pulse traction system."
	///The message that gets shown when we disable the magboots.
	var/mag_disable = "You disable the mag-pulse traction system."
	///If the magboots can be removed when enabled or not.
	var/unremovable_when_enabled = FALSE
	actions_types = list(/datum/action/item_action/toggle_magboots)
	step_volume_mod = 1.3
	drop_sound = 'sound/items/drop/metalboots.ogg'
	pickup_sound = 'sound/items/pickup/toolbox.ogg'
	resistance_flags = FIRE_PROOF

/obj/item/clothing/shoes/magboots/fit_constraint()
	return null

/obj/item/clothing/shoes/magboots/proc/set_slowdown()
	slowdown = shoes? max(SHOES_SLOWDOWN, shoes.slowdown): SHOES_SLOWDOWN	//So you can't put on magboots to make you walk faster.
	if (magpulse)
		slowdown += 3

/obj/item/clothing/shoes/magboots/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(magpulse)
		item_flags &= ~NOSLIP
		magpulse = FALSE
		set_slowdown()
		force = 3
		if(icon_base) icon_state = "[icon_base]0"
		to_chat(user, mag_disable)
		if(unremovable_when_enabled)
			canremove = TRUE
	else
		//Checks to ensure if they're unremovable we're actually wearing them when we turn them on.
		if(unremovable_when_enabled)
			if(!ishuman(user))
				return
			var/mob/living/carbon/human/H = user
			if(H.get_equipped_item(SLOT_ID_SHOES) != src)
				to_chat(user, "You will have to put on the [src] before you can do that.")
				return
			canremove = FALSE

		item_flags |= NOSLIP
		magpulse = TRUE
		set_slowdown()
		force = 5
		if(icon_base) icon_state = "[icon_base]1"
		playsound(src, 'sound/effects/magnetclamp.ogg', 20)
		to_chat(user, mag_enable)
	user.update_inv_shoes()	//so our mob-overlays update
	user.update_mob_action_buttons()

/obj/item/clothing/shoes/magboots/equip_constraint()
	return dq_spec_join(..(), list(REQ_ON(PRED_TARGET, /obj/item/clothing/shoes/magboots/proc/overshoe_clearance, null)))

/// Magboots go on over shoes, but not over other overshoes.
/obj/item/clothing/shoes/magboots/proc/overshoe_clearance(mob/living/carbon/human/H)
	if(!istype(H) || !istype(H.get_equipped_item(SLOT_ID_SHOES), /obj/item/clothing/shoes))
		return TRUE
	var/obj/item/clothing/shoes/worn = H.get_equipped_item(SLOT_ID_SHOES)
	return worn.overshoes ? "\the [worn] are in the way" : TRUE

/obj/item/clothing/shoes/magboots/equipped(mob/user, slot)

	var/mob/living/carbon/human/H = user
	if(slot && slot != slot_shoes)
		return ..()
	set_slowdown()
	wearer = WEAKREF(H)
	..()

/obj/item/clothing/shoes/magboots/dropped(mob/user, equipping, slot)
	..()
	wearer = null

	var/mob/living/carbon/human/H = user
	if(!ishuman(H))
		return

	//Equipping shoes. If you put it so you can put your shoes somewhere BUT your shoe slot, make sure this shit works.
	if(equipping && (slot == slot_shoes))
		if(H.get_equipped_item(SLOT_ID_SHOES) && H.get_equipped_item(SLOT_ID_SHOES) != src)
			shoes = H.get_equipped_item(SLOT_ID_SHOES)
			H.unEquip(shoes, TRUE, src)
			to_chat(user, "You slip \the [src] on over \the [shoes].")
		return

	if(shoes)
		if(!H.equip_to_slot_if_possible(shoes, slot_shoes, FALSE, TRUE, TRUE, TRUE))
			shoes.forceMove(get_turf(src))
		shoes = null

/obj/item/clothing/shoes/magboots/examine(mob/user)
	. = ..()
	. += "Its mag-pulse traction system appears to be [item_flags & NOSLIP ? "enabled" : "disabled"]."

/obj/item/clothing/shoes/magboots/vox

	desc = "A pair of heavy, jagged armoured foot pieces, seemingly suitable for a velociraptor."
	name = "vox magclaws"
	item_state = "boots-vox"
	icon_state = "boots-vox"
	icon_base = null
	mag_enable = "You dig your claws deeply into the flooring, bracing yourself."
	mag_disable = "You relax your deathgrip on the flooring."
	unremovable_when_enabled = TRUE
	flags = PHORONGUARD
	armor_spec = "melee=40;bullet=10;laser=10;energy=20;bomb=20;bio=10;rad=20" // values of workboots and heavy duty engineering gloves, it's the only option that will ever be taken so may as well give the turkeys some protection //

	actions_types = list(/datum/action/item_action/toggle_magclaws)

/obj/item/clothing/shoes/magboots/vox/fit_constraint()
	var/list/bodytypes = list(SPECIES_VOX)
	return list(REQ_FITS_BODYTYPES(bodytypes))

/obj/item/clothing/shoes/magboots/vox/set_slowdown()
	return //voxboots suffer no slowdown penalties!

//In case they somehow come off while enabled.
/obj/item/clothing/shoes/magboots/vox/dropped(mob/user, equipping, slot)
	..()
	if(magpulse)
		user.visible_message("The [src] go limp as they are removed from [user]'s feet.", "The [src] go limp as they are removed from your feet.")
		item_flags &= ~NOSLIP
		magpulse = FALSE
		canremove = TRUE

/obj/item/clothing/shoes/magboots/vox/examine(mob/user)
	. = ..()
	if(magpulse)
		. += "It would be hard to take these off without relaxing your grip first." // Theoretically this message should only be seen by the wearer when the claws are equipped.
