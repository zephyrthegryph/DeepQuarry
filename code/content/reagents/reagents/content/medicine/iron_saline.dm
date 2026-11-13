/// Iron saline: iron in a saline carrier. Every unit metabolised in the blood adds blood volume, up to what the species holds.
/// Carthatoline weakens it (pharmacology/interactions.dm).
/datum/reagent/iron_saline
	treatment_tags = list(TREAT_BLOOD_RESTORE = 1.5)
	name = REAGENT_IRONSALINE
	id = REAGENT_ID_IRONSALINE
	description = "Iron in a saline carrier, given to a patient who has bled. Restores blood volume quickly. Carthatoline binds the iron and weakens it."
	taste_description = "salty metal"
	reagent_state = LIQUID
	dermal_absorption = 0
	color = "#8a6a5a"
	overdose = REAGENTS_OVERDOSE * 2
	scannable = SCANNABLE_BENEFICIAL
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_DRUG
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/// Blood added to the vessel per unit of iron saline metabolised.
#define IRON_SALINE_BLOOD_PER_UNIT 2

/datum/reagent/iron_saline/affect_blood(mob/living/carbon/M, alien, removed)
	if(!ishuman(M) || HAS_SYNTHETIC_BIOLOGY(M))
		return
	var/mob/living/carbon/human/H = M
	if(!H.vessel)
		return
	var/datum/reagent/blood/own = H.get_blood(H.vessel)
	if(!own)
		return
	var/room = H.species.blood_volume - H.vessel.total_volume
	// A drug interaction (carthatoline) scales it through the body's cure modifier.
	var/modifier = H.body ? H.body.reagent_cure_modifier(id) : 1
	var/amount = min(removed * IRON_SALINE_BLOOD_PER_UNIT * modifier, room)
	if(amount <= 0)
		return
	H.vessel.add_reagent(REAGENT_ID_BLOOD, amount, own.data)
	if(GLOB.chem_trace)
		log_world("CHEM: [id] restores [amount] blood to [H] (removed [removed], room [room])")

#undef IRON_SALINE_BLOOD_PER_UNIT
