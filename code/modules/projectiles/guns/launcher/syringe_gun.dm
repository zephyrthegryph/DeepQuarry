MATERIAL_MIX(/obj/item/syringe_cartridge, list(MAT_STEEL = 125, MAT_GLASS = 375))
/obj/item/syringe_cartridge
	name = "syringe gun cartridge"
	desc = "An impact-triggered compressed gas cartridge that can be fitted to a syringe for rapid injection."
	icon = 'icons/obj/ammo.dmi'
	icon_state = "syringe-cartridge"
	var/icon_flight = "syringe-cartridge-flight" //so it doesn't look so weird when shot
	slot_flags = SLOT_BELT | SLOT_EARS
	throwforce = 3
	force = 3
	w_class = ITEMSIZE_TINY
	var/tmp/obj/item/reagent_containers/syringe/syringe

DECLARE_APPEARANCE_PROC(/obj/item/syringe_cartridge, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/syringe_cartridge/appearance_overlays()
	. = list()
	underlays.Cut()
	if(syringe())
		underlays += image(syringe().icon, src, syringe().icon_state)
		if(length(syringe().filling)) underlays += syringe().filling

/// Old attackby.
/obj/item/syringe_cartridge/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/reagent_containers/syringe))
		if(syringe())
			to_chat(user, span_warning("[src] already has a syringe loaded!"))
			return OP_PASS
		rel_set(src, nameof(syringe), I)
		to_chat(user, span_notice("You carefully insert [syringe()] into [src]."))
		user.remove_from_mob(syringe())
		syringe().forceMove(src)
		sharp = TRUE
		name = "syringe dart"
		update_icon()
	return OP_PASS

CAPABILITIES(/obj/item/syringe_cartridge)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attack_self.
/obj/item/syringe_cartridge/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(syringe())
		to_chat(user, span_notice("You remove [syringe()] from [src]."))
		play_sfx(src, SFX_WEAPONS_EMPTY)
		user.put_in_hands(syringe())
		rel_clear(src, nameof(syringe))
		sharp = initial(sharp)
		name = initial(name)
		update_icon()
	return TRUE

/obj/item/syringe_cartridge/proc/prime()
	//the icon state will revert back when update_icon() is called from throw_impact()
	icon_state = icon_flight
	underlays.Cut()

/obj/item/syringe_cartridge/throw_impact(atom/hit_atom, datum/thrownthing/throwingdatum)
	..() //handles embedding for us. Should have a decent chance if thrown fast enough
	if(syringe())
		//check speed to see if we hit hard enough to trigger the rapid injection
		//incidentally, this means syringe_cartridges can be used with the pneumatic launcher
		if(throwingdatum?.speed >= 10 && isliving(hit_atom))
			var/mob/living/L = hit_atom
			//unfortuately we don't know where the dart will actually hit, since that's done by the parent.
			if(L.can_inject() && syringe().reagents)
				var/contained = syringe().reagents.get_reagents()
				var/trans = syringe().reagents.trans_to_mob(L, 15, CHEM_BLOOD)
				var/mob/thrower = throwingdatum?.get_thrower()
				if(thrower)
					add_attack_logs(thrower,L,"Shot with [src.name] containing [contained], trasferred [trans] units")

		syringe().break_syringe(iscarbon(hit_atom)? hit_atom : null)
		syringe().update_icon()

	icon_state = initial(icon_state) //reset icon state
	update_icon()

/obj/item/gun/launcher/syringe
	name = "syringe gun"
	desc = "A spring loaded rifle designed to fit syringes, designed to incapacitate unruly patients from a distance."
	icon_state = "syringegun"
	item_state = "syringegun"
	w_class = ITEMSIZE_NORMAL
	force = 7
	MATERIAL_BULK(MAT_STEEL, 2000)
	slot_flags = SLOT_BELT | SLOT_HOLSTER

	fire_sound = SFX_WEAPONS_EMPTY
	fire_sound_text = "a metallic thunk"
	recoil = 0
	release_force = 10
	throw_distance = 10

	var/list/darts
	var/max_darts = 1
	var/tmp/obj/item/syringe_cartridge/next

	special_handling = TRUE

// Loaded cartridges sit in the gun's contents; next is a view of the one on the bolt.
/obj/item/gun/launcher/syringe/ownership()
	. = ..()
	. += owns(nameof(darts), policy = OWN_CONTAINED, is_list = TRUE)

/obj/item/gun/launcher/syringe/consume_next_projectile()
	if(next())
		next().prime()
		return next()
	return null

/obj/item/gun/launcher/syringe/handle_post_fire()
	..()
	own_take_member(src, nameof(darts), next()) // fired: it flies off on its own
	rel_clear(src, nameof(next))

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/launcher/syringe/gun_self(datum/act/op/A, callback)
	var/mob/user = A.actor
	. = ..()
	if(. == OP_OK)
		return OP_OK
	if(next())
		act_message(user, src, MSG_SELF(span_warning("You unlatch and carefully relax the bolt on %T%, unloading the spring.")), \
			MSG_OTHERS("%U% unlatches and carefully relaxes the bolt on %T%."))
		rel_clear(src, nameof(next))
	else if(length(darts))
		play_sfx(src, SFX_WEAPONS_FLIPBLADE)
		act_message(user, src, MSG_SELF(span_warning("You draw back the bolt on %T%, loading the spring!")), \
			MSG_OTHERS("%U% draws back the bolt on %T%, clicking it into place."))
		rel_set(src, nameof(next), LAZYACCESS(darts, 1))
	add_fingerprint(user)

CAPABILITIES(/obj/item/gun/launcher/syringe)
	op("interaction_hand", hand(), then(PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/item/gun/launcher/syringe/proc/interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(user.get_inactive_hand() == src)
		if(!length(darts))
			to_chat(user, span_warning("[src] is empty."))
			return TRUE
		if(next())
			to_chat(user, span_warning("[src]'s cover is locked shut."))
			return TRUE
		var/obj/item/syringe_cartridge/C = LAZYACCESS(darts, 1)
		own_take_member(src, nameof(darts), C)
		user.put_in_hands(C)
		act_message(user, src, MSG_SELF(span_notice("You remove \a [C] from %T%.")), MSG_OTHERS("%U% removes \a [C] from %T%."))
		play_sfx(src, SFX_WEAPONS_EMPTY)
	else
		return OP_DECLINE
	return TRUE

/// Old attackby.
/obj/item/gun/launcher/syringe/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(istype(held, /obj/item/syringe_cartridge))
		var/obj/item/syringe_cartridge/C = held
		if(length(darts) >= max_darts)
			to_chat(user, span_warning("[src] is full!"))
			return OP_PASS
		if(!move_into(src, nameof(src.darts), C, user))
			return OP_PASS
		act_message(user, src, MSG_SELF(span_notice("You insert \a [C] into %T%.")), MSG_OTHERS("%U% inserts \a [C] into %T%."))
		return OP_PASS
	return ..()

/obj/item/gun/launcher/syringe/rapid
	name = "syringe gun revolver"
	desc = "A modification of the syringe gun design, using a rotating cylinder to store up to five syringes. The spring still needs to be drawn between shots."
	icon_state = "rapidsyringegun"
	item_state = "rapidsyringegun"
	max_darts = 5

/// the syringe this refers to (a relation view: null once it is deleted).
/obj/item/syringe_cartridge/proc/syringe() as /obj/item/reagent_containers/syringe
	return syringe

/// the next this refers to (a relation view: null once it is deleted).
/obj/item/gun/launcher/syringe/proc/next() as /obj/item/syringe_cartridge
	return next
