/datum/reagent/mercury
	name = REAGENT_MERCURY
	id = REAGENT_ID_MERCURY
	description = "A chemical element."
	taste_mult = 0 //mercury apparently is tasteless. IDK
	reagent_state = LIQUID
	scannable = SCANNABLE_ADVANCED
	color = "#484848"
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/mercury
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/mercury/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.canmove && !M.restrained() && istype(M.loc, /turf/space))
		step(M, pick(GLOB.cardinal))
	if(prob(5))
		M.emote(pick("twitch", "drool", "moan"))
	M.injure(INJURY_NEURAL, 0.5 * removed, source = src)
	M.injure(INJURY_TOXIN, 0.25 * removed, source = src, affliction = /datum/affliction/poisoning/heavy_metal)
