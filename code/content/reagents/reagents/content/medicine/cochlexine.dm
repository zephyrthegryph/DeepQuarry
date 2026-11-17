/// Cochlexine: an ear repair drug. It heals ear damage and clears deafness while it is in the blood. Damage past the permanent line (ear_damage 100) is
/// beyond a drug: that takes the Repair Eardrum surgery (surgery/ears.dm), after which the drug finishes the healing.
/datum/reagent/cochlexine
	name = REAGENT_COCHLEXINE
	id = REAGENT_ID_COCHLEXINE
	description = "Repairs damaged ears: ringing, muffled hearing and the deafness that follows a flashbang or a blast fade over a minute or two of a dose. It cannot rebuild an eardrum that is destroyed (the ears read as severely damaged); that needs the Repair Eardrum surgery on the head, and the drug then heals what is left. Makes the patient a little dizzy."
	taste_description = "sour metal"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#A8C8C0"
	overdose = REAGENTS_OVERDOSE
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/// Ear damage healed per tick while cochlexine is in the blood.
#define COCHLEXINE_EAR_HEAL 2

/datum/reagent/cochlexine/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_at_least(STAT_DIZZY, 2)
	if(M.ear_damage <= 0 || M.ear_damage >= EAR_DAMAGE_PERMANENT)
		return // healthy ears (a deafness that is not from damage is not touched), or an eardrum past repair: surgery only
	M.adjustEarDamage(-COCHLEXINE_EAR_HEAL, 0)
	if(M.ear_damage < EAR_DAMAGE_IMPAIRED)
		M.status_end(STAT_DEAFENED)
		M.set_sdisabilities(M.sdisabilities & (~DEAF))
