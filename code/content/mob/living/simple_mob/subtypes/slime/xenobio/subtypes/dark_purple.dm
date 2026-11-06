/mob/living/simple_mob/slime/xenobio/dark_purple/get_mechanics_info(list/additional_information)
	return ..(list("This slime applies phoron to enemies it attacks. A biosuit or other thick armor can protect from the toxic attack. \
	If hit with a burning attack, it will erupt in flames.") + additional_information)

/mob/living/simple_mob/slime/xenobio/dark_purple
	desc ="This slime produces ever-coveted phoron.  Risky to handle but very much worth it."
	color = "#660088"
	slime_color = "dark purple"
	coretype = /obj/item/slime_extract/dark_purple
	reagent_injected = REAGENT_ID_PHORON
	player_msg = "You <b>inject phoron</b> into enemies you attack.<br>\
	<b>You will erupt into flames if harmed by fire!</b>"

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/purple,
			/mob/living/simple_mob/slime/xenobio/orange,
			/mob/living/simple_mob/slime/xenobio/ruby,
			/mob/living/simple_mob/slime/xenobio/ruby
		)

/mob/living/simple_mob/slime/xenobio/dark_purple

/mob/living/simple_mob/slime/xenobio/dark_purple/proc/ignite()
	act_message(src, null, null, MSG_OTHERS(span_critical("%U% erupts in an inferno!")))
	for(var/turf/simulated/target_turf in view(2, src))
		target_turf.assume_gas(GAS_PHORON, 30, 1500+T0C)
		target_turf.hotspot_expose(1500+T0C, 400)
	destroyed(src, null, BURN)

CAPABILITIES(/mob/living/simple_mob/slime/xenobio/dark_purple)
	configure(living_rules(fire_reaction = FIRE_REACTION_TRIGGER, fire_trigger_proc = TYPE_PROC_REF(/mob/living/simple_mob/slime/xenobio/dark_purple, ignite)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(blast_ignite)), order = ORDER_EARLY))
	op("darkpurple_slime_item", item(/obj/item), priority(OP_PRIORITY_PART + 1), then(PROC_REF(darkpurple_slime_interaction_item)))

/mob/living/simple_mob/slime/xenobio/dark_purple/proc/blast_ignite(datum/act/A)
	log_and_message_admins("ignited due to a chain reaction with an explosion.", src)
	ignite()
	return TRUE

/mob/living/simple_mob/slime/xenobio/dark_purple/bullet_act(obj/item/projectile/P, def_zone)
	if(P.obj_damage_type() && P.obj_damage_type() == BURN && P.damage) // Most bullets won't trigger the explosion, as a mercy towards Security.
		log_and_message_admins("ignited due to bring hit by a burning projectile[P.firer ? " by [key_name(P.firer)]" : ""].", src)
		ignite()
	else
		..()

/// Old attackby: burning weapons ignite it.
/mob/living/simple_mob/slime/xenobio/dark_purple/proc/darkpurple_slime_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	. = OP_OK
	if(istype(W) && combat_of(W).force && W.obj_damage_type() == BURN)
		log_and_message_admins("ignited due to being hit with a burning weapon ([W]) by [key_name(user)].", src)
		ignite()
	else
		return OP_DECLINE
