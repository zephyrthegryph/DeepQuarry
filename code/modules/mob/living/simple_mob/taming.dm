
/mob/living/simple_mob
	// Assoc list of items that can be given to a mob to befriend it, and the percent success.
	var/list/tame_items
	// Mobs who are 'friends' (a relation list: a friend going away drops out).
	var/list/tamers

/mob/living/simple_mob/relations()
	. = ..()
	. += rel_many(nameof(tamers))

/mob/living/simple_mob/IIsAlly(mob/living/L)
	. = ..()

	if(!. && LAZYLEN(tamers))
		if(L in tamers)
			return TRUE

/mob/living/simple_mob/proc/can_tame(obj/O, mob/user)
	if(!LAZYLEN(tame_items))
		return FALSE

	if(!user)
		return FALSE

	if(!O)
		return FALSE

	for(var/path in tame_items)
		if(istype(O, path) && unique_tame_check(O,user))
			return TRUE

	return FALSE

/// Per-mob extra condition on a taming item (the old half-second wait is gone).
/mob/living/simple_mob/proc/unique_tame_check(obj/O, mob/user)
	return TRUE

/mob/living/simple_mob/proc/tame_prob(obj/O, mob/user)
	for(var/path in tame_items)
		if(istype(O, path))
			if(prob(tame_items[path]))
				return TRUE
	return FALSE

/mob/living/simple_mob/proc/do_tame(obj/O, mob/user)
	if(!user)
		return

	handle_tame_item(O, user)

	if(!(user in tamers))
		rel_add(src, nameof(tamers), user)
	ai_brain.forget_everything()

/mob/living/simple_mob/proc/handle_tame_item(obj/O, mob/user)
	consume(O, user)

/mob/living/simple_mob/proc/fail_tame(obj/O, mob/user)
	consume(O, user)
