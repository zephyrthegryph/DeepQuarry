/datum/reagent/ethanol/crevice_spike
	name = REAGENT_CREVICESPIKE
	id = REAGENT_ID_CREVICESPIKE
	description = "Sour, bitter, and smashingly sobering."
	taste_description = "a bitter SPIKE with a sour aftertaste"
	color = "#5BD231" // rgb(91, 210, 49)
	strength = 200
	glass_name = REAGENT_CREVICESPIKE
	glass_desc = "It'll either knock the drunkenness out of you or knock you out cold. Both, probably."

/datum/reagent/ethanol/crevice_spike/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	M.injure(INJURY_BLUNT, 50 * removed, source = src)
	if(!M.ingested)
		return
	for(var/datum/reagent/R in M.ingested.reagent_list)
		if(istype(R, /datum/reagent/ethanol))
			R.remove_self(50 * removed)
