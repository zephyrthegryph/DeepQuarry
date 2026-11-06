/datum/reagent/drink/coffee/nukie/mega/grow //Basically macrocillin but for ingesting
	name = REAGENT_NUKIEMEGAGROWTH
	id = REAGENT_ID_NUKIEMEGAGROWTH
	color = "#90ed87"
	taste_description = "absurd hugeness"

/datum/reagent/drink/coffee/nukie/mega/grow/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	var/new_size = clamp((M.size_multiplier + 0.01), RESIZE_MINIMUM_DORMS, RESIZE_MAXIMUM_DORMS)
	M.resize(new_size, uncapped = M.has_large_resize_bounds(), aura_animation = FALSE)
