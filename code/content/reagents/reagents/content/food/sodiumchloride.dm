/* Non-food stuff like condiments */

/datum/reagent/sodiumchloride
	name = REAGENT_SODIUMCHLORIDE
	id = REAGENT_ID_SODIUMCHLORIDE
	description = "A salt made of sodium chloride. Commonly used to season food."
	taste_description = "salt"
	reagent_state = SOLID
	color = "#FFFFFF"
	overdose = REAGENTS_OVERDOSE
	ingest_met = REM
	allergen_type = ALLERGEN_SALT
	cup_prefix = "salty"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_FOOD
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_BURN = 1))

/datum/reagent/sodiumchloride/affect_ingest(mob/living/carbon/M, alien, removed)
	var/pass_mod = rand(3,5)
	var/passthrough = (removed - (removed/pass_mod)) //Some may be nullified during consumption, between one third and one fifth.
	affect_blood(M, alien, passthrough)
	// The passthrough acts as blood, so it carries the blood route's species reaction.
	apply_species_injuries(M, species_injuries_blood, passthrough)
