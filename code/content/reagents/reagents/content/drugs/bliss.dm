/datum/reagent/drugs/bliss /// Replaces Space Drugs.
	name = REAGENT_BLISS
	id = REAGENT_ID_BLISS
	description = "Known for providing a euphoric high, this psychoactive drug is often used recreationally."
	taste_description = "unpleasant bitterness"
	taste_mult = 0.4
	scannable = SCANNABLE_ADVANCED
	high_message_list = list("You don't quite know what up or down is anymore...",
	"Colors just seem much more amazing.",
	"You feel incredibly confident. No one can stop you.",
	"You clench your jaw involuntarily.",
	"You feel... unsteady.",
	"You really feel like talking about your feelings!")
	sober_message_list = list("Everything feels a little more grounded.",
	"Colors seem... flatter.",
	"Everything feels a little dull, now.")
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED // bonus
	industrial_use = REFINERYEXPORT_REASON_ILLDRUG

/datum/reagent/drugs/bliss/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	var/drug_strength = 15
	if(M.species.chem_strength_tox > 0)
		drug_strength *= M.species.chem_strength_tox
	drug_strength *= species_mult(M)

	M.status_at_least(STAT_DRUGGED, drug_strength)
	if(prob_proc == TRUE && prob(10) && isturf(M.loc) && !istype(M.loc, /turf/space) && M.canmove && !M.restrained() && !M.resting)
		step(M, pick(GLOB.cardinal))
		prob_proc = FALSE
	if(prob_proc == TRUE && prob(7))
		M.emote(pick("twitch", "drool", "moan", "giggle"))
		prob_proc = FALSE

/datum/reagent/drugs/bliss/overdose(mob/living/M as mob)
	if(prob_proc == TRUE && prob(20))
		M.status_at_least(STAT_HALLUCINATING, 5)
		prob_proc = FALSE
	M.injure(INJURY_NEURAL, 0.25*REM, source = src)
	M.injure(INJURY_TOXIN, 0.25*REM, source = src)
	..()
