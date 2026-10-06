/// Was /datum/component/rotting_disability: a trait-granted disability ticking once a Life cycle.
CAPABILITY_TYPE(rotting_disability, CAP_DISABILITY_ROTTING, /datum/capability/disability/rotting, key = NONE)
/datum/capability/disability/rotting
	required_type = /mob/living/carbon/human

/datum/capability/disability/rotting/disability_tick(mob/living/carbon/human/owner)

	if(QDELETED(owner))
		return
	if(isbelly(owner.loc))
		return
	if(owner.transforming)
		return
	if(prob(2) && prob(3)) // stacked percents for rarity
		// random strange symptoms from organ/limb
		owner.automatic_custom_emote(VISIBLE_MESSAGE, "flinches slightly.", check_stat = TRUE)
		switch(rand(1,4))
			if(1)
				owner.injure(INJURY_TOXIN, rand(2, 8))
			if(2)
				owner.injure(INJURY_CELLULAR, rand(1, 2))
			if(3)
				owner.apply_body_effect(/datum/body_effect/numbness/mild, 3 SECONDS)
			else
				owner.add_oxygen_debt(rand(13, 26), src)
		// external organs need to fall off if damaged enough
		var/obj/item/organ/O = pick(owner.organs)
		if(O && !(O.organ_tag == BP_GROIN || O.organ_tag == BP_TORSO) && istype(O,/obj/item/organ/external))
			var/obj/item/organ/external/E = O
			if(O.damage >= O.min_broken_damage && !O.is_robotic() && prob(70))
				owner.apply_body_effect(/datum/body_effect/numbness/deep, 3 SECONDS) // what limb? Extreme nerve damage. Can't feel a thing + shock
				E.droplimb(TRUE, DROPLIMB_ACID)
