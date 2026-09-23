// body.diagnose(profile) and body.treatment_demand(profile): the one
// diagnosis model. See doc/health_system_review.md §5.8.
//
// diagnose() builds a /datum/diagnosis from what the profile can perceive:
//   vitals        read ONLY through the vitals contract (physiology.dm)
//   conditions    afflictions whose presentation the profile senses
//   signs         presenting symptoms (scanner phrases for instruments,
//                 examine lines for the naked eye), even when their cause is
//                 hidden from this instrument
//   parts         per-part integrity bands (plan hook)
//   plan findings brain death, blood loss, radiation (plan hook)
//   hints         treatment_demand() for profiles that give advice
// Feigned death is applied once, here.

/// Diagnose this mob through `profile` (a /datum/diagnostic_profile typepath
/// or instance). Null when the mob has no body.
/mob/living/proc/diagnose(profile) as /datum/diagnosis
	return body?.diagnose(profile)

/// Write one line to the game log for a player-initiated scan.
/proc/log_diagnosis(mob/user, mob/living/patient, datum/diagnosis/D)
	if(!D)
		return
	log_game("DIAGNOSIS: [key_name(user)] scanned [key_name(patient)] with [D.profile.name]: status [D.status], band [D.band], [LAZYLEN(D.findings)] finding(s).")

/datum/body/proc/diagnose(profile) as /datum/diagnosis
	var/datum/diagnostic_profile/P = ispath(profile) ? diagnostic_profile(profile) : profile
	if(!istype(P))
		CRASH("diagnose() called with an invalid profile: [profile]")
	ensure_vitals()
	var/datum/diagnosis/D = new
	D.profile = P
	D.patient_name = owner.name
	D.fake_death = (owner.status_flags & FAKEDEATH) && !P.sees_fake_death

	if(owner.stat == DEAD || D.fake_death)
		D.status = DIAG_STATUS_DEAD
		D.band = DIAG_BAND_CRITICAL
		D.time_of_death = owner.timeofdeath
	else if(owner.is_critical())
		D.status = DIAG_STATUS_CRITICAL
		D.band = DIAG_BAND_CRITICAL
	else
		D.band = dq_qualitative_vitality_band(get_vitality())

	diagnose_vitals(D, P)
	diagnose_afflictions(D, P)
	diagnose_plan(D, P)
	if(P.part_detail != DIAG_PARTS_NONE)
		diagnose_parts(D, P)
	if(P.hints)
		D.hints = treatment_demand(P)
	D.sort_findings()
	return D

/// Vitals through the contract. A feigned death reads as flatlined.
/datum/body/proc/diagnose_vitals(datum/diagnosis/D, datum/diagnostic_profile/P)
	var/flat = D.fake_death || owner.stat == DEAD
	if(P.vitals & VITALS_PULSE)
		var/rate = heart_rate()
		if(!isnull(rate))
			D.heart_rate = flat ? 0 : round(rate)
	if(P.vitals & VITALS_BP)
		var/list/pressure = blood_pressure()
		if(pressure)
			D.blood_pressure = flat ? list(0, 0) : list(round(pressure[1]), round(pressure[2]))
	if(P.vitals & VITALS_SPO2)
		var/saturation = oxygenation()
		if(!isnull(saturation))
			D.oxygenation = flat ? 0 : round(saturation)
	if(P.vitals & VITALS_RESP)
		var/breaths = respiratory_rate()
		if(!isnull(breaths))
			D.respiratory_rate = flat ? 0 : round(breaths)
	if(P.vitals & VITALS_TEMP)
		D.temperature = round((owner.bodytemperature - T0C + owner.factor(BF_TEMPERATURE)) * 10) / 10
	if(P.vitals & VITALS_CONSCIOUSNESS)
		if(flat)
			D.consciousness = "none"
		else if(owner.stat == UNCONSCIOUS || is_unconscious())
			D.consciousness = "unresponsive"
		else if(consciousness < 70)
			D.consciousness = "drowsy"
		else
			D.consciousness = "alert"

/// Conditions the profile perceives, plus the signs every affliction presents.
/datum/body/proc/diagnose_afflictions(datum/diagnosis/D, datum/diagnostic_profile/P)
	var/instrument = P.senses & (PRESENT_SURFACE | PRESENT_INTERNAL | PRESENT_LAB | PRESENT_SYNTHETIC | PRESENT_NANITE)
	var/eyes = P.senses & PRESENT_VISIBLE
	for(var/datum/affliction/A as anything in afflictions)
		var/where = (P.localize && A.location) ? "[A.location.name]" : ""
		var/band = dq_qualitative_damage_band(A.diagnostic_severity(), 100)
		if(A.perceived_by(P) && band != DIAG_BAND_NONE)
			var/datum/diagnosis_finding/F = D.add_finding(new /datum/diagnosis_finding(A.diagnostic_name(), A.finding_kind(), band, where, A.type))
			if(P.describe)
				F.description = A.clinical_description
			if(P.hints)
				F.hint = A.diagnostic_hint(P)
			if(P.trends && !istype(A, /datum/affliction/wound))
				F.trend = _dq_trend_for_condition(A)
				A.last_scanned_severity = A.severity
		if(!A.active_symptoms || !(biology_of(A.location) & P.biology))
			continue
		for(var/datum/affliction_symptom/S as anything in affliction_symptoms_of(A))
			var/phrase
			if(instrument && S.is_scanner_visible())
				phrase = S.scanner_phrase
			else if(eyes && (S.audiences & SYMPTOM_AUDIENCE_PUBLIC))
				phrase = S.examine_line || S.name
			if(phrase)
				D.add_finding(new /datum/diagnosis_finding(phrase, DIAG_FINDING_SIGN, band, where))

