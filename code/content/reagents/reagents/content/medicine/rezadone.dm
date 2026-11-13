// B15: leporazine's temperature correction is its TREAT_THERMOREGULATION tag,
// applied by the thermoregulation life stage (no second, unscaled write here).

/datum/reagent/rezadone
	// "Almost magical": a strong generic on top of its genetic specialty.
	treatment_tags = list(
		TREAT_GENETIC_REPAIR = 1.0,
		TREAT_TISSUE_REPAIR = 0.8,
		TREAT_BURN_CARE = 0.8,
		TREAT_ANTITOXIN = 0.8,
		TREAT_ANTIRADIATION = 0.25,
		TREAT_OXYGENATION = 0.1,
	)
	strains = alist(O_LIVER = DRUG_STRAIN_HEAVY)
	name = REAGENT_REZADONE
	id = REAGENT_ID_REZADONE
	description = "A powder with almost magical properties: it repairs genetic damage and, more moderately, tissue damage, burns and poisoning. It is made only from reagent-grade ingredients, it strains the liver heavily, it undoes arithrazine, and excessive consumption has side effects."
	taste_description = "bitterness"
	reagent_state = SOLID
	dermal_absorption = 0 //solid powder
	color = "#669900"
	overdose = REAGENTS_OVERDOSE
	overdose_mod = 2
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_CLONEDRUG

/datum/reagent/rezadone
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/rezadone/affect_blood(mob/living/carbon/M, alien, removed)
	var/mob/living/carbon/human/H = M
	if(alien == IS_SLIME && istype(H))
		// each channel (red, green, blue) of skin, hair and beard moves halfway to 50 at a coin flip; a zero channel stays
		for(var/channel in 1 to 3)
			if(!prob(50))
				continue
			var/list/channels = hex2rgb(H.looks.skin_color)
			var/value = channels[channel]
			if(value)
				H.looks.set_skin_color(colour_set_channel(H.looks.skin_color, channel, (value + 50) / 2))
			channels = hex2rgb(H.looks.hair_color)
			value = channels[channel]
			if(value)
				H.looks.set_hair_color(colour_set_channel(H.looks.hair_color, channel, (value + 50) / 2))
			channels = hex2rgb(H.looks.facial_color)
			value = channels[channel]
			if(value)
				H.looks.set_facial_color(colour_set_channel(H.looks.facial_color, channel, (value + 50) / 2))
	// Rezadone's regeneration is its treatment_tags profile.
	if(dose > 3)
		M.set_status_flags(M.status_flags & ~DISFIGURED)
	if(dose > 10)
		M.status_adjust(STAT_DIZZY, 5)
		M.status_adjust(STAT_JITTERY, 5)
