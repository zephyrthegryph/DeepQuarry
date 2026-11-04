/datum/reagent/toxin/expired_medicine
	name = REAGENT_EXPIREDMEDICINE
	id = REAGENT_ID_EXPIREDMEDICINE
	description = "Some form of liquid medicine that is well beyond its shelf date. Administering it now would cause illness."
	taste_description = "bitterness"
	dermal_absorption = 0
	reagent_state = LIQUID
	strength = 5
	filtered_organs = list(O_SPLEEN)
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/toxin/expired_medicine/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(prob(5))
		M.vomit()

/datum/reagent/toxin/expired_medicine/affect_ingest(mob/living/carbon/M, alien, removed)
	affect_blood(M, alien, removed * 0.66)
