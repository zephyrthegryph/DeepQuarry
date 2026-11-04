/datum/reagent/toxin/stimm	//Homemade Hyperzine
	factors = alist(STAT_SLOWDOWN = -1, STAT_PENALTY_SCALE = 0.5)
	name = REAGENT_STIMM
	id = REAGENT_ID_STIMM
	description = "A homemade stimulant with some serious side-effects."
	taste_description = "sweetness"
	taste_mult = 1.8
	dermal_absorption = 0.2 //Made with fertilizer, so some penetration ala organophosphate.
	color = "#d0583a"
	metabolism = REM * 3
	overdose = 10
	overdose_mod = 0.5
	strength = 3
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/toxin/stimm/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_TAJARA)
		removed *= 1.25
	..()
	if(prob(15))
		M.emote(pick("twitch", "blink_r", "shiver"))
	if(prob(15))
		act_message(M, null, MSG_SELF("You shudder uncontrollably, it hurts."), MSG_OTHERS("%U% shudders violently."))
		M.injure(INJURY_BLUNT, 6 * removed, source = src)

/datum/reagent/toxin/stimm/overdose(mob/living/carbon/M, alient, removed)
	..()
	if(prob(10)) // 1 in 10. This thing's made with welder fuel and fertilizer, what do you expect?
		var/obj/item/organ/internal/heart/ht = M.organ_in(O_HEART)
		if(ht)
			M.injure(INJURY_BLUNT, 1, ht, src, flags = INJURE_IGNORE_RESISTANCE)
			to_chat(M, span_warning("Huh... Is this what a heart attack feels like?"))
