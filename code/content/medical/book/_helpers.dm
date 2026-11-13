// DQ Medical Reference — shared helper(s) that don't fit a single tab.
//
// _dq_condition_name() resolves a /datum/affliction
// typepath to its display name by reading the prototype. Used from
// multiple tab builders (conditions complications, causes produces,
// surgeries treats) to render condition cross-links.

/proc/_dq_condition_name(typepath)
	if(!ispath(typepath, /datum/affliction))
		return "[typepath]"
	var/datum/affliction/proto = dq_proto(typepath)
	return proto.name

/datum/affliction
	/// Listed in the reference book, content audits and debug pickers.
	/// FALSE for structural afflictions (injury loads) and runtime-configured
	/// ones (GM custom afflictions) that have no authored clinical picture.
	var/catalogued = TRUE
	/// TRUE when the condition recedes on its own once its cause is gone
	/// (its progress() turns progression negative), so it needs no cure.
	var/recedes_without_cause = FALSE

// Simple-body injury loads are bookkeeping, not diagnoses.
/datum/affliction/load
	catalogued = FALSE

// Abstract family bases: only their concrete subtypes are real diagnoses.
/datum/affliction/venom
	catalogued = FALSE
/datum/affliction/poisoning
	catalogued = FALSE
/datum/affliction/synthetic
	catalogued = FALSE
/datum/affliction/wound
	catalogued = FALSE
/datum/affliction/wound/synthetic
	catalogued = FALSE
// Marker left on a stump; not something to diagnose or treat.
/datum/affliction/wound/lost_limb
	catalogued = FALSE

/// Every catalogued /datum/affliction subtype. Built once. Abstract family
/// bases (`abstract_type` == their own type) are skipped.
/proc/build_dq_catalogued_affliction_types()
	var/list/types = list()
	for(var/T in subtypesof(/datum/affliction))
		var/datum/affliction/typed = T
		// Checked before building a prototype: uncatalogued families
		// (engineered contagion strains) have constructors with side effects.
		if(!initial(typed.catalogued))
			continue
		var/datum/affliction/proto = dq_proto(T)
		if(proto.catalogued && proto.abstract_type != T)
			types += T
	return types

GLOBAL_TABLE(dq_catalogued_affliction_types, GLOBAL_PROC_REF(build_dq_catalogued_affliction_types))

/// One reading a drug masks on instruments (HIDE_* in code/defines/content/drug_profile.dm) in the book's words.
GLOBAL_LIST_INIT(dq_hide_labels, list( \
	HIDE_PAIN                = "the patient's pain level and every pain finding", \
	HIDE_PAIN_LOCATION       = "where it hurts", \
	HIDE_ORGAN_MILD          = "mild organ damage", \
	HIDE_PULSE_IRREGULAR     = "an irregular pulse (reads as a normal rhythm)", \
	HIDE_INTERNAL_BLEEDING   = "internal bleeding", \
	HIDE_LUNG_HEART          = "lung and heart damage", \
	HIDE_FEVER               = "fever (the temperature reads normal)", \
	HIDE_SYMPTOM_SUPPRESSION = "withdrawal and similar signs", \
))

/// The label of a HIDE_* key.
/proc/dq_hide_label(key)
	return GLOB.dq_hide_labels[key] || "[key]"
