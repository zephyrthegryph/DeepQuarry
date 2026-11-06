/datum/reagent/toxin/potassium_chloride
	name = REAGENT_POTASSIUMCHLORIDE
	id = REAGENT_ID_POTASSIUMCHLORIDE
	description = "A delicious salt that stops the heart when injected into cardiac muscle."
	taste_description = "salt"
	dermal_absorption = 0 //it's salt.
	reagent_state = SOLID
	color = "#FFFFFF"
	strength = 0
	overdose = REAGENTS_OVERDOSE
	filtered_organs = list(O_SPLEEN, O_KIDNEYS)
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_BURN = 2))

/datum/reagent/toxin/potassium_chloride/overdose(mob/living/carbon/M, alien)
	..()
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		H.induce_arrhythmia(CARDIAC_RHYTHM_VF) // Hyperkalaemia fibrillates the heart; the arrest does the rest.
		if(H.stat != 1)
			if(H.losebreath() >= 10)
				H.set_losebreath(max(10, H.losebreath() - 10))
			H.status_at_least(STAT_WEAKENED, 10)
