/datum/reagent/ethanol/voxdelight
	name = REAGENT_VOXDELIGHT
	id = REAGENT_ID_VOXDELIGHT
	description = "A dangerous combination of all things flammable. Why would you drink this?"
	taste_description = "corrosive death"
	color = "#7c003a" // rgb(124, 0, 58)
	strength = 10

	glass_name = REAGENT_VOXDELIGHT
	glass_desc = "Not recommended if you enjoy having organs."
	coolant_modifier = 1.25

/datum/reagent/ethanol/voxdelight/affect_ingest(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	// Kept: vox are treated where everyone else is poisoned (a per-unit mend, not a dose-level tag).
	if(alien == IS_VOX)
		// Species-gated: mends directly.
		M.mend(TREAT_ANTITOXIN, 0.5 * removed)
		return
	M.injure(INJURY_TOXIN, 3 * removed, source = src)
