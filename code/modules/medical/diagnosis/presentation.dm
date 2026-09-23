// How afflictions present to instruments: the House MD layer.
//
// Each affliction declares which senses (PRESENT_*) can detect it through
// `presentation`. Left null, it defaults by family (get_presentation()):
//   load (simple / machine bodies)    everything: the injury is the diagnosis
//   external wound                    visible, palpable, any analyzer
//   internal wound (arterial bleed)   internal imaging
//   lesion (organ integrity)          internal imaging
//   synthetic-only fault              synthetic diagnostic bus
//   nanite fault                      nanite telemetry and the synthetic bus
//   organic injury (injury_category)  surface sensors and up
//   other organic conditions          internal imaging and up
// A condition that needs a specific test sets `presentation = PRESENT_LAB`
// (only the body scanner and phasic analyzer find it). Its symptoms still
// present on their own (signs), so a doctor sees the evidence first and has
// to run the right test to name the cause.

/datum/affliction
	/// PRESENT_* senses that detect this affliction. Null = family default.
	var/presentation

/// Senses (PRESENT_*) that detect this affliction.
/datum/affliction/proc/get_presentation()
	if(!isnull(presentation))
		return presentation
	if(!(biology & BIOLOGY_ORGANIC))
		. = NONE
		if(biology & BIOLOGY_SYNTHETIC)
			. |= PRESENT_SYNTHETIC
		if(biology & BIOLOGY_NANOFORM)
			. |= PRESENT_NANITE | PRESENT_SYNTHETIC
		return
	if(injury_category)
		return PRESENT_SURFACE | PRESENT_INTERNAL | PRESENT_LAB
	return PRESENT_INTERNAL | PRESENT_LAB

/// Can an instrument with profile `P` detect this affliction?
/datum/affliction/proc/perceived_by(datum/diagnostic_profile/P)
	if(!(get_presentation() & P.senses))
		return FALSE
	return (body ? body.biology_of(location) : biology) & P.biology

/// 0..100 how bad this affliction is, for banding and urgency.
/datum/affliction/proc/diagnostic_severity()
	return severity

/// Name a report uses for this affliction.
/datum/affliction/proc/diagnostic_name()
	return name

/// Extra advice line a hint-capable profile shows, or null.
/datum/affliction/proc/diagnostic_hint(datum/diagnostic_profile/P)
	return null

/// DIAG_FINDING_* kind of the finding this affliction produces.
/datum/affliction/proc/finding_kind()
	return DIAG_FINDING_CONDITION


// --- Family defaults -------------------------------------------------------------

/datum/affliction/load/get_presentation()
	return isnull(presentation) ? PRESENT_ALL : presentation

/datum/affliction/wound/get_presentation()
	if(!isnull(presentation))
		return presentation
	if(internal)
		return PRESENT_INTERNAL | PRESENT_LAB
	if(!(biology & BIOLOGY_ORGANIC))
		return PRESENT_VISIBLE | PRESENT_PALPATION | PRESENT_SYNTHETIC
	return PRESENT_VISIBLE | PRESENT_PALPATION | PRESENT_SURFACE | PRESENT_INTERNAL | PRESENT_LAB

/datum/affliction/wound/diagnostic_severity()
	var/obj/item/organ/external/E = location
	var/max_damage = istype(E) ? E.max_damage : 0
	return max_damage > 0 ? clamp(damage / max_damage * 100, 0, 100) : clamp(damage, 0, 100)

/datum/affliction/wound/diagnostic_name()
	return desc || name

/datum/affliction/wound/finding_kind()
	return DIAG_FINDING_WOUND

/datum/affliction/lesion/get_presentation()
	return isnull(presentation) ? (PRESENT_INTERNAL | PRESENT_LAB) : presentation

/datum/affliction/lesion/finding_kind()
	return DIAG_FINDING_LESION

/// GM afflictions keep their per-instance visibility: an analyzer tier for
/// handheld instruments, an on/off switch for medbay machines.
/datum/affliction/custom/perceived_by(datum/diagnostic_profile/P)
	if(!(P.senses & (PRESENT_SURFACE | PRESENT_INTERNAL | PRESENT_LAB)))
		return FALSE
	if(P.scanner_machine)
		return showscanner
	return P.scan_level >= advscan

/datum/affliction/custom/diagnostic_hint(datum/diagnostic_profile/P)
	return P.scan_level >= advscan_cure ? cure_hint() : null
