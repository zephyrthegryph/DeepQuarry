// Generated damage flavour text (damage.md §6). The damage-flavour rules in
// code/datums/rules/declarations.dm keep each object's damage_band; examine()
// shows the band's line. This replaces the hand-written per-type lines.

// Shared damage presentation and ionic susceptibility; overrides allocate only on write.
STATIC_ENTRY(damage_profile)

/proc/damage_profile(wear = null, announce = null, ionic = null)
	return entry_make(ENTRY_DAMAGE_PROFILE, null, list("wear" = wear, "announce" = announce, "ionic" = ionic))

/datum/type_trait/damage_profile
	var/wear = "scrapes and dents"
	var/announce = FALSE
	var/ionic = 0

/datum/type_trait/damage_profile/copy_values(datum/type_trait/damage_profile/into)
	into.wear = wear
	into.announce = announce
	into.ionic = ionic

/datum/entry_engine/type_trait/damage_profile
	kind = ENTRY_DAMAGE_PROFILE
	trait_type = /datum/type_trait/damage_profile
	publish_key = DAMAGE_PROFILE_KEY
	base_type = /atom
	var_names = list("damage_wear" = "wear", "announce_damage_bands" = "announce", "emp_integrity_factor" = "ionic")

READS_AS(/proc/damage_profile_of, DAMAGE_PROFILE_KEY)
/proc/damage_profile_of(atom/A) as /datum/type_trait/damage_profile
	READS_FROM(A)
	return type_trait_of(A, ENTRY_DAMAGE_PROFILE)

/proc/damage_profile_of_type(type) as /datum/type_trait/damage_profile
	READS_FROM()
	return type_trait_of_type(type, ENTRY_DAMAGE_PROFILE)

/// The examine line for `band` (DAMAGE_BAND_*), or null for none.
/atom/proc/damage_flavour_text(band)
	var/they = gender == PLURAL ? "They" : "It"
	var/have = gender == PLURAL ? "have" : "has"
	var/look = gender == PLURAL ? "look" : "looks"
	switch(band)
		if(DAMAGE_BAND_LIGHT)
			return span_notice("[they] [have] a few [damage_profile_of(src).wear].")
		if(DAMAGE_BAND_MODERATE)
			return span_warning("[they] [look] seriously damaged.")
		if(DAMAGE_BAND_HEAVY)
			return span_danger("[they] [look] about to fall apart!")
	return null

/// The line onlookers see when this atom drops into `band`.
/atom/proc/damage_band_announcement(band)
	switch(band)
		if(DAMAGE_BAND_LIGHT)
			return "\The [src] starts to show [damage_profile_of(src).wear]!"
		if(DAMAGE_BAND_MODERATE)
			return "\The [src] looks seriously damaged!"
		if(DAMAGE_BAND_HEAVY)
			return "\The [src] looks like it's about to break!"
	return null

/// Announces a drop into a worse damage band between two integrity values.
/// Called from on_update_integrity() for types that set announce_damage_bands.
/atom/proc/announce_damage_band(old_value, new_value)
	if(new_value <= 0 || new_value >= old_value || max_integrity <= 0)
		return
	var/new_band = dq_damage_band_at(new_value / max_integrity)
	if(new_band > dq_damage_band_at(old_value / max_integrity))
		visible_message(damage_band_announcement(new_band))

/// The damage band (DAMAGE_BAND_*) for an integrity ratio, read against the
/// declared flavour rules' levels.
/proc/dq_damage_band_at(ratio)
	. = DAMAGE_BAND_NONE
	for(var/datum/rule/rule as anything in GLOBAL_TABLE_GET(damage_flavour_rules))
		var/datum/rule_trigger/trigger = rule.triggers[1]
		if(ratio < trigger.value && rule.band > .)
			. = rule.band

/// The damage band `A` is in, read against the declared flavour rules' levels.
/// For atoms no rule binding keeps (turfs, objects that never materialized).
/proc/dq_damage_band_for(atom/A)
	if(!A.uses_integrity || A.max_integrity <= 0)
		return DAMAGE_BAND_NONE
	if(A.damage_band)
		return A.damage_band
	return dq_damage_band_at(A.get_integrity() / A.max_integrity)

/// The compiled damage-flavour rules.
GLOBAL_TABLE(damage_flavour_rules, GLOBAL_PROC_REF(build_damage_flavour_rules))

/proc/build_damage_flavour_rules()
	var/list/found = list()
	var/list/rules = GLOBAL_TABLE_GET(dq_rules)
	for(var/path in subtypesof(/datum/rule/damage_flavour))
		if(rules[path])
			found += rules[path]
	return found
