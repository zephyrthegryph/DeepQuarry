/datum/reagent/drink/coffee/nukie/mega/shrink //Basically microcillin but for ingesting
	name = REAGENT_NUKIEMEGASHRINK
	id = REAGENT_ID_NUKIEMEGASHRINK
	color = "#15ff00"
	taste_description = "a plastic bag floating gently on the breeze"

/datum/reagent/drink/coffee/nukie/mega/shrink/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	var/new_size = clamp((M.size_multiplier - 0.01), RESIZE_MINIMUM_DORMS, RESIZE_MAXIMUM_DORMS)
	M.resize(new_size, uncapped = M.has_large_resize_bounds(), aura_animation = FALSE)
