// Qualitative bucketing helpers for the body scanner.
//
// Severity bands shared by every diagnosis report (diagnosis/): instruments
// report bands, never raw damage numbers.
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


/// Qualitative band for the patient's overall condition, from the body's
/// vitality (0..1 wellness). A patient who is down from injury reads
/// critical regardless of the number.
/proc/dq_qualitative_vitality_band(vitality, critical = FALSE)
	if(critical || vitality <= 0)
		return "critical"
	if(vitality >= 0.9)
		return "uninjured"
	if(vitality >= 0.6)
		return "minor"
	if(vitality >= 0.3)
		return "moderate"
	if(vitality >= 0.1)
		return "severe"
	return "critical"


/// Trend bucket for a condition's severity delta. Uses a small dead
/// zone around zero so a condition that's drifting by < 2 severity
/// between scans reads as "stable" rather than flickering.
/proc/_dq_trend_for_condition(datum/affliction/C)
	if(isnull(C.last_scanned_severity))
		return "new"
	var/delta = C.severity - C.last_scanned_severity
	if(delta > 2)
		return "worsening"
	if(delta < -2)
		return "improving"
	return "stable"


/// Internal-bleeding wound afflictions on a limb (empty list if none). The
/// single place diagnostics look for internal bleeds, so scanners don't
/// reach into wound internals themselves.
/proc/dq_limb_internal_bleeds(obj/item/organ/external/E)
	. = list()
	for(var/datum/affliction/wound/W in E?.afflictions_here())
		if(W.internal)
			. += W
