/mob/living/simple_mob/vore/alienanimals/catslug/custom/engislug
	name = "Engineer O'Brimn"
	desc = "A yellow-furred noodley bodied creature with thin arms and legs, and gloomy dark eyes. This one seems to be wearing a too-big high visibility vest and a full-face hardhat."
	tt_desc = "Mollusca Felis Munitor"
	icon_state = "engislug"
	icon_living = "engislug"
	icon_rest = "engislug_rest"
	icon_dead = "engislug_dead"
	holder_type = /obj/item/holder/catslug/custom/engislug
	myid_access = list(ACCESS_ENGINE, ACCESS_ENGINE_EQUIP, ACCESS_TECH_STORAGE, ACCESS_MAINT_TUNNELS, ACCESS_CONSTRUCTION, ACCESS_ATMOSPHERICS)
	siemens_coefficient = 0 		//Noodly fella's gone and built up an immunity from many small shocks

	minbodytemp = 200
	maxbodytemp = 600		//engislug can survive a little heat, as a treat
	heat_damage_per_tick = 1
	cold_damage_per_tick = 2

	min_oxy = 16 			//Require atleast 16kPA oxygen
	max_oxy = 0
	min_tox = 0		//should still suffer hypoxia, but the mask ought to filter out not-nice gases for them
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/engislug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/engislug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/engislug))

/mob/living/simple_mob/vore/alienanimals/catslug/custom/engislug/catslug_interaction_hand(datum/act/op/A, stance)
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
			MSG_SELF(span_notice("You rub %T%'s tummy... You feel the danger.")), \
			MSG_OTHERS(span_notice("%U% rubs %T%'s tummy...")))
		if(client)
			return
		act_message(src, M, null, MSG_OTHERS(span_notice("%U% pushes %T%'s hand away from their tummy and furrows their brow!")))
		//prob(5) give_target on tummy rub removed.
	else
		return OP_DECLINE
