/datum/reagent/lithium
	name = REAGENT_LITHIUM
	id = REAGENT_ID_LITHIUM
	description = "A chemical element, used as antidepressant."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_BENEFICIAL
	color = "#808080"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR
	coolant_modifier = 0.15

/datum/reagent/lithium
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/lithium/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.canmove && !M.restrained() && istype(M.loc, /turf/space))
		step(M, pick(GLOB.cardinal))
	if(prob(5))
		M.emote(pick("twitch", "drool", "moan"))
