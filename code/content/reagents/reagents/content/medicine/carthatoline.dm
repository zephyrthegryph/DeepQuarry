/datum/reagent/carthatoline
	treatment_tags = list(TREAT_ANTITOXIN = 1.0, TREAT_HEPATORENAL = 0.4)
	// It slows the refill of blood (the stat's floor is no refill at all).
	factors = alist(STAT_BLOOD_REGEN = -0.05)
	purges_stomach = TRUE
	name = REAGENT_CARTHATOLINE
	id = REAGENT_ID_CARTHATOLINE
	description = REAGENT_CARTHATOLINE + " is a strong evacuant used to treat severe poisoning: heavy metals, phoron and other deep toxins, with a mild repair of the liver and kidneys. It empties the stomach (swallowed drugs are lost), slows the body's refill of blood and leaves the patient profoundly sick."
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#225722"
	scannable = SCANNABLE_BENEFICIAL
	overdose = REAGENTS_OVERDOSE * 0.5
	overdose_mod = 0 // Not used, but it shouldn't deal toxin damage anyways. Carth heals toxins!
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_SPECIALDRUG

/datum/reagent/carthatoline
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/carthatoline/affect_blood(mob/living/carbon/M, alien, removed)
	if(M.injury_load(INJURY_CATEGORY_TOXIC) && prob(10))
		M.vomit(1)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/internal/liver/L = H.organ_in(O_LIVER)
		if(istype(L) && L.is_robotic())
			return
		// Liver repair is carthatoline's TREAT_HEPATORENAL tag (body/treatment.dm).
		if(alien == IS_SLIME)
			H.status_set(STAT_DRUGGED, max(M.status_units(STAT_DRUGGED), 5))

/datum/reagent/carthatoline/overdose(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_PAIN, 2, source = src)
	var/mob/living/carbon/human/H = M
	var/obj/item/organ/internal/stomach/st = H.organ_in(O_STOMACH)
	if(st)
		H.injure(INJURY_BLUNT, removed * 2, st, src, flags = INJURE_IGNORE_RESISTANCE) // Causes stomach contractions, makes sense for an overdose to make it much worse.
