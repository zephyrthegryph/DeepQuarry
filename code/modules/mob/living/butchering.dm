

/mob/living
	var/meat_amount = 0					// How much meat to drop from this mob when butchered
	var/obj/meat_type					// The meat object to drop
	var/name_the_meat = TRUE

	var/gib_on_butchery = FALSE
	var/butchery_drops_organs = TRUE	// Do we spawn and/or drop organs when butchered?

	var/list/butchery_loot				// Associated list, path = number.


// Harvest an animal's delicious byproducts
/mob/living/proc/harvest(mob/user, obj/item/I)
	if(meat_type && meat_amount>0 && (stat == DEAD) && !op_claimed(src))
		harvest_step(user, I)
		return

	if(!meat_amount && !op_claimed(src))
		handle_butcher(user, I)

/// Carves one cut of meat per lap of the "harvest_cut" op (library/mob/living_abilities.dm) until none is left, then butchers.
/mob/living/proc/harvest_step(mob/user, obj/item/I)
	if(meat_amount > 0)
		if(user)
			perform_op(user, src, "harvest_cut", I, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)
		return
	handle_butcher(user, I)

/// A cut takes as long as the animal is big.
/mob/living/proc/harvest_cut_time(datum/act/op/A)
	return max(1 TICK, 0.5 SECONDS * (mob_size / 10))

/// Another cut while there is meat left.
/mob/living/proc/harvest_more(datum/act/op/A)
	return read_once(meat_amount > 0)

/// One cut done: the meat, the blood, one less cut to make.
/mob/living/proc/harvest_cut_done(datum/act/op/A)
	var/obj/item/meat = new meat_type(get_turf(src))
	if(name_the_meat)
		meat.name = "[src.name] [meat.name]"
	new /obj/effect/decal/cleanable/blood/splatter(get_turf(src))
	meat_amount--

/// The last cut is made: the carcass is next.
/mob/living/proc/harvest_finished(datum/act/op/A)
	if(meat_amount > 0)
		return OP_OK
	butcher_begin(A.actor, A.held)
	return OP_OK

/mob/living/proc/can_butcher(mob/user, obj/item/I)	// Override for special butchering checks.
	if(((meat_type && meat_amount) || LAZYLEN(butchery_loot)) && stat == DEAD)
		return TRUE

	return FALSE

/mob/living/proc/handle_butcher(mob/user, obj/item/I)
	if(op_claimed(src))
		return
	butcher_begin(user, I)

/// Starts the butchering (the claim was checked by the caller, or ended with the cuts that led here).
/mob/living/proc/butcher_begin(mob/user, obj/item/I)
	if(!user)
		butcher_done(user, I)
		return
	perform_op(user, src, "butcher_mob", I, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)

/// The carcass takes as long as the animal is big.
/mob/living/proc/butcher_time(datum/act/op/A)
	return max(1 TICK, 2 SECONDS * mob_size / 10)

/mob/living/proc/butcher_finished(datum/act/op/A)
	butcher_done(A.actor, A.held)
	return OP_OK

/mob/living/proc/butcher_done(mob/user, obj/item/I)
	if(LAZYLEN(butchery_loot))
		if(LAZYLEN(butchery_loot))
			for(var/path in butchery_loot)
				while(butchery_loot[path])
					butchery_loot[path] -= 1
					var/obj/item/loot = new path(get_turf(src))
					loot.pixel_x = rand(-12, 12)
					loot.pixel_y = rand(-12, 12)

			butchery_loot.Cut()
			butchery_loot = null

	// removed() is a ledger move out; the detach hook empties the caches.
	if(LAZYLEN(organs) && butchery_drops_organs)
		for(var/obj/item/organ/OR in organs.Copy())
			OR.removed()

	if(butchery_drops_organs)
		spawn_butchery_organs()
	if(length(internal_organ_list()) && butchery_drops_organs)
		for(var/obj/item/organ/OR in internal_organ_list())
			OR.removed()

	if(!ckey)
		if(issmall(src))
			act_message(user, src, others = span_danger("%U% chops up %T%!"))
			new /obj/effect/decal/cleanable/blood/splatter(get_turf(src))
			if(gib_on_butchery)
				destroyed(src, user, BRUTE)
		else
			act_message(user, src, others = span_danger("%U% butchers %T% messily!"))
			if(gib_on_butchery)
				gib()

// A meat type path or a shared definition, never a per-mob instance.