/// Plan-specific findings (brain death, blood loss, radiation...). Base:
/// radiation, which every living mob accumulates.
/datum/body/proc/diagnose_plan(datum/diagnosis/D, datum/diagnostic_profile/P)
	if(owner.radiation >= 100 && (P.senses & (PRESENT_SURFACE | PRESENT_SYNTHETIC)))
		var/datum/diagnosis_finding/F = D.add_finding(new /datum/diagnosis_finding("acute radiation exposure", DIAG_FINDING_CONDITION, dq_qualitative_damage_band(owner.radiation, 1500)))
		if(P.describe)
			F.description = "Absorbed dose approximately [round(owner.radiation / 50)] Gy."

/// Per-part integrity bands. Base: no parts.
/datum/body/proc/diagnose_parts(datum/diagnosis/D, datum/diagnostic_profile/P)
	return

/// Which treatment mechanisms the afflictions `P` can perceive respond to:
/// TREAT_* -> DIAG_BAND_* urgency (the worst band among the afflictions it
/// treats). Without a profile, every affliction counts. Natural
/// regeneration and restoration are never asked for.
/datum/body/proc/treatment_demand(datum/diagnostic_profile/P = null)
	if(ispath(P))
		P = diagnostic_profile(P)
	var/list/demand
	for(var/datum/affliction/A as anything in afflictions)
		if(P && !A.perceived_by(P))
			continue
		var/band = dq_qualitative_damage_band(A.diagnostic_severity(), 100)
		if(band == DIAG_BAND_NONE)
			continue
		var/part_biology = biology_of(A.location)
		for(var/tag in A.treated_by)
			if(tag == TREAT_REGENERATION || tag == TREAT_RESTORATION)
				continue
			if(!A.treated_by[tag] || !(treatment_tag_biology(tag) & part_biology))
				continue
			LAZYINITLIST(demand)
			if(_dq_band_rank(band) > _dq_band_rank(demand[tag]))
				demand[tag] = band
	return demand


// --- Humanoid ------------------------------------------------------------------

/datum/body/humanoid/diagnose_plan(datum/diagnosis/D, datum/diagnostic_profile/P)
	..()
	var/mob/living/carbon/human/H = owner
	var/instrument = P.senses & (PRESENT_SURFACE | PRESENT_INTERNAL | PRESENT_LAB)
	if(instrument)
		if(H.should_have_organ(O_BRAIN) && (D.fake_death || H.is_brain_dead() || !H.has_brain()))
			D.add_finding(new /datum/diagnosis_finding("no brain activity", DIAG_FINDING_CONDITION, DIAG_BAND_CRITICAL))
		if(HUSK in H.mutations)
			D.add_finding(new /datum/diagnosis_finding("anatomical structure lost", DIAG_FINDING_CONDITION, DIAG_BAND_CRITICAL))
		for(var/datum/disease/virus in H.GetViruses())
			if(virus.visibility_flags & (HIDDEN_SCANNER | HIDDEN_PANDEMIC))
				continue
			D.add_finding(new /datum/diagnosis_finding("[virus.form] in the blood", DIAG_FINDING_CONDITION, DIAG_BAND_MODERATE))
	if((P.vitals & VITALS_BP) || instrument)
		if(H.vessel && H.species?.blood_volume && H.should_have_organ(O_HEART))
			D.blood_percent = round(H.vessel.get_reagent_amount(REAGENT_ID_BLOOD) / H.species.blood_volume * 100)

/datum/body/humanoid/diagnose_parts(datum/diagnosis/D, datum/diagnostic_profile/P)
	var/mob/living/carbon/human/H = owner
	for(var/obj/item/organ/external/E as anything in H.organs)
		if(!(biology_of(E) & P.biology))
			continue
		var/list/flags = list()
		if(E.status & ORGAN_BROKEN)
			flags += E.splinted ? "splinted fracture" : "fracture"
		if(E.status & ORGAN_BLEEDING)
			flags += "bleeding"
		if(E.status & ORGAN_DEAD)
			flags += "necrotic"
		if(E.open)
			flags += "open"
		if(E.robotic >= ORGAN_ROBOT)
			flags += "prosthetic"
		LAZYADD(D.parts, list(list(
			"name" = E.name,
			"band" = dq_qualitative_damage_band(E.get_trauma() + E.get_burn(), E.max_damage),
			"flags" = flags,
		)))


// --- Robots --------------------------------------------------------------------

/datum/body/simple/machine/robot/diagnose_parts(datum/diagnosis/D, datum/diagnostic_profile/P)
	if(!(biology_of(null) & P.biology))
		return
	var/mob/living/silicon/robot/R = owner
	for(var/datum/robot_component/C as anything in R.components)
		var/list/flags = list()
		var/band
		switch(C.installed)
			if(ROBOT_PART_MISSING)
				flags += "missing"
				band = DIAG_BAND_NONE
			if(ROBOT_PART_DESTROYED)
				flags += "destroyed"
				band = DIAG_BAND_CRITICAL
			else
				band = dq_qualitative_damage_band(component_load(C), C.max_damage)
				if(!C.toggled)
					flags += "disabled"
				else if(!C.powered)
					flags += "unpowered"
		LAZYADD(D.parts, list(list("name" = C.name, "band" = band, "flags" = flags)))
