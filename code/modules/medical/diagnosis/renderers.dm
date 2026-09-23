// Diagnosis renderers. Every device renders the same /datum/diagnosis; the
// profile it was taken with already decided what is in it.
//
//   render_chat()      HTML for chat (analyzers, cyborg analyzer, admin scan)
//                      and printouts
//   report_data()      list for the TGUI (body scanner, operating computer,
//                      kiosk, sleepers); matches tgui/.../common/Diagnosis.tsx
//   examine_lines()    short lines for examine text
//   hud_status()       "dead" / "critical" / "ill" / "healthy" for HUD icons
//   sensor_status()    coarse suit-sensor status for the crew monitor

/// Human-readable label for a treatment mechanism.
/proc/treatment_tag_label(tag)
	var/static/list/labels = list(
		TREAT_HEMOSTATIC = "hemostatic (stop bleeding)",
		TREAT_TISSUE_REPAIR = "soft-tissue repair",
		TREAT_BONE_REPAIR = "bone repair",
		TREAT_BURN_CARE = "burn care",
		TREAT_ANTIMICROBIAL = "antimicrobial",
		TREAT_ANTITOXIN = "antitoxin",
		TREAT_OXYGENATION = "oxygenation",
		TREAT_NEURAL_REPAIR = "neural repair",
		TREAT_CARDIAC = "cardiac repair",
		TREAT_RESPIRATORY = "respiratory repair",
		TREAT_HEPATORENAL = "hepatorenal repair",
		TREAT_OCULAR = "ocular repair",
		TREAT_ANTIRADIATION = "anti-radiation",
		TREAT_GENETIC_REPAIR = "genetic repair",
		TREAT_THERMOREGULATION = "thermoregulation",
		TREAT_BLOOD_RESTORE = "blood restoration",
		TREAT_CIRCULATORY = "circulatory support",
		TREAT_ANALGESIC = "analgesia",
		TREAT_STIMULANT = "stimulant",
		TREAT_PLATING_REPAIR = "plating repair",
		TREAT_WIRING_REPAIR = "wiring repair",
		TREAT_SYSTEM_RESTORE = "system restore",
		TREAT_COOLANT = "coolant",
		TREAT_CALIBRATION = "recalibration",
		TREAT_SURGICAL_REPAIR = "surgical repair",
		TREAT_RESECTION = "surgical resection",
		TREAT_AIRWAY = "airway management",
		TREAT_VENTILATION = "assisted ventilation",
		TREAT_DECOMPRESSION = "chest decompression",
		TREAT_DEFIBRILLATION = "defibrillation",
		TREAT_CHEST_COMPRESSION = "chest compressions",
		TREAT_VASOPRESSOR = "vasopressor",
		TREAT_DIGESTIVE = "digestive repair",
	)
	return labels[tag] || tag

/proc/_diag_band_span(band, text)
	switch(band)
		if(DIAG_BAND_CRITICAL)
			return span_danger(span_bold(text))
		if(DIAG_BAND_SEVERE)
			return span_danger(text)
		if(DIAG_BAND_MODERATE)
			return span_warning(text)
	return span_notice(text)


// --- Chat ------------------------------------------------------------------------

/datum/diagnosis/proc/render_chat()
	var/list/lines = list()
	var/status_text
	switch(status)
		if(DIAG_STATUS_DEAD)
			status_text = span_danger("deceased")
		if(DIAG_STATUS_CRITICAL)
			status_text = span_danger("critical")
		else
			status_text = _diag_band_span(band, band == DIAG_BAND_NONE ? "stable" : "[band] distress")
	lines += span_notice("[capitalize(profile.name)] results for [patient_name]: [status_text]")
	var/vitals_text = render_vitals_text()
	if(vitals_text)
		lines += span_notice(vitals_text)
	if(time_of_death && status == DIAG_STATUS_DEAD)
		lines += span_notice("Time of death: [worldtime2stationtime(time_of_death)]")
	if(!LAZYLEN(findings))
		lines += span_notice("No abnormal findings.")
	for(var/datum/diagnosis_finding/F as anything in findings)
		var/text = capitalize(F.name)
		if(F.location)
			text += " ([F.location])"
		if(F.kind != DIAG_FINDING_SIGN)
			text += " - [F.band]"
		if(F.trend)
			text += ", [F.trend]"
		lines += _diag_band_span(F.band, text)
		if(F.description)
			lines += span_italics(span_notice("&emsp;[F.description]"))
		if(F.hint)
			lines += span_notice("&emsp;[F.hint]")
	for(var/list/part in parts)
		if(part["band"] == DIAG_BAND_NONE && !length(part["flags"]))
			continue
		var/list/flags = part["flags"]
		lines += _diag_band_span(part["band"], "[capitalize(part["name"])]: [part["band"]][length(flags) ? " \[[flags.Join(", ")]\]" : ""]")
	if(LAZYLEN(hints))
		var/list/wanted = list()
		for(var/tag in hints)
			wanted += "[treatment_tag_label(tag)] ([hints[tag]])"
		lines += span_notice("Responds to: [wanted.Join(", ")].")
	return lines.Join("<br>")

