

/mob/living
	var/meat_amount = 0					// How much meat to drop from this mob when butchered
	var/obj/meat_type					// The meat object to drop
	var/name_the_meat = TRUE

	var/gib_on_butchery = FALSE
	var/butchery_drops_organs = TRUE	// Do we spawn and/or drop organs when butchered?

	var/list/butchery_loot				// Associated list, path = number.


// Harvest an animal's delicious byproducts: one cut of meat per lap of the "harvest" op, then the "butcher" op (code/library/mob/living_abilities.dm).
/mob/living/proc/harvest(mob/user, obj/item/I)
	if(op_claimed(src))
		return
	if(meat_type && meat_amount > 0 && stat == DEAD)
		perform_op(user, src, "harvest", I, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("cuts" = meat_amount))
		return

	if(!meat_amount)
		handle_butcher(user, I)

/// A cut takes as long as the animal is big.
/mob/living/proc/harvest_time(datum/act/op/A)
	return 0.5 SECONDS * (mob_size / 10)

/// One cut of meat.
/mob/living/proc/harvest_cut(datum/act/op/A)
	var/obj/item/meat = new meat_type(get_turf(src))
	if(name_the_meat)
		meat.name = "[src.name] [meat.name]"
	new /obj/effect/decal/cleanable/blood/splatter(get_turf(src))
	meat_amount--
	LAZYSET(A.args, "cuts", A.arg("cuts") - 1)

/// Another cut while there are cuts left (the op counts them: the meat was counted when it began).
/mob/living/proc/harvest_more(datum/act/op/A)
	return A.arg("cuts") > 0

/// The last cut is made: the carcass is butchered.
/mob/living/proc/harvest_finished(datum/act/op/A)
	handle_butcher(A.actor, A.held)

/mob/living/proc/can_butcher(mob/user, obj/item/I)	// Override for special butchering checks.
	if(((meat_type && meat_amount) || LAZYLEN(butchery_loot)) && stat == DEAD)
		return TRUE

	return FALSE

/mob/living/proc/handle_butcher(mob/user, obj/item/I)
	if(op_claimed(src))
		return
	if(!user)
		butcher_loot(user, I)
		return
	perform_op(user, src, "butcher", I, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)

/// Butchering takes as long as the animal is big.
/mob/living/proc/butcher_time(datum/act/op/A)
	return 2 SECONDS * mob_size / 10

/mob/living/proc/butcher_finished(datum/act/op/A)
	butcher_loot(A.actor, A.held)

/// What a butchered carcass gives: its loot and organs, and the mess.
/mob/living/proc/butcher_loot(mob/user, obj/item/I)
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
