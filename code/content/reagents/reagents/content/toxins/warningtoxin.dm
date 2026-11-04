/datum/reagent/toxin/warningtoxin
	factors = alist(STAT_SLOWDOWN = 5, STAT_PENALTY_SCALE = 1.25)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_WARNINGTOXIN
	id = REAGENT_ID_WARNINGTOXIN
	description = "A weaker toxin produced by giant spiders applied only in warning bites, known to slow a people down a lot."
	color = "#2CE893"
	strength = 1
	poison_affliction = /datum/affliction/venom/arachnid

/datum/reagent/toxin/warningtoxin
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/toxin/warningtoxin/affect_blood(mob/living/carbon/M, alien, removed)
	var/poison_strength = strength * M.species.chem_strength_tox
	if(strength)
		M.injure(INJURY_TOXIN, poison_strength * removed, source = src, affliction = poison_affliction)
		M.status_at_least(STAT_DRUGGED, 10)
		M.status_adjust(STAT_JITTERY, 5)
