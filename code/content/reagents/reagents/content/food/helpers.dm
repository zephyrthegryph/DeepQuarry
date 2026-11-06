/datum/reagent/proc/handle_spicy(mob/living/carbon/M, alien, removed)
	if(inert_for(M))
		return
	// Kept: plant people get a different, mild effect (not a strength).
	if(alien == IS_ALRAUNE) // It wouldn't affect plants that much.
		if(prob(5))
			to_chat(M, span_rose("You feel a pleasant sensation in your mouth."))
		warm_body(M, rand(10, 25), removed)
		return
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!H.can_feel_pain())
			return

	var/effective_dose = (dose * M.species.spice_mod)
	if((effective_dose < 5) && (dose == metabolism || prob(5)))
		to_chat(M, span_danger("Your insides feel uncomfortably hot!"))
	if(effective_dose >= 5)
		M.apply_effect(2 * M.species.spice_mod, AGONY, 0)
		warm_body(M, rand(1, 5) * M.species.spice_mod, removed) // Really fucks you up, cause it makes you overheat, too.
		if(prob(5))
			act_message(M, null, MSG_SELF(pick(span_danger("You feel like your insides are burning!"), span_danger("You feel like your insides are on fire!"), span_danger("You feel like your belly is full of lava!"))), \
				MSG_OTHERS(span_warning("%U% [pick("dry heaves!","coughs!","splutters!")]")))
	// holder.remove_reagent(REAGENT_ID_FROSTOIL, 5) // Nop, we don't instadelete spices for free.
