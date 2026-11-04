/* Transformations */

/datum/reagent/slimetoxin
	name = REAGENT_MUTATIONTOXIN
	id = REAGENT_ID_MUTATIONTOXIN
	scannable = SCANNABLE_DIFFICULT
	description = "A corruptive toxin produced by slimes."
	taste_description = "sludge"
	reagent_state = LIQUID
	color = "#13BC5E"
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/slimetoxin/affect_blood(mob/living/carbon/M, alien, removed)
	if(HAS_SYNTHETIC_BIOLOGY(M))
		return

	var/mob/living/carbon/human/H = M
	if(istype(H) && (H.species.flags & NO_DNA))
		return

	if(M.dna)
		if(prob(removed * 10))
			if(prob(98))
				randmutb(M)
			else
				randmutg(M)
			domutcheck(M, null)
			M.UpdateAppearance()
	M.apply_effect(16 * removed, IRRADIATE, 0)
