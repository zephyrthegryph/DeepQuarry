///////////////////////////////////////////////////////////////////////
// Ears: headsets, earmuffs and tiny objects
/obj/item/clothing/ears
	name = "ears"
	w_class = ITEMSIZE_TINY
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/ears/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/ears/mob_vox.dmi',
		SPECIES_WEREBEAST = 'icons/inventory/ears/mob_werebeast.dmi')

CAPABILITIES(/obj/item/clothing/ears)
	configure(item_worn(slots = SLOT_EARS))
	configure(item_thrown(force = 2))
	op("ears_take_off_hand", hand(), then(PROC_REF(ears_take_off_hand)))

/// Old attack_hand: take worn ears off into the hand.
/obj/item/clothing/ears/proc/ears_take_off_hand(datum/act/op/A)
	var/mob/user = A.actor
	if (!user) return OP_DECLINE

	if (src.loc != user || !ishuman(user))
		return OP_DECLINE

	var/mob/living/carbon/human/H = user
	if(H.get_equipped_item(SLOT_ID_EAR_L) != src && H.get_equipped_item(SLOT_ID_EAR_R) != src)
		return OP_DECLINE

	if(!canremove)
		return TRUE

	var/obj/item/clothing/ears/O
	if(HAS_TAG(src, TAG_WEAR_TWO_EARS))
		O = (H.get_equipped_item(SLOT_ID_EAR_L) == src ? H.get_equipped_item(SLOT_ID_EAR_R) : H.get_equipped_item(SLOT_ID_EAR_L))
		user.drop_from_inventory(O)
		if(!istype(src,/obj/item/clothing/ears/offear))
			spent(O)
			O = src
	else
		O = src

	user.unEquip(src)

	if (O)
		user.put_in_hands(O)
		O.add_fingerprint(user)

	if(istype(src,/obj/item/clothing/ears/offear))
		consume(src, user)
	return TRUE

/obj/item/clothing/ears/drop_with_actor(mob/user, obj/over_object)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		// If this covers both ears, we want to return the result of unequipping the primary object, and kill the off-ear one
		if(HAS_TAG(src, TAG_WEAR_TWO_EARS))
			var/obj/item/clothing/ears/O = (H.get_equipped_item(SLOT_ID_EAR_L) == src ? H.get_equipped_item(SLOT_ID_EAR_R) : H.get_equipped_item(SLOT_ID_EAR_L))
			if(istype(src, /obj/item/clothing/ears/offear))
				. = O.drop_with_actor(user, over_object)
				consume(src, H)
			else
				. = ..(user, over_object)
				consume(O, H)
		else
			. = ..(user, over_object)
