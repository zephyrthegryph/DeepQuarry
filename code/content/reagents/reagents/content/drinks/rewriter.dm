/datum/reagent/drink/rewriter
	name = REAGENT_REWRITER
	id = REAGENT_ID_REWRITER
	description = "The secret of the sanctuary of the Libarian..."
	taste_description = "citrus and coffee"
	nutriment_factor = 1.5
	color = "#485000"
	adj_temp = -5

	glass_name = REAGENT_REWRITER
	glass_desc = "The secret of the sanctuary of the Libarian..."
	allergen_type = ALLERGEN_FRUIT|ALLERGEN_COFFEE|ALLERGEN_STIMULANT //Made with space mountain wind (Fruit, caffeine)

/datum/reagent/drink/rewriter/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	M.status_adjust(STAT_JITTERY, 5)
