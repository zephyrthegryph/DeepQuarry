/datum/reagent/toxin/neurotoxic_protein
	name = REAGENT_NEUROTOXIC_PROTEIN
	id = REAGENT_ID_NEUROTOXIC_PROTEIN
	description = "A weak neurotoxic chemical."
	taste_description = "fish"
	reagent_state = LIQUID
	color = "#005555"
	strength = 8
	poison_affliction = /datum/affliction/poisoning/neurotoxin
	dermal_absorption = 0.4
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_NO
	industrial_use = REFINERYEXPORT_REASON_BIOHAZARD

/datum/reagent/toxin/neurotoxic_protein
	immune_species_blood = SPECIES_TAG_BIT(IS_CHIMERA) // P2-S13

/datum/reagent/toxin/neurotoxic_protein/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(!inert_for(M))
		if(M.canmove && !M.restrained() && istype(M.loc, /turf/space))
			step(M, pick(GLOB.cardinal))
		if(prob(5))
			M.emote(pick("twitch", "drool", "moan"))
		if(prob(20))
			M.injure(INJURY_NEURAL, 0.1, source = src)
