/datum/reagent/ethanol/fetching_fizz
	name = REAGENT_FETCHINGFIZZ
	id = REAGENT_ID_FETCHINGFIZZ
	description = "Cola/iron/uranium mixture resulting in a highly magnetic slurry. Mild alcohol content."
	taste_description = "charged metal"
	color = "#FF5B0F" // rgb(255, 91, 15)
	strength = 90

	glass_name = REAGENT_FETCHINGFIZZ
	glass_desc = "Induces magnetism in the imbiber. Started as a barroom prank but evolved to become popular with miners and scrappers. Metallic aftertaste."

/datum/reagent/ethanol/fetching_fizz/affect_ingest(mob/living/carbon/M, alien, removed)
	for(var/obj/item/ore/O in orange(3, M))
		step_towards(O, get_turf(M))
