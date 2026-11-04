/datum/reagent/ethanol/vodka
	name = REAGENT_VODKA
	id = REAGENT_ID_VODKA
	description = "Number one drink AND fueling choice for Russians worldwide."
	taste_description = "grain alcohol"
	color = "#0064C8" // rgb: 0, 100, 200
	strength = 15

	glass_name = REAGENT_ID_VODKA
	glass_desc = "The glass contain wodka. Xynta."

	allergen_type = ALLERGEN_GRAINS //Vodka is made from grains

/datum/reagent/ethanol/vodka/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(!(HAS_SYNTHETIC_BIOLOGY(M)))
		M.purge_radiation(1 * removed) // purges radiation; apply_effect(IRRADIATE) here added it back (P2-F8)
