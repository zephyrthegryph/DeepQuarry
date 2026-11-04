////////////////////////////////////////////////////////////////////////////////////////
//Gloves
/obj/item/clothing/gloves
	name = DEVELOPER_WARNING_NAME // "Gloves"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_gloves.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_gloves.dmi',
		)
	gender = PLURAL //Carn: for grammarically correct text-parsing
	w_class = ITEMSIZE_SMALL
	icon = 'icons/inventory/hands/item.dmi'
	blood_sprite_state = "bloodyhands"
	var/wired = 0
	var/obj/item/cell/cell = 0 // owned: the installed power cell, kept in the gloves' contents
	var/fingerprint_chance = 0					//How likely the glove is to let fingerprints through
	// owned: the ring worn under the gloves, kept in their contents
	var/obj/item/clothing/accessory/ring = null	//Covered ring
	// owned: the undergloves worn under gauntlets, kept in their contents
	var/obj/item/clothing/gloves/gloves = null	//Undergloves. Used for gauntlets.
	var/glove_level = 2							//What "layer" the glove is on
	var/overgloves = 0							//Used by gauntlets and arm_guards
	var/punch_force = 0							//How much damage do these gloves add to a punch?
	var/punch_injury_kind						//What punches in these gloves inflict (INJURY_*); null = the punch's own kind.
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/hands/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/hands/mob_vox.dmi'
		)

	valid_accessory_slots = (\
		ACCESSORY_SLOT_RING\
		|ACCESSORY_SLOT_WRIST)
	restricted_accessory_slots = (\
		ACCESSORY_SLOT_RING\
		|ACCESSORY_SLOT_WRIST)

CAPABILITIES(/obj/item/clothing/gloves)
	configure(item_worn(covers = HANDS, slots = SLOT_GLOVES))
	configure(item_combat(attack_verbs = list("challenged")))
	configure(item_protection(siemens = 0.9, heat_parts = HANDS, cold_parts = HANDS))
	configure(item_sounds(drop = SFX_ITEMS_DROP_GLOVES, pickup = SFX_ITEMS_PICKUP_GLOVES))
	owns_one(nameof(gloves), /obj/item/clothing/gloves)
	owns_one(nameof(ring), /obj/item/clothing/accessory)
	owns_one(nameof(special_attack), /datum/unarmed_attack, starts = nameof(special_attack_type))
	owns_one(nameof(contents), on_destroy = ON_DESTROY_SPILL)
	owns_one(nameof(cell), on_destroy = ON_DESTROY_CONTAINED)

// Called just before an attack_hand(), in mob/UnarmedAttack()
/obj/item/clothing/gloves/proc/Touch(atom/A, proximity, stance = I_HURT, mob/user)
	return 0 // return 1 to cancel attack_hand()

/obj/item/clothing/gloves/wash()
	. = ..()
	transfer_blood = 0

/obj/item/clothing/gloves/equipped(mob/user, slot)
	rel_set(src, nameof(wearer), user)
	return ..()

/obj/item/clothing/gloves/dropped(mob/user, equipping, slot)
	..()

	punch_force = initial(punch_force)
	rel_clear(src, nameof(wearer))
	if(!ishuman(user))
		return
	var/mob/living/carbon/human/H = user

	//Equipping to our glove slot? Cover our former gloves, if applicable.
	if(equipping && slot && slot == SLOT_ID_GLOVES)
		var/obj/item/clothing/G = H.get_equipped_item(SLOT_ID_GLOVES)
		if(istype(G))
			to_chat(user, "You slip \the [src] on over \the [H.get_equipped_item(SLOT_ID_GLOVES)].")
			if(istype(G, /obj/item/clothing/gloves))
				rel_set(src, nameof(gloves), H.get_equipped_item(SLOT_ID_GLOVES))
			else if(istype(G, /obj/item/clothing/accessory))
				rel_set(src, nameof(ring), H.get_equipped_item(SLOT_ID_GLOVES))
			else
				rel_set(src, nameof(gloves), H.get_equipped_item(SLOT_ID_GLOVES)) //Fallback
			H.unEquip(H.get_equipped_item(SLOT_ID_GLOVES), TRUE, src)
			if(!(flags & THICKMATERIAL))
				if(istype(G, /obj/item/clothing/gloves) || istype(G, /obj/item/clothing/accessory)) //Because sometimes you can wear non-glove items on your hands.
					punch_force += ring.punch_force
		return

	//Taking our gloves off? Put our former gloves / ring on.
	if(gloves)
		if(!H.equip_to_slot_if_possible(gloves, SLOT_ID_GLOVES))
			gloves.forceMove(get_turf(src))
		rel_take(src, nameof(gloves))
		return

	if(ring) //We do NOT have gloves under our gloves but have a ring under our glove instead!
		if(!H.equip_to_slot_if_possible(ring, SLOT_ID_GLOVES))
			ring.forceMove(get_turf(src))
		rel_take(src, nameof(ring))
		return

/obj/item/clothing/gloves
	var/tmp/datum/unarmed_attack/special_attack = null //do the gloves have a special unarmed attack?
	var/special_attack_type = null

/////////////////////////////////////////////////////////////////////
//Rings

/obj/item/clothing/gloves/ring
	name = DEVELOPER_WARNING_NAME // "ring"
	w_class = ITEMSIZE_TINY
	icon = 'icons/inventory/hands/item.dmi'
	gender = NEUTER
	glove_level = 1
	fingerprint_chance = 100
	punch_force = 2

CAPABILITIES(/obj/item/clothing/gloves/ring)
	fits_as(FIT_NO_DIONA)
	configure(item_worn(covers = 0))
	configure(item_protection(siemens = 1))
	configure(item_sounds(drop = SFX_ITEMS_DROP_RING, pickup = SFX_ITEMS_PICKUP_RING))

/obj/item/clothing/gloves
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/hands/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/hands/mob_vox.dmi',
		SPECIES_WEREBEAST = 'icons/inventory/hands/mob_werebeast.dmi')
