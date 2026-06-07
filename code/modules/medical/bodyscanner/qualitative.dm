// Qualitative bucketing helpers for the body scanner.
//
// The bodyscanner used to dump raw damage numbers and the full list of
// medical_issue names onto the TGUI. Players read those as "exact" data
// that the in-fiction scanner would not, in practice, give a medic.
//
// These helpers translate raw damage numbers and condition lists into
// qualitative findings that match what a real-life medical scanner would
// actually report: severity bands, broken/bleeding/dead flags, and the
// scanner phrases authored on each /datum/medical_symptom.
//
// Bands (used everywhere unless noted):
//   "uninjured"   no measurable damage
//   "minor"       1 – 25% of max
//   "moderate"    25 – 50%
//   "severe"      50 – 75%
//   "critical"    75% +

/// Numeric rank for a qualitative band so we can compare severities.
/// Higher = worse. Used by the scanner-finding sort and the worst-finding
/// roll-up that drives the occupant card's Condition row.
/proc/_dq_band_rank(band)
	switch(band)
		if("critical")
			return 4
		if("severe")
			return 3
		if("moderate")
			return 2
		if("minor")
			return 1
	return 0


/// Qualitative band for a damage value against its max.
/proc/dq_qualitative_damage_band(amount, max_amount)
	if(!amount || amount <= 0)
		return "uninjured"
	if(!max_amount || max_amount <= 0)
		return "minor"
	var/frac = amount / max_amount
	if(frac < 0.25)
		return "minor"
	if(frac < 0.50)
		return "moderate"
	if(frac < 0.75)
		return "severe"
	return "critical"


/// Qualitative band for the *overall* health pool. Different max from
/// per-organ values (the body's overall pool tops out around 100), and
/// the "critical" tier is calibrated so that 0-or-below health reads
/// critical regardless of the player's max.
/proc/dq_qualitative_health_band(health, max_health)
	if(!max_health || max_health <= 0)
		return "critical"
	if(health <= 0)
		return "critical"
	var/frac = health / max_health
	if(frac >= 0.9)
		return "uninjured"
	if(frac >= 0.6)
		return "minor"
	if(frac >= 0.3)
		return "moderate"
	if(frac >= 0.1)
		return "severe"
	return "critical"


/// Whole-body damage panel: one row per damage type, qualitative band only.
/// Caller passes the occupant; we read each loss type and translate.
/proc/dq_qualitative_damage_panel(mob/living/carbon/human/H)
	if(!H)
		return list()
	var/list/out = list()
	// Each entry: { kind, label, band }. Order is deliberate — mirrors
	// the order the old TGUI rendered them in.
	out += list(list("kind" = "brute",     "label" = "Trauma",        "band" = dq_qualitative_damage_band(H.getBruteLoss(), 100)))
	out += list(list("kind" = "fire",      "label" = "Burns",         "band" = dq_qualitative_damage_band(H.getFireLoss(), 100)))
	out += list(list("kind" = "oxy",       "label" = "Respiratory",   "band" = dq_qualitative_damage_band(H.getOxyLoss(), 100)))
	out += list(list("kind" = "tox",       "label" = "Toxin",         "band" = dq_qualitative_damage_band(H.getToxLoss(), 100)))
	out += list(list("kind" = "brain",     "label" = "Neurological",  "band" = dq_qualitative_damage_band(H.getBrainLoss(), 100)))
	out += list(list("kind" = "clone",     "label" = "Genetic",       "band" = dq_qualitative_damage_band(H.getCloneLoss(), 100)))
	out += list(list("kind" = "rad",       "label" = "Radiation",     "band" = dq_qualitative_damage_band(H.radiation, 100)))
	// Paralysis is tick-based, not damage. Translate "this many seconds
	// of expected immobility" → band.
	var/par_seconds = round(H.paralysis / 4)
	var/par_band = "uninjured"
	if(par_seconds > 0)
		par_band = "minor"
	if(par_seconds > 20)
		par_band = "moderate"
	if(par_seconds > 60)
		par_band = "severe"
	if(par_seconds > 180)
		par_band = "critical"
	out += list(list("kind" = "paralysis", "label" = "Paralysis",     "band" = par_band))
	return out


/// Scanner-audience findings derived from active DQ symptoms on a mob.
/// Returns an unordered list of { phrase, organ, severity, trend }
/// entries — one per active symptom whose audiences flag includes
/// SCANNER. The caller (bodyscanner data emitter) groups them by organ.
///
/// Trend is computed from each condition's severity vs its last
/// scanned severity. Tells the medic whether treatment is taking hold
/// without revealing the raw number. After computing the trend for a
/// condition, this proc updates the snapshot — so consecutive scans
/// always compare against the previous read, not the first one ever.
/proc/dq_qualitative_scanner_findings(mob/living/carbon/human/H)
	if(!H)
		return list()
	var/list/out = list()
	var/list/trend_by_condition = list()
	for(var/datum/medical_issue/condition/C as anything in H.get_all_conditions())
		if(!C.active_symptoms)
			continue
		// Compute the trend once per condition (one delta) but attach
		// it to every finding the condition produces.
		var/key = "[C]"
		var/trend = trend_by_condition[key]
		if(isnull(trend))
			trend = _dq_trend_for_condition(C)
			trend_by_condition[key] = trend
			C.last_scanned_severity = C.severity
		for(var/datum/medical_symptom/S as anything in C.active_symptoms)
			if(!(S.audiences & SYMPTOM_AUDIENCE_SCANNER))
				continue
			if(!S.scanner_phrase)
				continue
			var/organ_name = ""
			if(C.affectedorgan)
				organ_name = C.affectedorgan.name
			out += list(list(
				"phrase"   = S.scanner_phrase,
				"organ"    = organ_name,
				"severity" = dq_qualitative_damage_band(C.severity, 100),
				"trend"    = trend,
				"stage"    = C.stage,
			))
	return out


/// Trend bucket for a condition's severity delta. Uses a small dead
/// zone around zero so a condition that's drifting by < 2 severity
/// between scans reads as "stable" rather than flickering.
/proc/_dq_trend_for_condition(datum/medical_issue/condition/C)
	if(isnull(C.last_scanned_severity))
		return "new"
	var/delta = C.severity - C.last_scanned_severity
	if(delta > 2)
		return "worsening"
	if(delta < -2)
		return "improving"
	return "stable"
