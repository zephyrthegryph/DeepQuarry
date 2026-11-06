/datum/reagent/water/holywater
	name = REAGENT_HOLYWATER
	id = REAGENT_ID_HOLYWATER
	description = "An ashen-obsidian-water mix, this solution will alter certain sections of the brain's rationality."
	taste_description = "water"
	color = "#E0E8EF"
	mrate_static = TRUE
	dermal_absorption = 0.5 //It's so holy it penetrates into your blood.
	scannable = SCANNABLE_BENEFICIAL

	glass_name = "holy water"
	glass_desc = "An ashen-obsidian-water mix, this solution will alter certain sections of the brain's rationality."
	wiki_flag = WIKI_SPOILER

	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_RAW
	coolant_modifier = 1 // It's water
	var/failed_message = FALSE

/datum/reagent/water/holywater/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(ishuman(M)) // Any location
		if(M.mind && antag_cult().is_antagonist(M.mind) && prob(10))
			antag_cult().remove_antagonist(M.mind)
		if(prob(2)) //Get an ACTUAL chaplain for your stuff
			if(M.has_body_effect(/datum/body_effect/redspace_corruption))
				M.remove_body_effect(/datum/body_effect/redspace_corruption)
				to_chat(M, span_notice("You feel calmer."))

			if(M.has_contagion(/datum/affliction/contagion/fleshy_spread))
				for(var/datum/affliction/contagion/fleshy_spread/disease in M.get_contagions())
					disease.cure()
					break
				to_chat(M, span_notice("Your fever subsides.."))
		if(volume <= max_dose * 0.5 && !failed_message)
			if(M.has_body_effect(/datum/body_effect/redspace_corruption) || M.has_contagion(/datum/affliction/contagion/fleshy_spread))
				to_chat(M, span_notice("The power of the holy water courses through you, but seems to have failed to cure your ailments. Perhaps a larger dose is needed?"))
				failed_message = TRUE

/datum/reagent/water/holywater/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(ishuman(M)) // Any location
		if(M.mind && antag_cult().is_antagonist(M.mind) && prob(5))
			antag_cult().remove_antagonist(M.mind)
		if(prob(1)) //injecting holy water makes it weaker because that's sinful
			if(M.has_body_effect(/datum/body_effect/redspace_corruption))
				M.remove_body_effect(/datum/body_effect/redspace_corruption)
				to_chat(M, span_notice("You feel calmer."))

			if(M.has_contagion(/datum/affliction/contagion/fleshy_spread))
				for(var/datum/affliction/contagion/fleshy_spread/disease in M.get_contagions())
					disease.cure()
					break
				to_chat(M, span_notice("Your fever subsides.."))
		if(volume <= max_dose * 0.25 && !failed_message)
			if(M.has_body_effect(/datum/body_effect/redspace_corruption) || M.has_contagion(/datum/affliction/contagion/fleshy_spread))
				to_chat(M, span_notice("The power of the holy water courses through you, but seems to have failed to cure your ailments. Perhaps a larger dose is needed?"))
				failed_message = TRUE
	return

/datum/reagent/water/holywater/touch_turf(turf/T)
	..()
	if(volume >= 5)
		T.holy = 1
	return
