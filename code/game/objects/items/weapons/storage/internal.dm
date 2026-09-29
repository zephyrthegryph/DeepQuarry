//A storage item intended to be used by other items to provide storage functionality.
//Types that use this should consider overriding emp_act() and hear_talk(), unless they shield their contents somehow.
/obj/item/storage/internal
	preserve_item = 1
	var/obj/item/master_item
	item_flags = ABSTRACT

/obj/item/storage/internal/Initialize(mapload)
	. = ..()
	rel_set(src, "master_item", loc)
	if(!istype(master_item(), /obj/item))
		return INITIALIZE_HINT_QDEL
	name = master_item().name

EXTEND_INTERACTIONS(/obj/item/storage/internal, INTERACT_HAND_UNGATED(null, TYPE_PROC_REF(/atom, interaction_swallow)))

/// Internal storage is part of its owner and is never worn on its own.
TYPE_TABLE(/obj/item/storage/internal, equip_spec, list(REQ_BECAUSE(REQ_TYPE(PRED_TARGET, list()), "it can't be worn")))

//Helper procs to cleanly implement internal storages - storage items that provide inventory slots for other items.
//These procs are completely optional, it is up to the master item to decide when it's storage get's opened by calling open()
//However they are helpful for allowing the master item to pretend it is a storage item itself.
//If you are using these you will probably want to override attackby() as well.
//See /obj/item/clothing/suit/storage for an example.

//items that use internal storage have the option of calling this to emulate default storage MouseDrop behaviour.
//returns 1 if the master item's parent's MouseDrop() should be called, 0 otherwise. It's strange, but no other way of
//doing it without the ability to call another proc's parent, really.
/obj/item/storage/internal/proc/handle_mousedrop(mob/user, obj/over_object)
	if (ishuman(user) || issmall(user)) //so monkeys can take off their backpacks -- Urist

		if (istype(user.loc,/obj/mecha)) // stops inventory actions in a mech
			return 0

		if(over_object == user && Adjacent(user)) // this must come before the screen objects only block
			src.open(user)
			return 0

		if (!( istype(over_object, /atom/movable/screen) ))
			return 1

		//makes sure master_item is equipped before putting it in hand, so that we can't drag it into our hand from miles away.
		//there's got to be a better way of doing this...
		if (!(master_item().loc == user) || (master_item().loc && master_item().loc.loc == user))
			return 0

		if (!( user.restrained() ) && !( user.stat ))
			switch(over_object.name)
				if("r_hand")
					user.unEquip(master_item())
					user.put_in_r_hand(master_item())
				if("l_hand")
					user.unEquip(master_item())
					user.put_in_l_hand(master_item())
			master_item().add_fingerprint(user)
			return 0
	return 0

//items that use internal storage have the option of calling this to emulate default storage attack_hand behaviour.
//returns 1 if the master item's parent's attack_hand() should be called, 0 otherwise.
//It's strange, but no other way of doing it without the ability to call another proc's parent, really.
/obj/item/storage/internal/proc/handle_attack_hand(mob/user)

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.get_equipped_item(SLOT_ID_POCKET_L) == master_item() && !H.get_active_hand())	//Prevents opening if it's in a pocket.
			H.put_in_hands(master_item())
			return 0
		if(H.get_equipped_item(SLOT_ID_POCKET_R) == master_item() && !H.get_active_hand())
			H.put_in_hands(master_item())
			return 0

	src.add_fingerprint(user)
	if (master_item().loc == user)
		src.open(user)
		return 0

	for(var/mob/M in range(1, master_item().loc))
		if (M.s_active == src)
			src.close(M)
	return 1

/obj/item/storage/internal/Adjacent(atom/neighbor)
	return master_item().Adjacent(neighbor)

/// Relation view: master item (reads null once it is gone).
/obj/item/storage/internal/proc/master_item() as /obj/item
	return master_item
