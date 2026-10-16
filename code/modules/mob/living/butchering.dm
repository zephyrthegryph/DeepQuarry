

/mob/living
	var/meat_amount = 0					// How much meat to drop from this mob when butchered


	var/list/butchery_loot				// Associated list, path = number.


// Harvest an animal's delicious byproducts: one cut of meat per lap of the "harvest" op, then the "butcher" op (code/library/mob/living_abilities.dm).
/mob/living/proc/harvest(mob/user, obj/item/I)
	if(op_claimed(src))
		return
	if(butchery_config_of(src).meat_type && meat_amount > 0 && stat == DEAD)
		perform_op(user, src, "harvest", I, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("cuts" = meat_amount))
		return

	if(!meat_amount)
		handle_butcher(user, I)

/// A cut takes as long as the animal is big.
/mob/living/proc/harvest_time(datum/act/op/A)
	return 0.5 SECONDS * (mob_size / 10)

/// One cut of meat.
/mob/living/proc/harvest_cut(datum/act/op/A)
	var/path = butchery_config_of(src).meat_type
	var/obj/item/meat = new path(get_turf(src))
	if(butchery_config_of(src).name_the_meat)
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
	if(((butchery_config_of(src).meat_type && meat_amount) || LAZYLEN(butchery_loot)) && stat == DEAD)
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
					loot.set_pixel_x(rand(-12, 12))
					loot.set_pixel_y(rand(-12, 12))

			butchery_loot.Cut()
			butchery_loot = null

	// removed() is a ledger move out; the detach hook empties the caches.
	if(LAZYLEN(organs) && butchery_config_of(src).butchery_drops_organs)
		for(var/obj/item/organ/OR in organs.Copy())
			OR.removed()

	if(butchery_config_of(src).butchery_drops_organs)
		spawn_butchery_organs()
	if(length(internal_organ_list()) && butchery_config_of(src).butchery_drops_organs)
		for(var/obj/item/organ/OR in internal_organ_list())
			OR.removed()

	if(!ckey)
		if(issmall(src))
			act_message(user, src, others = span_danger("%U% chops up %T%!"))
			new /obj/effect/decal/cleanable/blood/splatter(get_turf(src))
			if(butchery_config_of(src).gib_on_butchery)
				destroyed(src, user, BRUTE)
		else
			act_message(user, src, others = span_danger("%U% butchers %T% messily!"))
			if(butchery_config_of(src).gib_on_butchery)
				gib()

// A meat type path or a shared definition, never a per-mob instance.

/proc/butchery_config(meat_type = null, name_the_meat = null, gib_on_butchery = null, butchery_drops_organs = null)
	return entry_make(ENTRY_BUTCHERY_CONFIG, null, list("meat_type" = meat_type, "name_the_meat" = name_the_meat, "gib_on_butchery" = gib_on_butchery, "butchery_drops_organs" = butchery_drops_organs))

/datum/type_trait/butchery_config
	var/meat_type = null
	var/name_the_meat = TRUE
	var/gib_on_butchery = FALSE
	var/butchery_drops_organs = TRUE

/datum/type_trait/butchery_config/copy_values(datum/type_trait/butchery_config/into)
	into.meat_type = meat_type
	into.name_the_meat = name_the_meat
	into.gib_on_butchery = gib_on_butchery
	into.butchery_drops_organs = butchery_drops_organs

/datum/entry_engine/type_trait/butchery_config
	kind = ENTRY_BUTCHERY_CONFIG
	trait_type = /datum/type_trait/butchery_config
	publish_key = BUTCHERY_CONFIG_KEY
	base_type = /mob/living
	var_names = list("meat_type" = "meat_type", "name_the_meat" = "name_the_meat", "gib_on_butchery" = "gib_on_butchery", "butchery_drops_organs" = "butchery_drops_organs")

READS_AS(/proc/butchery_config_of, BUTCHERY_CONFIG_KEY)
/proc/butchery_config_of(mob/living/M) as /datum/type_trait/butchery_config
	READS_FROM(M)
	return type_trait_of(M, ENTRY_BUTCHERY_CONFIG)

/proc/butchery_config_of_type(path) as /datum/type_trait/butchery_config
	READS_FROM()
	return type_trait_of_type(path, ENTRY_BUTCHERY_CONFIG)
