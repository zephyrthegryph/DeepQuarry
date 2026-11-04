/datum/reagent/toxin/sifslurry
	name = REAGENT_SIFSAP
	id = REAGENT_ID_SIFSAP
	description = "A natural slurry comprised of fluorescent bacteria native to Sif, in the Vir system."
	taste_description = "sour"
	dermal_absorption = 0 //Bacteria.
	reagent_state = LIQUID
	color = "#C6E2FF"
	strength = 2
	overdose = 20
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/toxin/sifslurry/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA) // Symbiotic bacteria.
		M.adjust_nutrition(strength * removed)
		return
	else
		M.apply_body_effect(/datum/body_effect/slow_pulse, 30 SECONDS)
	..()

/datum/reagent/toxin/sifslurry/overdose(mob/living/carbon/M, alien, removed) // Overdose effect.
	if(inert_for(M))
		return
	M.apply_effect(2 * removed,IRRADIATE, 0, 0)
	M.apply_effect(5 * removed,DROWSY, 0, 0)

/datum/reagent/toxin/sifslurry/affect_ingest(mob/living/carbon/M, alien, removed)
	affect_blood(M, alien, removed * 0.7)
