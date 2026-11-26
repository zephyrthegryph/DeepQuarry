/// Naloxone: the opioid antagonist. It knocks oxycodone and tramadol off their receptors, so an opioid overdose lifts within a few ticks of the dose.
/// Made by reducing oxycodone (blocks/structures.dm); it carries no analgesia of its own, and a patient who was relying on the opioid for pain feels it all again.
/datum/reagent/naloxone
	treatment_tags = list(TREAT_OPIOID_ANTAGONIST = 1.0)
	// Whatever pain the opioid was holding back comes back at once.
	factors = alist(STAT_INCOMING_PAIN = 1.2)
	name = REAGENT_NALOXONE
	id = REAGENT_ID_NALOXONE
	description = "An opioid antagonist: it strips oxycodone and tramadol out of the blood within a few seconds, ending an opioid overdose (slow breathing, drowsiness, blue lips) and the pain relief with it. It has no effect on anything else. A dose is worn off in a few minutes, so a long-lasting opioid can come back and the patient needs watching."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#D8C8E8"
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/// Units of opioid stripped out of the blood each tick while naloxone is in it.
#define NALOXONE_OPIOID_REMOVAL 4

/datum/reagent/naloxone/affect_blood(mob/living/carbon/M, alien, removed)
	if(!M.bloodstr)
		return
	for(var/datum/reagent/R in M.bloodstr.reagent_list)
		if(istype(R, /datum/reagent/oxycodone) || istype(R, /datum/reagent/tramadol))
			R.remove_self(NALOXONE_OPIOID_REMOVAL)
