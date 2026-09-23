// /datum/diagnosis: one structured report on a patient, as seen through a
// /datum/diagnostic_profile. Built by /datum/body/proc/diagnose(); every
// scanner, monitor, HUD and examine line renders one (renderers.dm).
//
// Readings the instrument can't take, or that the body plan has no system
// for, stay null. Renderers skip nulls.

/datum/diagnosis
	/// The profile the report was taken with.
	var/datum/diagnostic_profile/profile
	/// Patient name at scan time.
	var/patient_name
	/// DIAG_STATUS_*.
	var/status = DIAG_STATUS_ALIVE
	/// Overall DIAG_BAND_*.
	var/band = DIAG_BAND_NONE
	/// Feigned death was applied to this report.
	var/fake_death = FALSE
	/// world.time of death, when dead (or feigning it).
	var/time_of_death

	// --- Vitals (null = not measured / no such system) ---
	var/heart_rate
	/// list(systolic, diastolic)
	var/list/blood_pressure
	/// SpO2, 0..100
	var/oxygenation
	var/respiratory_rate
	/// Core temperature, °C.
	var/temperature
	/// "alert", "drowsy", "unresponsive" or "none".
	var/consciousness
	/// Blood volume, % of normal.
	var/blood_percent

	/// /datum/diagnosis_finding, most severe first. Lazy.
	var/list/findings
	/// Per-part integrity: list(list("name", "band", "flags" = list(...))). Lazy.
	var/list/parts
	/// TREAT_* -> DIAG_BAND_* urgency, when the profile gives hints. Lazy.
	var/list/hints

/datum/diagnosis/Destroy()
	profile = null
	QDEL_LIST(findings)
	parts = null
	hints = null
	return ..()

/datum/diagnosis/proc/add_finding(datum/diagnosis_finding/F)
	for(var/datum/diagnosis_finding/existing as anything in findings)
		if(existing.name == F.name && existing.location == F.location)
			if(_dq_band_rank(F.band) > _dq_band_rank(existing.band))
				existing.band = F.band
			qdel(F)
			return existing
	LAZYADD(findings, F)
	return F

/// Findings of `kind` (DIAG_FINDING_*), or every finding.
/datum/diagnosis/proc/findings_of(kind = null)
	. = list()
	for(var/datum/diagnosis_finding/F as anything in findings)
		if(!kind || F.kind == kind)
			. += F

/// Does the report name an affliction of `affliction_type` (or a subtype)?
/datum/diagnosis/proc/has_finding_for(affliction_type)
	for(var/datum/diagnosis_finding/F as anything in findings)
		if(F.source_type && ispath(F.source_type, affliction_type))
			return TRUE
	return FALSE

/// Worst band among findings.
/datum/diagnosis/proc/worst_finding_band()
	. = DIAG_BAND_NONE
	for(var/datum/diagnosis_finding/F as anything in findings)
		if(_dq_band_rank(F.band) > _dq_band_rank(.))
			. = F.band

/// Sort findings most severe first (stable within a band).
/datum/diagnosis/proc/sort_findings()
	if(LAZYLEN(findings) < 2)
		return
	var/list/sorted = list()
	for(var/rank in list(DIAG_BAND_CRITICAL, DIAG_BAND_SEVERE, DIAG_BAND_MODERATE, DIAG_BAND_MINOR, DIAG_BAND_NONE))
		for(var/datum/diagnosis_finding/F as anything in findings)
			if(F.band == rank)
				sorted += F
	findings = sorted


/// One finding: a condition, a lesion, a wound or a sign (a presenting
/// symptom whose cause the instrument may not see).
/datum/diagnosis_finding
	var/name
	/// DIAG_FINDING_*.
	var/kind = DIAG_FINDING_CONDITION
	/// DIAG_BAND_*.
	var/band = DIAG_BAND_MINOR
	/// Part name, when the profile localizes. Empty = systemic / unknown.
	var/location = ""
	/// Clinical description, when the profile describes.
	var/description
	/// "new" / "worsening" / "improving" / "stable", when the profile trends.
	var/trend
	/// Advice line, when the profile gives hints.
	var/hint
	/// Affliction typepath behind the finding (null for plan findings).
	var/source_type

/datum/diagnosis_finding/New(name, kind, band, location, source_type)
	..()
	src.name = name
	if(kind)
		src.kind = kind
	if(band)
		src.band = band
	src.location = location || ""
	src.source_type = source_type
