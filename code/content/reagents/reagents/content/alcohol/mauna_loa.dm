/datum/reagent/ethanol/mauna_loa
	name = REAGENT_MAUNALOA
	id = REAGENT_ID_MAUNALOA
	description = "Extremely hot; not for the faint of heart!"
	taste_description = "fiery, with an aftertaste of burnt flesh"
	color = "#fe8308" // rgb(254, 131, 8)
	strength = 50
	glass_name = REAGENT_MAUNALOA
	glass_desc = "Lava in a drink... mug... volcano... thing."

/datum/reagent/ethanol/mauna_loa/affect_ingest(mob/living/carbon/M, alien, removed)
	if(prob(10))
		M.adjust_fire_stacks(5*removed)
		M.ignite_mob()
