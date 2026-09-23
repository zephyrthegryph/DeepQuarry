//This is a generic proc that should be called by other ling armor procs to equip them.
/mob/proc/changeling_generic_armor(armor_type, helmet_type, boot_type, chem_cost)

	if(!ishuman(src))
		return 0

	var/mob/living/carbon/human/M = src

	if(istype(M.get_equipped_item(SLOT_ID_WEAR_SUIT), armor_type) || istype(M.get_equipped_item(SLOT_ID_HEAD), helmet_type) || istype(M.get_equipped_item(SLOT_ID_SHOES), boot_type))
		chem_cost = 0

	var/datum/component/antag/changeling/changeling = changeling_power(chem_cost, 1, 100, CONSCIOUS)

	if(!changeling)
		return

	//First, check if we're already wearing the armor, and if so, take it off.
	if(istype(M.get_equipped_item(SLOT_ID_WEAR_SUIT), armor_type) || istype(M.get_equipped_item(SLOT_ID_HEAD), helmet_type) || istype(M.get_equipped_item(SLOT_ID_SHOES), boot_type))
		M.visible_message(span_warning("[M] casts off their [M.get_equipped_item(SLOT_ID_WEAR_SUIT).name]!"),
		span_warning("We cast off our [M.get_equipped_item(SLOT_ID_WEAR_SUIT).name]"),
		span_warningplain("You hear the organic matter ripping and tearing!"))
		if(istype(M.get_equipped_item(SLOT_ID_WEAR_SUIT), armor_type))
			remove_from_mob(M.get_equipped_item(SLOT_ID_WEAR_SUIT))
		if(istype(M.get_equipped_item(SLOT_ID_HEAD), helmet_type))
			remove_from_mob(M.get_equipped_item(SLOT_ID_HEAD))
		if(istype(M.get_equipped_item(SLOT_ID_SHOES), boot_type))
			remove_from_mob(M.get_equipped_item(SLOT_ID_SHOES))
		M.update_inv_wear_suit()
		M.update_inv_head()
		M.update_hair()
		M.update_inv_shoes()
		return 1

	if(M.get_equipped_item(SLOT_ID_HEAD) || M.get_equipped_item(SLOT_ID_WEAR_SUIT)) //Make sure our slots aren't full
		to_chat(src, span_warning("We require nothing to be on our head, and we cannot wear any external suits, or shoes."))
		return 0

	var/obj/item/clothing/suit/A = new armor_type(src)
	src.equip_to_slot_or_del(A, slot_wear_suit)

	var/obj/item/clothing/suit/H = new helmet_type(src)
	src.equip_to_slot_or_del(H, slot_head)

	var/obj/item/clothing/shoes/B = new boot_type(src)
	src.equip_to_slot_or_del(B, slot_shoes)

	changeling.chem_charges -= chem_cost
	playsound(src, 'sound/effects/blobattack.ogg', 30, 1)
	M.update_inv_wear_suit()
	M.update_inv_head()
	M.update_hair()
	M.update_inv_shoes()
	return 1

