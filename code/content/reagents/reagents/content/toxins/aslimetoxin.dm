/datum/reagent/aslimetoxin
	name = REAGENT_DOCILITYTOXIN
	id = REAGENT_ID_DOCILITYTOXIN
	scannable = SCANNABLE_DIFFICULT
	description = "A corruptive toxin produced by slimes."
	taste_description = "sludge"
	reagent_state = LIQUID
	color = "#FF69B4"
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/aslimetoxin/affect_blood(mob/living/carbon/M, alien, removed)
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
	M.apply_effect(6 * removed, IRRADIATE, 0)
