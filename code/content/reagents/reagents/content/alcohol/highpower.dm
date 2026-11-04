// Low Power's mild antitoxin action is its treatment_tags profile.

/datum/reagent/drink/highpower
	factors = alist(STAT_SLOWDOWN = -1, STAT_PENALTY_SCALE = 0.5)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_HIGHPOWER
	id = REAGENT_ID_HIGHPOWER
	description = "A strange, softly crackling drink, smelling just like lightning's just struck, twice. It's rather difficult to make this without busting the lights."
	taste_description = "copper, ozone, and pain"
	color = "#a2f563"

	glass_name = REAGENT_ID_HIGHPOWER
	glass_desc = "A strange, softly crackling drink, smelling just like lightning's just struck, twice. It's rather difficult to make this without busting the lights."

/datum/reagent/drink/highpower
	immune_species_ingest = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/drink/highpower/affect_ingest(mob/living/carbon/M, alien, removed)
	if(prob(5))
		M.say("!skin's crackles with energy and seems to be in pain.")
		M.custom_pain("You feel painful electricity running through your body, like adrenaline, and like your blood's boiling!",30)
		M.status_adjust(STAT_WEAKENED, 3)		//Getting sapped makes the victim fall
		M.status_at_least(STAT_STUNNED, 3)