/mob/proc/changeling_generic_equip_all_slots(list/stuff_to_equip, cost)
	var/datum/component/antag/changeling/changeling = changeling_power(cost,1,100,CONSCIOUS)
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
				qdel(M.get_equipped_item(SLOT_ID_HEAD))
				success = 1

		if(M.get_equipped_item(SLOT_ID_WEAR_ID) && stuff_to_equip["wear_id"])
			if(istype(M.get_equipped_item(SLOT_ID_WEAR_ID), stuff_to_equip["wear_id"]))
				qdel(M.get_equipped_item(SLOT_ID_WEAR_ID))
				success = 1

		if(M.get_equipped_item(SLOT_ID_WEAR_SUIT) && stuff_to_equip["wear_suit"])
			if(istype(M.get_equipped_item(SLOT_ID_WEAR_SUIT), stuff_to_equip["wear_suit"]))
				qdel(M.get_equipped_item(SLOT_ID_WEAR_SUIT))
				success = 1

		if(M.get_equipped_item(SLOT_ID_GLOVES) && stuff_to_equip["gloves"])
			if(istype(M.get_equipped_item(SLOT_ID_GLOVES), stuff_to_equip["gloves"]))
				qdel(M.get_equipped_item(SLOT_ID_GLOVES))
				success = 1
		if(M.get_equipped_item(SLOT_ID_SHOES) && stuff_to_equip["shoes"])
			if(istype(M.get_equipped_item(SLOT_ID_SHOES), stuff_to_equip["shoes"]))
				qdel(M.get_equipped_item(SLOT_ID_SHOES))
				success = 1

		if(M.get_equipped_item(SLOT_ID_BELT) && stuff_to_equip["belt"])
			if(istype(M.get_equipped_item(SLOT_ID_BELT), stuff_to_equip["belt"]))
				qdel(M.get_equipped_item(SLOT_ID_BELT))
				success = 1

		if(M.get_equipped_item(SLOT_ID_GLASSES) && stuff_to_equip["glasses"])
			if(istype(M.get_equipped_item(SLOT_ID_GLASSES), stuff_to_equip["glasses"]))
				qdel(M.get_equipped_item(SLOT_ID_GLASSES))
				success = 1

		if(M.get_equipped_item(SLOT_ID_WEAR_MASK) && stuff_to_equip["wear_mask"])
			if(istype(M.get_equipped_item(SLOT_ID_WEAR_MASK), stuff_to_equip["wear_mask"]))
				qdel(M.get_equipped_item(SLOT_ID_WEAR_MASK))
				success = 1

		if(M.get_equipped_item(SLOT_ID_BACK) && stuff_to_equip["back"])
			if(istype(M.get_equipped_item(SLOT_ID_BACK), stuff_to_equip["back"]))
				for(var/atom/movable/AM in M.get_equipped_item(SLOT_ID_BACK).contents) //Dump whatever's in the bag before deleting.
					AM.forceMove(src.loc)
				qdel(M.get_equipped_item(SLOT_ID_BACK))
				success = 1

		if(M.get_equipped_item(SLOT_ID_W_UNIFORM) && stuff_to_equip["w_uniform"])
			if(istype(M.get_equipped_item(SLOT_ID_W_UNIFORM), stuff_to_equip["w_uniform"]))
				qdel(M.get_equipped_item(SLOT_ID_W_UNIFORM))
				success = 1

		if(success)
			playsound(src, 'sound/effects/splat.ogg', 30, 1)
			visible_message(span_warning("[src] pulls on their clothes, peeling it off along with parts of their skin attached!"),
			span_notice("We remove and deform our equipment."))
		changeling.armor_deployed = 0
		return success

	else

		to_chat(M, span_notice("We begin growing our new equipment..."))

		var/list/grown_items_list = list()

		var/t = stuff_to_equip["head"]
		if(!M.get_equipped_item(SLOT_ID_HEAD) && t)
			var/I = new t
			M.equip_to_slot_or_del(I, slot_head)
			grown_items_list.Add("a helmet")
			playsound(src, 'sound/effects/blobattack.ogg', 30, 1)
			success = 1
			sleep(1 SECOND)

		t = stuff_to_equip["w_uniform"]
		if(!M.get_equipped_item(SLOT_ID_W_UNIFORM) && t)
			var/I = new t
			M.equip_to_slot_or_del(I, slot_w_uniform)
			grown_items_list.Add("a uniform")
			playsound(src, 'sound/effects/blobattack.ogg', 30, 1)
			success = 1
			sleep(1 SECOND)

		t = stuff_to_equip["gloves"]
		if(!M.get_equipped_item(SLOT_ID_GLOVES) && t)
			var/I = new t
			M.equip_to_slot_or_del(I, slot_gloves)
			grown_items_list.Add("some gloves")
			playsound(src, 'sound/effects/splat.ogg', 30, 1)
			success = 1
			sleep(1 SECOND)

		t = stuff_to_equip["shoes"]
		if(!M.get_equipped_item(SLOT_ID_SHOES) && t)
			var/I = new t
			M.equip_to_slot_or_del(I, slot_shoes)
			grown_items_list.Add("shoes")
			playsound(src, 'sound/effects/splat.ogg', 30, 1)
			success = 1
			sleep(1 SECOND)

		t = stuff_to_equip["belt"]
		if(!M.get_equipped_item(SLOT_ID_BELT) && t)
			var/I = new t
			M.equip_to_slot_or_del(I, slot_belt)
			grown_items_list.Add("a belt")
			playsound(src, 'sound/effects/splat.ogg', 30, 1)
			success = 1
			sleep(1 SECOND)

		t = stuff_to_equip["glasses"]
		if(!M.get_equipped_item(SLOT_ID_GLASSES) && t)
			var/I = new t
			M.equip_to_slot_or_del(I, slot_glasses)
			grown_items_list.Add("some glasses")
			playsound(src, 'sound/effects/splat.ogg', 30, 1)
			success = 1
			sleep(1 SECOND)

		t = stuff_to_equip["wear_mask"]
		if(!M.get_equipped_item(SLOT_ID_WEAR_MASK) && t)
			var/I = new t
			M.equip_to_slot_or_del(I, slot_wear_mask)
			grown_items_list.Add("a mask")
			playsound(src, 'sound/effects/splat.ogg', 30, 1)
			success = 1
			sleep(1 SECOND)

		t = stuff_to_equip["back"]
		if(!M.get_equipped_item(SLOT_ID_BACK) && t)
			var/I = new t
			M.equip_to_slot_or_del(I, slot_back)
			grown_items_list.Add("a backpack")
			playsound(src, 'sound/effects/blobattack.ogg', 30, 1)
			success = 1
			sleep(1 SECOND)

		t = stuff_to_equip["wear_suit"]
		if(!M.get_equipped_item(SLOT_ID_WEAR_SUIT) && t)
			var/I = new t
			M.equip_to_slot_or_del(I, slot_wear_suit)
			grown_items_list.Add("an exosuit")
			playsound(src, 'sound/effects/blobattack.ogg', 30, 1)
			success = 1
			sleep(1 SECOND)

		t = stuff_to_equip["wear_id"]
		if(!M.get_equipped_item(SLOT_ID_WEAR_ID) && t)
			var/I = new t
			M.equip_to_slot_or_del(I, slot_wear_id)
			grown_items_list.Add("an ID card")
			playsound(src, 'sound/effects/splat.ogg', 30, 1)
			success = 1
			sleep(1 SECOND)

		var/feedback = english_list(grown_items_list, nothing_text = "nothing", and_text = " and ", comma_text = ", ", final_comma_text = "" )

		to_chat(M, span_notice("We have grown [feedback]."))

		if(success)
			changeling.armor_deployed = 1
			changeling.chem_charges -= 10
		return success

//This is a generic proc that should be called by other ling weapon procs to equip them.
/mob/proc/changeling_generic_weapon(weapon_type, make_sound = 1, cost = 20)
	var/datum/component/antag/changeling/changeling = changeling_power(cost,1,100,CONSCIOUS)
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
		playsound(src, 'sound/effects/blobattack.ogg', 30, 1)
	return 1
