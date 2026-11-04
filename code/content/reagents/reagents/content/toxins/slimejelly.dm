/datum/reagent/slimejelly
	species_factors = alist(IS_SLIME = alist(STAT_ANALGESIA = 45))
	name = REAGENT_SLIMEJELLY
	id = REAGENT_ID_SLIMEJELLY
	scannable = SCANNABLE_ADVANCED
	description = "A gooey semi-liquid produced from one of the deadliest lifeforms in existence. SO REAL."
	taste_description = "slime"
	taste_mult = 1.3
	reagent_state = LIQUID
	color = "#801E28"
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/slimejelly
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/slimejelly/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_SLIME) //Partially made of the stuff. Why would it hurt them?
		if(prob(75))
			// Random species-gated bursts: can't be a continuous tag, so it mends directly.
			M.mend(TREAT_TISSUE_REPAIR, 25 * removed)
			M.mend(TREAT_BURN_CARE, 25 * removed)
			M.mend(TREAT_ANTITOXIN, rand(10, 30) * removed)
			M.status_at_least(STAT_DRUGGED, 10)
	else
		if(prob(10))
			to_chat(M, span_danger("Your insides are burning!"))
			M.injure(INJURY_TOXIN, rand(100, 300) * removed, source = src)
		else if(prob(40))
			// Random burst: mends directly.
			M.mend(TREAT_TISSUE_REPAIR, 25 * removed)
