/datum/reagent/respirodaxon/affect_blood(mob/living/carbon/M, alien, removed)
	daxon_affect(M, removed)

/datum/reagent/respirodaxon
	treatment_tags = list(TREAT_RESPIRATORY = 1.0)
	name = REAGENT_RESPIRODAXON
	id = REAGENT_ID_RESPIRODAXON
	description = "Used to repair the tissue of the lungs and similar organs: pulmonary contusion, respiratory failure and the airway burns of an inhalation injury. The airway it heals is tender and briefly vulnerable to smoke and gas while the drug is in the blood."
	taste_description = "metallic"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#4444FF"
	metabolism = REM * 1.5
	overdose = 10
	overdose_mod = 1.75
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

TYPE_TABLE(/datum/reagent/respirodaxon, daxon_organs, list(O_LUNGS, O_VOICE, O_GBLADDER))

TYPE_TABLE(/datum/reagent/respirodaxon, daxon_partners, list(REAGENT_ID_GASTIRODAXON, REAGENT_ID_PERIDAXON))

/datum/reagent/respirodaxon/daxon_clash(mob/living/carbon/human/H, removed)
	if(H.losebreath() >= 15 && prob(H.losebreath()))
		H.status_at_least(STAT_STUNNED, 2)
	else
		H.set_losebreath(CLAMP(H.losebreath() + 3, 0, 20))

/datum/reagent/respirodaxon/daxon_alone(mob/living/carbon/human/H, removed)
	H.set_losebreath(max(H.losebreath() - 4, 0))
