

/mob/living
	var/meat_amount = 0					// How much meat to drop from this mob when butchered
	var/obj/meat_type					// The meat object to drop
	var/name_the_meat = TRUE

	var/gib_on_butchery = FALSE
	var/butchery_drops_organs = TRUE	// Do we spawn and/or drop organs when butchered?

	var/list/butchery_loot				// Associated list, path = number.


// Harvest an animal's delicious byproducts
/mob/living/proc/harvest(mob/user, obj/item/I)
	if(meat_type && meat_amount>0 && (stat == DEAD) && !om_in_use(src))
		harvest_step(user, I)
		return

	if(!meat_amount && !om_in_use(src))
		handle_butcher(user, I)

/// Carves one cut of meat per timed action until none is left, then butchers.
/mob/living/proc/harvest_step(mob/user, obj/item/I)
	if(meat_amount > 0)
		om_do_after(user, 0.5 SECONDS * (mob_size / 10), target = src, receiver = src, on_done = PROC_REF(harvest_cut), done_args = list(user, I), claims = TRUE)
		return
	handle_butcher(user, I)

/mob/living/proc/harvest_cut(mob/user, obj/item/I)
	var/obj/item/meat = new meat_type(get_turf(src))
	if(name_the_meat)
		meat.name = "[src.name] [meat.name]"
	new /obj/effect/decal/cleanable/blood/splatter(get_turf(src))
	meat_amount--
	harvest_step(user, I)

/mob/living/proc/can_butcher(mob/user, obj/item/I)	// Override for special butchering checks.
	if(((meat_type && meat_amount) || LAZYLEN(butchery_loot)) && stat == DEAD)
		return TRUE

	return FALSE

/mob/living/proc/handle_butcher(mob/user, obj/item/I)
	if(om_in_use(src))
		return
	if(!user)
		butcher_done(user, I)
		return
	om_do_after(user, 2 SECONDS * mob_size / 10, target = src, receiver = src, on_done = PROC_REF(butcher_done), done_args = list(user, I), claims = TRUE)

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
	if(LAZYLEN(internal_organs) && butchery_drops_organs)
		for(var/obj/item/organ/OR in internal_organs.Copy())
			OR.removed()

	if(!ckey)
		if(issmall(src))
			user?.visible_message(span_danger("[user] chops up \the [src]!"))
			new /obj/effect/decal/cleanable/blood/splatter(get_turf(src))
			if(gib_on_butchery)
				qdel(src)
		else
			user?.visible_message(span_danger("[user] butchers \the [src] messily!"))
			if(gib_on_butchery)
				gib()
