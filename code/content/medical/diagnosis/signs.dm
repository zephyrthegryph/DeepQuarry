// Vitals-level signs: what the basic health analyzer says of a condition it can't image (profile.signs), and what the naked eye
// sees whatever symptoms rolled (visible_sign). A sign names the kind of trouble and, for organ damage, the organ; the condition's
// name, its level and the lab detail (pathogen, exact numbers) stay with the advanced and lab tools, so the tiers still differ.
// diagnose_afflictions() (diagnose.dm) asks `signs_label()` only when `perceived_by()` is false, so an instrument that images the
// condition keeps reporting it by name.

// --- Shock ----------------------------------------------------------------------------------------------------------------

/datum/affliction/hypovolemic_shock/signs_label()
	return "shock"

/datum/affliction/burn_shock/signs_label()
	return "shock"

/datum/affliction/septic_shock/signs_label()
	return "shock"

/datum/affliction/septic_shock/visible_sign()
	return "They are pale, clammy and flushed with fever, breathing fast."

// --- Infection and fever --------------------------------------------------------------------------------------------------

/datum/affliction/sepsis/signs_label()
	return "fever, infection suspected"

/datum/affliction/sepsis/visible_sign()
	return "They look pale and feverish, flushed and sweating."

/datum/affliction/cellulitis/signs_label()
	return "fever, infection suspected"

/datum/affliction/wound_infection/signs_label()
	return "fever, infection suspected"

/datum/affliction/appendiceal_sepsis/signs_label()
	return "fever, infection suspected"

/// A strain the scanners can't see (hidden or dormant) stays hidden; a carrier shows nothing; every other disease reads as a fever.
/datum/affliction/contagion/signs_label()
	if((visibility_flags & HIDDEN_SCANNER) || global_flag_check(virus_modifiers, DORMANT) || global_flag_check(virus_modifiers, CARRIER))
		return null
	return "fever, infection suspected"

// --- Bones and bleeding ----------------------------------------------------------------------------------------------------

/datum/affliction/untreated_fracture/signs_label()
	return "suspected fracture"

/datum/affliction/malunion/signs_label()
	return "suspected fracture"

/datum/affliction/internal_hemorrhage/signs_label()
	return "suspected internal bleeding"

/datum/affliction/lacerated_artery/signs_label()
	return "suspected internal bleeding"

/datum/affliction/wound/internal_bleeding/signs_label()
	return "suspected internal bleeding"

// --- Organs ---------------------------------------------------------------------------------------------------------------

/datum/affliction/lesion/signs_label()
	return location ? "organ damage ([lowertext(location.name)])" : "organ damage"

/datum/affliction/heart_damage/signs_label()
	return "organ damage (heart)"

/datum/affliction/hepatic_failure/signs_label()
	return "organ damage (liver)"

/datum/affliction/renal_failure/signs_label()
	return "organ damage (kidneys)"

/datum/affliction/brain_damage/signs_label()
	return "organ damage (brain)"

/datum/affliction/ischemic_vision_loss/signs_label()
	return "organ damage (eyes)"

/datum/affliction/pulmonary_contusion/signs_label()
	return "organ damage (lungs)"

/datum/affliction/respiratory_failure/signs_label()
	return "organ damage (lungs)"

// --- Oxygenation and temperature --------------------------------------------------------------------------------------------

/datum/affliction/tissue_hypoxia/signs_label()
	return "low oxygenation"

/datum/affliction/airway_obstruction/signs_label()
	return "low oxygenation"

/datum/affliction/airway_edema/signs_label()
	return "low oxygenation"

/datum/affliction/respiratory_arrest/signs_label()
	return "low oxygenation"

/datum/affliction/pneumothorax/signs_label()
	return "low oxygenation"

/datum/affliction/hypothermia/signs_label()
	return "hypothermia"

/datum/affliction/heatstroke/signs_label()
	return "heatstroke"
