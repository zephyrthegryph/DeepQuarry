/datum/reagent/toxin/potassium_chlorophoride
	name = REAGENT_POTASSIUMCHLOROPHORIDE
	id = REAGENT_ID_POTASSIUMCHLOROPHORIDE
	description = "A specific chemical based on Potassium Chloride to stop the heart for surgery. Not safe to eat!"
	taste_description = "salt"
	dermal_absorption = 0 //again, it's salt.
	reagent_state = SOLID
	color = "#FFFFFF"
	strength = 10
	overdose = 20
	filtered_organs = list(O_SPLEEN, O_KIDNEYS)
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_BURN = 3))

/datum/reagent/toxin/potassium_chlorophoride/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		H.induce_arrhythmia(CARDIAC_RHYTHM_ASYSTOLE) // A lethal-injection flatline; the arrest does the rest.
		if(H.stat != 1)
			if(H.losebreath() >= 10)
				H.set_losebreath(max(10, M.losebreath()-10))
			H.status_at_least(STAT_WEAKENED, 10)