/// One line of vitals, or null when nothing was measured.
/datum/diagnosis/proc/render_vitals_text()
	var/list/readings = list()
	if(!isnull(heart_rate))
		readings += "HR [heart_rate] bpm"
	if(blood_pressure)
		readings += "BP [blood_pressure[1]]/[blood_pressure[2]]"
	if(!isnull(oxygenation))
		readings += "SpO2 [oxygenation]%"
	if(!isnull(respiratory_rate))
		readings += "RR [respiratory_rate]/min"
	if(!isnull(temperature))
		readings += "T [temperature]&deg;C"
	if(consciousness)
		readings += "consciousness: [consciousness]"
	if(!isnull(blood_percent))
		readings += "blood volume [blood_percent]%"
	return length(readings) ? readings.Join(" | ") : null


// --- TGUI ------------------------------------------------------------------------

/datum/diagnosis/proc/report_data()
	var/list/finding_data = list()
	for(var/datum/diagnosis_finding/F as anything in findings)
		finding_data += list(list(
			"name" = F.name,
			"kind" = F.kind,
			"band" = F.band,
			"location" = F.location,
			"description" = F.description,
			"trend" = F.trend,
			"hint" = F.hint,
		))
	var/list/hint_data = list()
	for(var/tag in hints)
		hint_data += list(list("tag" = tag, "label" = treatment_tag_label(tag), "band" = hints[tag]))
	return list(
		"status" = status,
		"band" = band,
		"vitals" = list(
			"heartRate" = heart_rate,
			"bloodPressure" = blood_pressure,
			"oxygenation" = oxygenation,
			"respiratoryRate" = respiratory_rate,
			"temperature" = temperature,
			"consciousness" = consciousness,
			"bloodPercent" = blood_percent,
		),
		"findings" = finding_data,
		"parts" = parts || list(),
		"hints" = hint_data,
	)


// --- Examine ---------------------------------------------------------------------

/// Lines for examine text: what the naked eye sees (visible wounds and signs).
/datum/diagnosis/proc/examine_lines()
	. = list()
	for(var/datum/diagnosis_finding/F as anything in findings)
		if(F.kind == DIAG_FINDING_SIGN)
			. += F.name


// --- HUD / sensors -------------------------------------------------------------------

/// Medical HUD status: "dead", "critical", "ill" or "healthy".
/datum/diagnosis/proc/hud_status()
	switch(status)
		if(DIAG_STATUS_DEAD)
			return "dead"
		if(DIAG_STATUS_CRITICAL)
			return "critical"
	return _dq_band_rank(band) >= _dq_band_rank(DIAG_BAND_SEVERE) ? "ill" : "healthy"

/// Coarse suit-sensor status from vitality and criticality alone.
/proc/sensor_status(mob/living/L)
	if(L.stat == DEAD)
		return DIAG_STATUS_DEAD
	if(L.is_critical())
		return DIAG_STATUS_CRITICAL
	return dq_qualitative_vitality_band(L.vitality())

/// Examine lines for a machine chassis (cyborgs, AI cores): what the naked eye
/// sees of its structural and thermal load.
/proc/machine_examine_lines(mob/living/L)
	. = list()
	var/datum/diagnosis/D = L.diagnose(/datum/diagnostic_profile/glance)
	var/dent = DIAG_BAND_NONE
	var/char = DIAG_BAND_NONE
	for(var/datum/diagnosis_finding/F as anything in D?.findings)
		if(ispath(F.source_type, /datum/affliction/load/trauma) && _dq_band_rank(F.band) > _dq_band_rank(dent))
			dent = F.band
		else if(ispath(F.source_type, /datum/affliction/load/burn) && _dq_band_rank(F.band) > _dq_band_rank(char))
			char = F.band
	qdel(D)
	if(dent != DIAG_BAND_NONE)
		. += _dq_band_rank(dent) >= _dq_band_rank(DIAG_BAND_SEVERE) ? span_boldwarning("It looks severely dented!") : span_warning("It looks slightly dented.")
	if(char != DIAG_BAND_NONE)
		. += _dq_band_rank(char) >= _dq_band_rank(DIAG_BAND_SEVERE) ? span_boldwarning("It looks severely burnt and heat-warped!") : span_warning("It looks slightly charred.")
