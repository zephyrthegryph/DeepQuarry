// Generated damage flavour text (damage.md §6). The damage-flavour rules in
// code/datums/rules/declarations.dm keep each object's damage_band; examine()
// shows the band's line. This replaces the hand-written per-type lines.

/atom
	/// What light damage looks like on this type, as a plural noun ("cracks", "scrapes and dents").
	var/damage_wear = "scrapes and dents"

/// The examine line for `band` (DAMAGE_BAND_*), or null for none.
/atom/proc/damage_flavour_text(band)
	var/they = gender == PLURAL ? "They" : "It"
	var/have = gender == PLURAL ? "have" : "has"
	var/look = gender == PLURAL ? "look" : "looks"
	switch(band)
		if(DAMAGE_BAND_LIGHT)
			return span_notice("[they] [have] a few [damage_wear].")
		if(DAMAGE_BAND_MODERATE)
			return span_warning("[they] [look] seriously damaged.")
		if(DAMAGE_BAND_HEAVY)
			return span_danger("[they] [look] about to fall apart!")
	return null

/// The damage band `A` is in, read against the declared flavour rules' levels.
/// For atoms no rule binding keeps (turfs, objects that never materialized).
/proc/dq_damage_band_for(atom/A)
	if(!A.uses_integrity || A.max_integrity <= 0)
		return DAMAGE_BAND_NONE
	if(A.damage_band)
		return A.damage_band
	var/ratio = A.get_integrity() / A.max_integrity
	. = DAMAGE_BAND_NONE
	for(var/datum/rule/rule as anything in dq_damage_flavour_rules())
		var/datum/rule_trigger/trigger = rule.triggers[1]
		if(ratio < trigger.value && rule.band > .)
			. = rule.band

/// The compiled damage-flavour rules.
/proc/dq_damage_flavour_rules()
	var/static/list/found
	if(!found)
		found = list()
		var/list/rules = dq_rules()
		for(var/path in subtypesof(/datum/rule/damage_flavour))
			if(rules[path])
				found += rules[path]
	return found
