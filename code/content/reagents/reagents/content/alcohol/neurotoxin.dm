/datum/reagent/ethanol/neurotoxin
	name = REAGENT_NEUROTOXIN
	id = REAGENT_ID_NEUROTOXIN
	description = "A strong neurotoxin that puts the subject into a death-like state."
	taste_description = "a numbing sensation"
	reagent_state = LIQUID
	color = "#2E2E61"
	strength = 10

	glass_name = REAGENT_NEUROTOXIN
	glass_desc = "A drink that is guaranteed to knock you silly."
	glass_icon = DRINK_ICON_NOISY
	glass_special = list("neuroright")

	allergen_type = ALLERGEN_FRUIT|ALLERGEN_GRAINS //Made from gargle blaster which is made from vodka(grains), gin(fruit), whiskey(grains), cognac(fruit), and lime juice(fruit)

/datum/reagent/ethanol/neurotoxin/affect_ingest(mob/living/carbon/M, alien, removed)
	..()

	if(M.species.robo_ethanol_drunk || !(HAS_SYNTHETIC_BIOLOGY(M)))
		M.status_at_least(STAT_WEAKENED, 3)
