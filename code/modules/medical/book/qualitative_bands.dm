// DQ Medical Reference — qualitative-band translators.
//
// Maps raw numeric tunables (progression rates, per-tick cure / worsen
// strengths, cascade chances, symptom-pool weights) onto short
// human-readable bands the book and other UI layers render verbatim.
// Also exposes the reagent-id -> display-name / description helpers,
// kept here because they're cross-cutting translators rather than
// book-specific.

/proc/dq_describe_progression(rate)
	if(rate < -0.05)
		return "self-resolving"
	if(rate <= 0.05)
		return "stable until treated"
	if(rate < 1.0)
		return "slow progression"
	if(rate < 2.0)
		return "steady progression"
	return "rapid progression"

/proc/dq_describe_cure_strength(per_tick)
	if(per_tick >= 1.0)
		return "strong"
	if(per_tick >= 0.4)
		return "moderate"
	return "mild"

/proc/dq_describe_worsen_strength(per_tick)
	if(per_tick >= 1.0)
		return "severe aggravation"
	if(per_tick >= 0.4)
		return "moderate aggravation"
	return "mild aggravation"

/proc/dq_describe_cascade_chance(pct)
	if(pct >= 70)
		return "very likely"
	if(pct >= 40)
		return "likely"
	if(pct >= 20)
		return "uncommon"
	return "rare"

/proc/dq_describe_symptom_frequency(weight)
	if(weight >= 80)
		return "almost always present"
	if(weight >= 50)
		return "often present"
	if(weight >= 25)
		return "sometimes present"
	return "rarely present"

/proc/dq_reagent_display_name(reagent_id)
	if(!SSchemistry?.chemical_reagents)
		return reagent_id
	var/datum/reagent/R = SSchemistry.chemical_reagents[reagent_id]
	if(R?.name)
		return R.name
	return reagent_id

/proc/dq_reagent_description(reagent_id)
	if(!SSchemistry?.chemical_reagents)
		return ""
	var/datum/reagent/R = SSchemistry.chemical_reagents[reagent_id]
	return R?.description || ""
