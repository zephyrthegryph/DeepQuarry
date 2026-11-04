/datum/objective/absorb/proc/gen_amount_goal(lowbound = 4, highbound = 6)
	target_amount = rand (lowbound,highbound)
	if (SSticker)
		var/n_p = 1 //autowin
		if (ticker_current_state() == GAME_STATE_SETTING_UP)
			for(var/mob/new_player/P in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
				if(P.client && P.ready && P.mind!=owner)
					n_p ++
		else if (ticker_current_state() == GAME_STATE_PLAYING)
			for(var/mob/living/carbon/human/P in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
				var/datum/changeling/comp = P.get_changeling_state()
				if(P.client && !(comp) && P.mind!=owner)
					n_p ++
		target_amount = min(target_amount, n_p)

	set_explanation_text("Absorb [target_amount] compatible genomes.")
	return target_amount

/datum/objective/absorb/check_completion()
	if(owner)
		var/datum/changeling/comp = owner.current ? owner.current.get_changeling_state() : null
		if(comp && comp.absorbed_dna && (comp.absorbedcount >= target_amount))
			return 1
	else
		return 0
