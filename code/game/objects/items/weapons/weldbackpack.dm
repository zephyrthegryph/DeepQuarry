/obj/item/weldpack
	name = "Welding kit"
	desc = "A heavy-duty, portable welding fluid carrier."
	slot_flags = SLOT_BACK
	icon = 'icons/obj/storage.dmi'
	icon_state = "welderpack"
	w_class = ITEMSIZE_LARGE
	var/max_fuel = 350
	var/obj/item/nozzle = null //Attached welder, or other spray device.
	var/nozzle_type = /obj/item/weldingtool/tubefed
	var/nozzle_attached = 0
	drop_sound = SFX_ITEMS_DROP_BACKPACK
	pickup_sound = SFX_ITEMS_PICKUP_BACKPACK

CAPABILITIES(/obj/item/weldpack)
	owns_one(nameof(nozzle), /obj/item, starts = nameof(nozzle_type))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	drag_onto(PROC_REF(mousedrop_input))

/obj/item/weldpack/Initialize(mapload)
	. = ..()
	var/datum/reagents/R = new/datum/reagents(max_fuel) //Lotsa refills
	rel_set(src, nameof(reagents), R)
	rel_set(R, nameof(R.my_atom), src)
	R.add_reagent(REAGENT_ID_FUEL, max_fuel)
	nozzle_attached = 1


/obj/item/weldpack/dropped(mob/user, equipping, slot)
	..()
	if(nozzle)
		user.remove_from_mob(nozzle)
		return_nozzle()
		to_chat(user, span_notice("\The [nozzle] retracts to its fueltank."))

/obj/item/weldpack/proc/get_nozzle(mob/living/user)
	if(!ishuman(user))
		return 0

	var/mob/living/carbon/human/H = user

	if(H.hands_are_full()) //Make sure our hands aren't full.
		to_chat(H, span_warning("Your hands are full.  Drop something first."))
		return 0

	var/obj/item/F = nozzle
	H.put_in_hands(F)
	nozzle_attached = 0 // out of the pack: the nozzle's burner_active() declaration starts its work

	return 1

/obj/item/weldpack/proc/return_nozzle(mob/living/user)
	nozzle.forceMove(src) // back in the pack: the declaration stops the nozzle's work
	nozzle_attached = 1

/// Old attackby.
/obj/item/weldpack/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	var/obj/item/weldingtool/T = W.get_welder()
	if(T && !(W == nozzle))
		if(T.welding && prob(50))
			message_admins("[key_name_admin(user)] triggered a fueltank explosion.")
			log_game("[key_name(user)] triggered a fueltank explosion.")
			to_chat(user, span_danger("That was stupid of you."))
			explosion(get_turf(src),-1,0,2)
			if(src)
				consume(src, user)
			return OP_PASS
		else if(T.status)
			if(T.welding)
				to_chat(user, span_danger("That was close!"))
			src.reagents.trans_to_obj(T, T.max_fuel)
			to_chat(user, span_notice("Welder refilled!"))
			play_sfx(src, SFX_EFFECTS_REFILL)
			return OP_PASS
	else if(nozzle)
		if(nozzle == W)
			if(!user.unEquip(W))
				to_chat(user, span_notice("\The [W] seems to be stuck to your hand."))
				return OP_PASS
			if(!nozzle_attached)
				return_nozzle()
				to_chat(user, span_notice("You attach \the [W] to the [src]."))
				return OP_PASS
		else
			to_chat(user, span_notice("The [src] already has a nozzle!"))
	else
		to_chat(user, span_warning("The tank scoffs at your insolence. It only provides services to welders."))
	return OP_PASS

/// Old attack_hand.
/obj/item/weldpack/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(ishuman(user))
		var/mob/living/carbon/human/wearer = user
		if(wearer.get_equipped_item(SLOT_ID_BACK) == src)
			if(nozzle && nozzle_attached)
				if(!wearer.incapacitated())
					get_nozzle(user)
			else
				to_chat(user, span_notice("\The [src] does not have a nozzle attached!"))
		else
			return OP_DECLINE
	else
		return OP_DECLINE
	return TRUE

/obj/item/weldpack/afterattack(obj/O as obj, mob/user as mob, proximity)
	if(!proximity) // this replaces and improves the get_dist(src,O) <= 1 checks used previously
		return
	if (istype(O, /obj/structure/reagent_dispensers/fueltank) && src.reagents.total_volume < max_fuel)
		O.reagents.trans_to_obj(src, max_fuel)
		to_chat(user, span_notice("You crack the cap off the top of the pack and fill it back up again from the tank."))
		play_sfx(src, SFX_EFFECTS_REFILL)
		return
	else if (istype(O, /obj/structure/reagent_dispensers/fueltank) && src.reagents.total_volume == max_fuel)
		to_chat(user, span_warning("The pack is already full!"))
		return

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/weldpack/proc/mousedrop_input(datum/act/input/A)
	if(!handle_inventory_drop(A.actor, A.over))
		return INPUT_FALLTHROUGH

/obj/item/weldpack/proc/handle_inventory_drop(mob/user, obj/over_object)
	if(!canremove)
		return TRUE

	if (ishuman(user) || issmall(user)) //so monkeys can take off their backpacks -- Urist

		if (istype(user.loc,/obj/mecha)) // stops inventory actions in a mech. why?
			return TRUE

		if (!( istype(over_object, /atom/movable/screen) ))
			return FALSE

		//makes sure that the thing is equipped, so that we can't drag it into our hand from miles away.
		//there's got to be a better way of doing this.
		if (!(src.loc == user) || (src.loc && src.loc.loc == user))
			return TRUE

		if (( user.restrained() ) || ( user.stat ))
			return TRUE

		if ((src.loc == user) && !(istype(over_object, /atom/movable/screen)) && !user.unEquip(src))
			return TRUE

		switch(over_object.name)
			if("r_hand")
				user.put_in_r_hand(src)
			if("l_hand")
				user.put_in_l_hand(src)
		src.add_fingerprint(user)
	return TRUE

/obj/item/weldpack/examine(mob/user)
	. = ..()
	. += "It has [src.reagents.total_volume] units of fuel left!"

/obj/item/weldpack/survival
	name = "emergency welding kit"
	desc = "A heavy-duty, portable welding fluid carrier."
	slot_flags = SLOT_BACK
	icon = 'icons/obj/storage.dmi'
	icon_state = "welderpack-e"
	item_state = "welderpack"
	w_class = ITEMSIZE_LARGE
	max_fuel = 100
	nozzle_type = /obj/item/weldingtool/tubefed/survival

/obj/item/weldpack
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/back/mob_teshari.dmi'
		)
