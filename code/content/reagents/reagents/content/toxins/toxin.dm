/* Toxins, poisons, venoms */

/datum/reagent/toxin
	name = REAGENT_TOXIN
	id = REAGENT_ID_TOXIN
	description = "A toxic chemical."
	taste_description = "bitterness"
	taste_mult = 1.2
	reagent_state = LIQUID
	color = "#CF3600"
	metabolism = REM * 0.25 // 0.05 by default. Hopefully enough to get some help, or die horribly, whatever floats your boat
	filtered_organs = list(O_LIVER, O_KIDNEYS)
	scannable = SCANNABLE_DIFFICULT
	var/strength = 4 // How much damage it deals per unit
	/// Affliction this poison causes instead of generic toxic poisoning
	/// (typepath; null = the body's default response). See toxicology.dm.
	var/poison_affliction
	dermal_absorption = 0
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR
	// Prometheans take a quarter dose, which halves the standard tox since they are 'Small' for flaps.
	species_strength = alist(IS_SLIME = 0.25)

/datum/reagent/toxin/affect_blood(mob/living/carbon/M, alien, removed)
	var/poison_strength = strength * M.species.chem_strength_tox
	if(strength && !inert_for(M))
		if(issmall(M)) removed *= 2 // Small bodymass, more effect from lower volume.
		removed *= species_mult(M)
		// Kept: a Promethean dose-gated behaviour (nourishment or repair), not a strength.
		if(alien == IS_SLIME)
			if(dose >= 10)
				M.adjust_nutrition(poison_strength * removed) // Body has to deal with the massive influx of toxins, rather than try using them to repair.
			else
				//Doses of toxins below 10 units, and 10 strength, are capable of providing useful compounds for repair.
				// Promethean-only, dose-gated: a species behaviour, not a treatment profile, so it mends directly.
				M.mend(TREAT_TISSUE_REPAIR, (10/poison_strength) * removed)
				M.mend(TREAT_BURN_CARE, (10/poison_strength) * removed)
		M.injure(INJURY_TOXIN, poison_strength * removed, source = src, affliction = poison_affliction)

/datum/reagent/toxin/plasticide
	name = REAGENT_PLASTICIDE
	id = REAGENT_ID_PLASTICIDE
	description = "Liquid plastic, do not eat."
	dermal_absorption = 0
	taste_description = "plastic"
	reagent_state = LIQUID
	color = "#CF3600"
	strength = 5
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/toxin/lead
	name = REAGENT_LEAD
	id = REAGENT_ID_LEAD
	description = "Elemental Lead."
	color = "#273956"
	dermal_absorption = 0 //It's lead.
	strength = 4
	poison_affliction = /datum/affliction/poisoning/heavy_metal
	supply_conversion_value = 0.5 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/toxin/spidertoxin
	name = REAGENT_SPIDERTOXIN
	id = REAGENT_ID_SPIDERTOXIN
	description = "A liquifying toxin produced by giant spiders."
	color = "#2CE893"
	strength = 5
	poison_affliction = /datum/affliction/venom/arachnid
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/toxin/fertilizer //Reagents used for plant fertilizers.
	name = REAGENT_FERTILIZER
	id = REAGENT_ID_FERTILIZER
	description = "A chemical mix good for growing plants with."
	taste_description = "plant food"
	taste_mult = 0.5
	dermal_absorption = 0.4 //Organo-phosphate poison... Give them a unique effect someday?
	reagent_state = LIQUID
	strength = 0.5 // It's not THAT poisonous.
	color = "#664330"
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_FOOD

/datum/reagent/toxin/fertilizer/eznutrient
	name = REAGENT_EZNUTRIENT
	id = REAGENT_ID_EZNUTRIENT

/datum/reagent/toxin/fertilizer/left4zed
	name = REAGENT_LEFT4ZED
	id = REAGENT_ID_LEFT4ZED

/datum/reagent/toxin/fertilizer/robustharvest
	name = REAGENT_ROBUSTHARVEST
	id = REAGENT_ID_ROBUSTHARVEST
