// Tier 5

/mob/living/simple_mob/slime/xenobio/oil/get_mechanics_info(list/additional_information)
	return ..(list("If this slime suffers damage from a fire or heat based source, or if it is caught inside \
	an explosion, it will explode. Oil slimes will also suicide-bomb themselves when fighting something that is not a monkey or slime.") + additional_information)

/mob/living/simple_mob/slime/xenobio/oil
	desc ="This slime is explosive and volatile.  Smoking near it is probably a bad idea."
	color = "#333333"
	slime_color = "oil"
	shiny = TRUE
	coretype = /obj/item/slime_extract/oil
	player_msg = "You <b>will explode if struck by a burning attack</b>, or if you hit an enemy with a melee attack that is not a monkey or another slime."

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/oil,
		/mob/living/simple_mob/slime/xenobio/oil,
		/mob/living/simple_mob/slime/xenobio/red,
		/mob/living/simple_mob/slime/xenobio/red
	)

/mob/living/simple_mob/slime/xenobio/oil

/mob/living/simple_mob/slime/xenobio/oil/proc/explode()
	if(stat != DEAD)
		explosion(src.loc, 0, 2, 4) // A bit weaker since the suicide charger tended to gib the poor sod being targeted.
		if(src) // Delete ourselves if the explosion didn't do it.
			destroyed(src, null, "explosion")

/mob/living/simple_mob/slime/xenobio/oil/proc/suicide_bomb(mob/living/L)
	log_and_message_admins("has suicide-bombed themselves while trying to kill \the [L].", src)
	explode()

/mob/living/simple_mob/slime/xenobio/oil/apply_melee_effects(atom/A)
	if(isliving(A))
		var/mob/living/L = A
		if(ishuman(L))
			var/mob/living/carbon/human/H = A
			if(istype(H.species, /datum/species/monkey))
				return ..()// Don't blow up when just eatting monkeys.

		else if(isslime(L))
			return ..()

		// Otherwise blow ourselves up.
		say(pick("Sacrifice...!", "Sssss...", "Boom...!"))
		ai_busy_begin()
		after(src, 2 SECONDS, PROC_REF(suicide_bomb), with = list(L))

	return ..()

CAPABILITIES(/mob/living/simple_mob/slime/xenobio/oil)
	configure(living_rules(fire_reaction = FIRE_REACTION_TRIGGER, fire_trigger_proc = TYPE_PROC_REF(/mob/living/simple_mob/slime/xenobio/oil, explode), fire_trigger_verb = "exploded"))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(blast_explode)), order = ORDER_EARLY))
	op("oilslime_item", item(/obj/item), priority(OP_PRIORITY_PART + 1), then(PROC_REF(oilslime_interaction_item)))

/mob/living/simple_mob/slime/xenobio/oil/proc/blast_explode(datum/act/A)
	log_and_message_admins("exploded due to a chain reaction with another explosion.", src)
	explode()
	return TRUE

/mob/living/simple_mob/slime/xenobio/oil/bullet_act(obj/item/projectile/P, def_zone)
	if(P.obj_damage_type() && P.obj_damage_type() == BURN && P.damage) // Most bullets won't trigger the explosion, as a mercy towards Security.
		log_and_message_admins("exploded due to bring hit by a burning projectile[P.firer ? " by [key_name(P.firer)]" : ""].", src)
		explode()
	else
		..()

/// Old attackby: burning weapons make it explode.
/mob/living/simple_mob/slime/xenobio/oil/proc/oilslime_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	. = OP_OK
	if(istype(W) && combat_of(W).force && W.obj_damage_type() == BURN)
		log_and_message_admins("exploded due to being hit with a burning weapon ([W]) by [key_name(user)].", src)
		explode()
	else
		return OP_DECLINE
