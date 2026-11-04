/datum/reagent/drink/juice/carrot
	name = REAGENT_CARROTJUICE
	id = REAGENT_ID_CARROTJUICE
	description = "It is just like a carrot but without crunching."
	taste_description = "carrots"
	color = "#FF8C00" // rgb: 255, 140, 0

	glass_name = "carrot juice"
	glass_desc = "It is just like a carrot but without crunching."
	allergen_type = ALLERGEN_VEGETABLE //Carrots are vegetables
	cup_prefix = "carrot"

/datum/reagent/drink/juice/carrot/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	M.reagents.add_reagent(REAGENT_ID_IMIDAZOLINE, removed * 0.2)
