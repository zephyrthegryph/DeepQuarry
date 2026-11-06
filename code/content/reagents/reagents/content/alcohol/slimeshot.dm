/datum/reagent/ethanol/slimeshot
	name = REAGENT_SLIMESHOT
	id = REAGENT_ID_SLIMESHOT
	description = "A thick and toxic slime jelly shot."
	taste_description = "liquified organs"
	color = "#6fa300" // rgb(111, 163, 0)
	strength = 10

	glass_name = REAGENT_SLIMESHOT
	glass_desc = "A thick slime jelly shot. You can feel your death approaching."

	allergen_type = ALLERGEN_GRAINS //Made from vodka(grains)

/datum/reagent/ethanol/slimeshot/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	M.reagents.add_reagent(REAGENT_ID_SLIMEJELLY, 0.25)
