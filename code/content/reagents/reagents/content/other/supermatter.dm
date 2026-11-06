/datum/reagent/supermatter
	name = REAGENT_SUPERMATTER
	id = REAGENT_ID_SUPERMATTER
	color = "#fffd6b"
	reagent_state = SOLID
	affects_dead = TRUE
	affects_robots = TRUE
	scannable = SCANNABLE_UNSCANNABLE
	description = "The immense power of a supermatter crystal, in liquid form. You're not entirely sure how that's possible, but it's probably best handled with care."
	taste_description = "taffy" // 0. The supermatter is tasty, tasty taffy.
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_MATSCI

// Same as if you boop it wrong. It touches you, you die
/datum/reagent/supermatter/affect_touch(mob/living/carbon/M, alien, removed)
	M.ash()

/datum/reagent/supermatter/affect_ingest(mob/living/carbon/M, alien, removed)
	M.ash()

/datum/reagent/supermatter/affect_blood(mob/living/carbon/M, alien, removed)
	M.ash()
