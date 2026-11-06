/////////////////////////////Event only nukie//////////////////////////////////////

/datum/reagent/drink/coffee/nukie/mega/one //Basically macrocillin but for ingesting
	treatment_tags = list(TREAT_TISSUE_REPAIR = 0.3, TREAT_BURN_CARE = 0.3)
	factors = alist(STAT_DARKSIGHT = 1, STAT_SLOWDOWN = -1, STAT_PENALTY_SCALE = 0.5)
	name = REAGENT_NUKIEONE
	id = REAGENT_ID_NUKIEONE
	color = "#90ed87"
	taste_description = "everything"
	overdose = 10
	adj_drowsy = -50
	adj_sleepy = -100

/datum/reagent/drink/coffee/nukie/mega/one/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	// Its trauma and burn repair is the treatment_tags profile.

/datum/reagent/drink/coffee/nukie/mega/one/overdose(mob/living/carbon/M, alien, removed)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		H.status_adjust(STAT_BLURRY, 20)
		var/od_harm = min(removed * overdose_mod * round(3 + 3 * volume / overdose), 1)
		H.injure_many(alist(INJURY_TOXIN = od_harm, INJURY_BURN = od_harm, INJURY_BLUNT = od_harm), source = src)
		H.apply_body_effect(/datum/body_effect/berserk, 2 SECONDS, suppress_output = TRUE)
