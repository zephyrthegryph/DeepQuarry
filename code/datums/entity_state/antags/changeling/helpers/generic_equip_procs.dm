//This is a generic proc that should be called by other ling armor procs to equip them.
/mob/proc/changeling_generic_armor(armor_type, helmet_type, boot_type, chem_cost)

	if(!ishuman(src))
		return 0

	var/mob/living/carbon/human/M = src

	if(istype(M.get_equipped_item(SLOT_ID_SUIT), armor_type) || istype(M.get_equipped_item(SLOT_ID_HEAD), helmet_type) || istype(M.get_equipped_item(SLOT_ID_SHOES), boot_type))
		chem_cost = 0

	var/datum/changeling/changeling = changeling_power(chem_cost, 1, 100, CONSCIOUS)

	if(!changeling)
		return

	//First, check if we're already wearing the armor, and if so, take it off.
	if(istype(M.get_equipped_item(SLOT_ID_SUIT), armor_type) || istype(M.get_equipped_item(SLOT_ID_HEAD), helmet_type) || istype(M.get_equipped_item(SLOT_ID_SHOES), boot_type))
		act_message(M, null, MSG_SELF(span_warning("We cast off our [M.get_equipped_item(SLOT_ID_SUIT).name]")), \
			MSG_OTHERS(span_warning("%U% casts off their [M.get_equipped_item(SLOT_ID_SUIT).name]!")), \
			MSG_BLIND(span_warningplain("You hear the organic matter ripping and tearing!")))
		if(istype(M.get_equipped_item(SLOT_ID_SUIT), armor_type))
			remove_from_mob(M.get_equipped_item(SLOT_ID_SUIT))
		if(istype(M.get_equipped_item(SLOT_ID_HEAD), helmet_type))
			remove_from_mob(M.get_equipped_item(SLOT_ID_HEAD))
		if(istype(M.get_equipped_item(SLOT_ID_SHOES), boot_type))
			remove_from_mob(M.get_equipped_item(SLOT_ID_SHOES))
		M.update_inv_wear_suit()
		M.update_inv_head()
		M.update_hair()
		M.update_inv_shoes()
		return 1

	if(M.get_equipped_item(SLOT_ID_HEAD) || M.get_equipped_item(SLOT_ID_SUIT)) //Make sure our slots aren't full
		to_chat(src, span_warning("We require nothing to be on our head, and we cannot wear any external suits, or shoes."))
		return 0

	var/obj/item/clothing/suit/A = new armor_type(src)
	equip_to_slot_or_del(A, SLOT_ID_SUIT)

	var/obj/item/clothing/suit/H = new helmet_type(src)
	equip_to_slot_or_del(H, SLOT_ID_HEAD)

	var/obj/item/clothing/shoes/B = new boot_type(src)
	equip_to_slot_or_del(B, SLOT_ID_SHOES)

	changeling.chem_charges -= chem_cost
	play_sfx(src, SFX_EFFECTS_BLOBATTACK)
	M.update_inv_wear_suit()
	M.update_inv_head()
	M.update_hair()
	M.update_inv_shoes()
	return 1

/mob/proc/changeling_generic_equip_all_slots(list/stuff_to_equip, cost)
	var/datum/changeling/changeling = changeling_power(cost,1,100,CONSCIOUS)
	if(!changeling)
		return

	if(!ishuman(src))
		return 0

	var/mob/living/carbon/human/M = src

	var/success = 0

	//First, check if we're already wearing the armor, and if so, take it off.

	if(changeling.armor_deployed)
		if(M.get_equipped_item(SLOT_ID_HEAD) && stuff_to_equip["head"])
			if(istype(M.get_equipped_item(SLOT_ID_HEAD), stuff_to_equip["head"]))
				M.slot_clear(SLOT_ID_HEAD)
				success = 1

		if(M.get_equipped_item(SLOT_ID_ID) && stuff_to_equip["wear_id"])
			if(istype(M.get_equipped_item(SLOT_ID_ID), stuff_to_equip["wear_id"]))
				M.slot_clear(SLOT_ID_ID)
				success = 1

		if(M.get_equipped_item(SLOT_ID_SUIT) && stuff_to_equip["wear_suit"])
			if(istype(M.get_equipped_item(SLOT_ID_SUIT), stuff_to_equip["wear_suit"]))
				M.slot_clear(SLOT_ID_SUIT)
				success = 1

		if(M.get_equipped_item(SLOT_ID_GLOVES) && stuff_to_equip["gloves"])
			if(istype(M.get_equipped_item(SLOT_ID_GLOVES), stuff_to_equip["gloves"]))
				M.slot_clear(SLOT_ID_GLOVES)
				success = 1
		if(M.get_equipped_item(SLOT_ID_SHOES) && stuff_to_equip["shoes"])
			if(istype(M.get_equipped_item(SLOT_ID_SHOES), stuff_to_equip["shoes"]))
				M.slot_clear(SLOT_ID_SHOES)
				success = 1

		if(M.get_equipped_item(SLOT_ID_BELT) && stuff_to_equip["belt"])
			if(istype(M.get_equipped_item(SLOT_ID_BELT), stuff_to_equip["belt"]))
				M.slot_clear(SLOT_ID_BELT)
				success = 1

		if(M.get_equipped_item(SLOT_ID_EYES) && stuff_to_equip["glasses"])
			if(istype(M.get_equipped_item(SLOT_ID_EYES), stuff_to_equip["glasses"]))
				M.slot_clear(SLOT_ID_EYES)
				success = 1

		if(M.get_equipped_item(SLOT_ID_MASK) && stuff_to_equip["wear_mask"])
			if(istype(M.get_equipped_item(SLOT_ID_MASK), stuff_to_equip["wear_mask"]))
				M.slot_clear(SLOT_ID_MASK)
				success = 1

		if(M.get_equipped_item(SLOT_ID_BACK) && stuff_to_equip["back"])
			if(istype(M.get_equipped_item(SLOT_ID_BACK), stuff_to_equip["back"]))
				for(var/atom/movable/AM in M.get_equipped_item(SLOT_ID_BACK).contents) //Dump whatever's in the bag before deleting.
					AM.forceMove(loc)
				M.slot_clear(SLOT_ID_BACK)
				success = 1

		if(M.get_equipped_item(SLOT_ID_UNIFORM) && stuff_to_equip["w_uniform"])
			if(istype(M.get_equipped_item(SLOT_ID_UNIFORM), stuff_to_equip["w_uniform"]))
				M.slot_clear(SLOT_ID_UNIFORM)
				success = 1

		if(success)
			play_sfx(src, SFX_EFFECTS_SPLAT, 0.6)
			act_message(src, null, MSG_SELF(span_notice("We remove and deform our equipment.")), \
				MSG_OTHERS(span_warning("%U% pulls on their clothes, peeling it off along with parts of their skin attached!")))
		changeling.armor_deployed = 0
		return success

	else

		to_chat(M, span_notice("We begin growing our new equipment..."))
		changeling_grow_piece(stuff_to_equip, 1, list())
		return 1

