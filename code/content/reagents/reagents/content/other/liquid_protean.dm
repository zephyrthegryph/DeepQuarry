/datum/reagent/liquid_protean
	treatment_tags = list(
		TREAT_TISSUE_REPAIR = 0.1,
		TREAT_BURN_CARE = 0.1,
		TREAT_OXYGENATION = 0.1,
		TREAT_ANTITOXIN = 0.1,
		TREAT_PLATING_REPAIR = 0.1,
		TREAT_WIRING_REPAIR = 0.1,
	)
	name = REAGENT_LIQUIDPROTEAN
	id = REAGENT_ID_LIQUIDPROTEAN
	description = "This seems to be a small portion of a Protean creature, still slightly wiggling."
	taste_description = "wiggly peanutbutter"
	reagent_state = LIQUID
	color = "#1d1d1d"
	scannable = SCANNABLE_BENEFICIAL
	metabolism = REM * 0.5
	affects_robots = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/liquid_protean/affect_blood(mob/living/carbon/M, alien, removed)
	// Its restorative action is the treatment_tags profile.
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.nif)
			var/obj/item/nif/nif = H.nif //L o c a l
			if(nif.stat == NIF_TEMPFAIL)
				nif.set_stat(NIF_INSTALLING)
			nif.repair(removed*0.1)
