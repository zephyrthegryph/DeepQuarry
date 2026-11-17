/// Anthelmin: an anti-parasitic. It poisons parasitic organisms (the malignant parasite growths, code/domains/body/organs/internal/malignant/) in the host and
/// leaves the patient's own tissue alone; a tumour is not a parasite and does not answer to it (tumours need the Resect Necrotic Tissue surgery).
/datum/reagent/anthelmin
	name = REAGENT_ANTHELMIN
	id = REAGENT_ID_ANTHELMIN
	description = "An anti-parasitic. A parasitic organism lodged in the body (a body scanner reads it as a parasitic organism) shrivels and dies over a few minutes of treatment; a tumour does not respond to it and needs to be cut out. Strains the liver a little."
	taste_description = "bitter chalk"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#C8B070"
	overdose = REAGENTS_OVERDOSE
	strains = alist(O_LIVER = DRUG_STRAIN_MILD)
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/// Chance each tick that anthelmin kills a parasite growth in its host.
#define ANTHELMIN_KILL_CHANCE 8

/datum/reagent/anthelmin/affect_blood(mob/living/carbon/M, alien, removed)
	if(!ishuman(M))
		return
	var/mob/living/carbon/human/H = M
	for(var/obj/item/organ/internal/malignant/parasite/P in H.internal_organ_list())
		if(!prob(ANTHELMIN_KILL_CHANCE))
			continue
		log_game("MEDICAL: anthelmin killed [P] ([P.type]) in [key_name(H)]")
		to_chat(H, span_notice("Something inside you shudders and goes still."))
		P.removed()
		spent(P)
