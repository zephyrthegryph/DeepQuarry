/obj/item/clothing/proc/can_attach_accessory(obj/item/clothing/accessory/A)
	//Just no, okay
	if(!istype(A) || !A.slot)
		return FALSE

	//Not valid at all, not in the valid list period.
	if((valid_accessory_slots & A.slot) != A.slot)
		return FALSE

	//Find all consumed slots
	var/consumed_slots = 0
	for(var/obj/item/clothing/accessory/AC as anything in accessories)
		consumed_slots |= AC.slot

	//Mask to just consumed restricted
	var/consumed_restricted = restricted_accessory_slots & consumed_slots

	//They share at least one bit with the restricted slots
	if(consumed_restricted & A.slot)
		return FALSE

	return TRUE

EXTEND_INTERACTIONS(/obj/item/clothing, \
	INTERACT_ITEM(null, PROC_REF(clothing_accessory_item)), \
	INTERACT_HAND_UNGATED(null, PROC_REF(clothing_accessory_hand)), \
	INTERACT_ALT(null, PROC_REF(clothing_remove_accessory_alt)), \
	INTERACT_SELF(null, PROC_REF(clothing_circuit_self)), \
)

/// Old attackby: attach an accessory, or forward the item to the attached accessories.
/obj/item/clothing/proc/clothing_accessory_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/clothing/accessory))
		var/obj/item/clothing/accessory/A = I
		if(attempt_attach_accessory(A, user))
			return INTERACTION_HANDLED_PASS

	if(LAZYLEN(accessories))
		for(var/obj/item/clothing/accessory/A in accessories)
			A.attackby(I, user)
		return INTERACTION_HANDLED_PASS

	return FALSE

/// Old attack_hand: forward to the attached accessories while worn.
/obj/item/clothing/proc/clothing_accessory_hand(mob/user, obj/item/held, datum/interaction/interaction)
	//only forward to the attached accessory if the clothing is equipped (not in a storage)
	if(LAZYLEN(accessories) && src.loc == user)
		for(var/obj/item/clothing/accessory/A in accessories)
			A.attack_hand(user)
		return TRUE
	if (ishuman(user) && src.loc == user)
		var/mob/living/carbon/human/H = user
		if(src == H.get_equipped_item(SLOT_ID_UNIFORM)) // Un-equip on single click, but not on uniform.
			return TRUE
	return FALSE

/obj/item/clothing/MouseDrop(obj/over_object)
	if (over_object && (ishuman(usr) || issmall(usr)))
		//makes sure that the clothing is equipped so that we can't drag it into our hand from miles away.
		if (!(src.loc == usr))
			return

		if (( usr.restrained() ) || ( usr.stat ))
			return

		if (!usr.unEquip(src))
			return

		switch(over_object.name)
			if("r_hand")
				usr.put_in_r_hand(src)
			if("l_hand")
				usr.put_in_l_hand(src)
		src.add_fingerprint(usr)

/obj/item/clothing/examine(mob/user)
	. = ..(user)
	if(LAZYLEN(accessories))
		. += "It has the following attached: [counting_english_list(user.client, accessories)]"

/**
 *  Attach accessory A to src
 *
 *  user is the user doing the attaching. Can be null, such as when attaching
 *  items on spawn
 */
/obj/item/clothing/proc/attempt_attach_accessory(obj/item/clothing/accessory/A, mob/user)
	if(!valid_accessory_slots)
		if(user)
			to_chat(user, span_warning("You cannot attach accessories of any kind to \the [src]."))
		return FALSE

	var/obj/item/clothing/accessory/acc = A
	if(can_attach_accessory(acc))
		if(user)
			user.remove_from_mob(acc)
		attach_accessory(user, acc)
		return TRUE
	else
		if(user)
			to_chat(user, span_warning("You cannot attach more accessories of this type to [src]."))
		return FALSE


/obj/item/clothing/proc/attach_accessory(mob/user, obj/item/clothing/accessory/A)
	own_add(src, "accessories", A)
	A.on_attached(src, user)
	src.verbs |= /obj/item/clothing/proc/removetie_verb
	update_accessory_slowdown()
	update_clothing_icon()
	worn_protection_changed()

/obj/item/clothing/proc/remove_accessory(mob/user, obj/item/clothing/accessory/A)
	if(!LAZYLEN(accessories) || !(A in accessories))
		return

	A.on_removed(user)
	own_take_member(src, "accessories", A)
	update_accessory_slowdown()
	update_clothing_icon()
	worn_protection_changed()

/obj/item/clothing/proc/update_accessory_slowdown()
	slowdown = initial(slowdown)
	for(var/obj/item/clothing/accessory/A in accessories)
		slowdown += A.slowdown

/obj/item/clothing/proc/removetie_verb()
	set name = "Remove Accessory"
	set category = VERB_CAT_OBJECT
	set src in usr

	removetie_proc(usr)

/obj/item/clothing/proc/removetie_proc(mob/living/user)

	if(!isliving(user))
		return

	if(user.stat)
		return

	// begin
	if(iscarbon(user))
		var/mob/living/carbon/C = user
		if(C.get_equipped_item(SLOT_ID_HANDCUFFED))
			to_chat(C, span_warning("You cannot remove accessories while handcuffed!"))
			return
		else if(istype(C, /mob/living/carbon/human))
			var/mob/living/carbon/human/H = C
			if(H.ability_flags & 0x1)
				to_chat(H, span_warning("You cannot remove accessories while phase shifted!"))
				return
	// end

	var/obj/item/clothing/accessory/A
	var/accessory_amount = LAZYLEN(accessories)
	if(accessory_amount)
		if(accessory_amount == 1)
			A = accessories[1] // If there's only one accessory, just remove it without any additional prompts.
		else
			var/_answer_a1 = rerun_ask(user, "a1", PROC_REF(removetie_proc), args, /datum/om/prompt/choice, message = "Select an accessory to remove from \the [src]", title = "Accessory Choice", choices = accessories)
			if(isnull(_answer_a1))
				return
			A = _answer_a1

	if(A)
		if(A.can_remove)
			remove_accessory(user,A)
		else
			to_chat(user, span_warning("It doesn't look like \the [A] can be taken off \the [src]."))


	if(!LAZYLEN(accessories))
		src.verbs -= /obj/item/clothing/proc/removetie_verb
		own_take_all(src, "accessories")