/// The pieces a changeling grows, in order: key in stuff_to_equip, slot id, slot, name, sound.
GLOBAL_LIST_INIT(changeling_grown_pieces, list(
	list("head", SLOT_ID_HEAD, SLOT_ID_HEAD, "a helmet", 'sound/effects/blobattack.ogg'),
	list("w_uniform", SLOT_ID_UNIFORM, SLOT_ID_UNIFORM, "a uniform", 'sound/effects/blobattack.ogg'),
	list("gloves", SLOT_ID_GLOVES, SLOT_ID_GLOVES, "some gloves", 'sound/effects/splat.ogg'),
	list("shoes", SLOT_ID_SHOES, SLOT_ID_SHOES, "shoes", 'sound/effects/splat.ogg'),
	list("belt", SLOT_ID_BELT, SLOT_ID_BELT, "a belt", 'sound/effects/splat.ogg'),
	list("glasses", SLOT_ID_EYES, SLOT_ID_EYES, "some glasses", 'sound/effects/splat.ogg'),
	list("wear_mask", SLOT_ID_MASK, SLOT_ID_MASK, "a mask", 'sound/effects/splat.ogg'),
	list("back", SLOT_ID_BACK, SLOT_ID_BACK, "a backpack", 'sound/effects/blobattack.ogg'),
	list("wear_suit", SLOT_ID_SUIT, SLOT_ID_SUIT, "an exosuit", 'sound/effects/blobattack.ogg'),
	list("wear_id", SLOT_ID_ID, SLOT_ID_ID, "an ID card", 'sound/effects/splat.ogg'),
))

/// Grows the next missing piece from `index` on, one a second, then reports.
/mob/proc/changeling_grow_piece(list/stuff_to_equip, index, list/grown_items_list)
	var/mob/living/carbon/human/M = src
	var/list/pieces = GLOB.changeling_grown_pieces
	for(var/i in index to length(pieces))
		var/list/piece = pieces[i]
		var/t = stuff_to_equip[piece[1]]
		if(M.get_equipped_item(piece[2]) || !t)
			continue
		var/I = new t
		M.equip_to_slot_or_del(I, piece[3])
		grown_items_list.Add(piece[4])
		playsound(src, piece[5], 30, 1)
		after(src, 1 SECOND, PROC_REF(changeling_grow_piece), with = list(stuff_to_equip, i + 1, grown_items_list))
		return

	var/feedback = english_list(grown_items_list, nothing_text = "nothing", and_text = " and ", comma_text = ", ", final_comma_text = "" )

	to_chat(M, span_notice("We have grown [feedback]."))

	var/datum/changeling/changeling = is_changeling(src)
	if(length(grown_items_list) && changeling)
		changeling.armor_deployed = 1
		changeling.chem_charges -= 10

//This is a generic proc that should be called by other ling weapon procs to equip them.
/mob/proc/changeling_generic_weapon(weapon_type, make_sound = 1, cost = 20)
	var/datum/changeling/changeling = changeling_power(cost,1,100,CONSCIOUS)
	if(!changeling)
		return

	if(!ishuman(src))
		return 0

	var/mob/living/carbon/human/M = src

	if(M.hands_are_full()) //Make sure our hands aren't full.
		to_chat(src, span_warning("Our hands are full.  Drop something first."))
		return 0

	var/obj/item/W = new weapon_type(src)
	src.put_in_hands(W)

	changeling.chem_charges -= cost
	if(make_sound)
		play_sfx(src, SFX_EFFECTS_BLOBATTACK)
	return 1
