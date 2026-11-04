/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug
	name = "Miros"
	desc = "Looks like catslugs can into space after all! This little chap seems to have gotten their mitts on a tiny spacesuit, there's a nametag on it that reads \"Miros\" alongside the Aether Atmospherics logo."
	tt_desc = "Mollusca Felis Stellaris"
	icon_state = "spaceslug"
	icon_living = "spaceslug"
	icon_rest = "spaceslug_rest"
	icon_dead = "spaceslug_dead"
	holder_type = /obj/item/holder/catslug/custom/spaceslug

	minbodytemp = 0				// Shamelessly stolen temp & atmos tolerances from the space cat.
	maxbodytemp = 900
	heat_damage_per_tick = 3
	cold_damage_per_tick = 2

	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0

	player_msg = "You are an intelligent creature capable of more than most think, clad in a spacesuit that protects you from the ravages of vacuum and hostile atmospheres alike. You can pick up and use many things, and even carry some of them with you into the vents, which you can use to move around quickly. You're quiet and capable, you speak with your hands and your deeds!<br>- - - - -<br>" + span_notice("Keep in mind, your goal should generally be to survive. You're expected to follow the same rules as everyone else, so don't go self antagging without permission from the staff team, but you are able and capable of defending yourself from those who would attack you for no reason.")

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/spaceslug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/spaceslug))

/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug/catslug_interaction_hand(datum/act/op/A, stance)
	var/mob/living/carbon/human/M = A.actor
	. = OP_OK

	if(stat == DEAD)
		return OP_DECLINE
	if(stance != I_HELP)
		return OP_DECLINE
	play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
	if(resting)
		act_message(M, src, MSG_SELF(span_notice("You shake %T% awake!")), MSG_OTHERS(span_notice("\The [M.name] shakes %T% awake from their nap.")))
		lay_down()
		ai_brain.go_wake()
		return
	if(hud_of(M)?.zone_sel?.selecting == BP_HEAD)
		act_message(M, src, \
			MSG_SELF(span_notice("You pat %T% on their helmet.")), \
			MSG_OTHERS(span_notice("%U% pats %T% on their helmet.")))
		if(client)
			return
		if(prob(10))
			act_message(src, M, null, MSG_OTHERS(span_notice("%U% purrs and leans into %T%'s hand.")))
	else if(hud_of(M)?.zone_sel?.selecting == BP_R_HAND || hud_of(M)?.zone_sel?.selecting == BP_L_HAND)
		act_message(M, src, \
			MSG_SELF(span_notice("You shake %T%'s hand.")), \
			MSG_OTHERS(span_notice("%U% shakes %T%'s hand.")))
		if(client)
			return
		if(prob(10))
			act_message(src, M, null, MSG_OTHERS(span_notice("%U%'s looks a little confused and bonks their helmet's faceplate against %T%'s hand experimentally, attempting to nibble at it.")))
	else if(hud_of(M)?.zone_sel?.selecting == "mouth")
		act_message(M, src, \
			MSG_SELF(span_notice("You attempt to boop %T% on the nose, stopped only by that helmet they wear.")), \
			MSG_OTHERS(span_notice("%U% attempts to boop %T%'s nose, defeated only by the helmet they wear.")))
		if(client)
			return
		if(prob(10))
			act_message(src, M, null, MSG_OTHERS(span_notice("%U%'s eyes widen as they stare at %T%. After a moment they rub at the faint mark %T%'s digit left upon the surface of their helmet's faceplate.")))
	else if(hud_of(M)?.zone_sel?.selecting == BP_GROIN)
		act_message(M, src, \
			MSG_SELF(span_notice("You rub %T%'s tummy, accidently pressing a few of the buttons on their chestpiece in the process... You feel the danger.")), \
			MSG_OTHERS(span_notice("%U% rubs %T%'s tummy...")))
		if(client)
			return
		act_message(src, M, null, MSG_OTHERS(span_notice("%U% pushes %T%'s hand away from their tummy and furrows their brow, frantically pressing at the buttons %T% so carelessly pushed!")))
		//prob(5) give_target on tummy rub removed.
	else
		return OP_DECLINE
