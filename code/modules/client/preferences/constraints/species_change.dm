// DQAdd — When species changes, several other prefs need to be re-checked: hair style might
// not be valid for the new species, age might fall outside the new species' min/max, custom
// base must be valid for the species, body markings must match the new species' allowed list.
//
// Each rule is its own constraint subtype for clarity and isolated testing.

/datum/preference_constraint/species_resets_hair
	triggers = list("species")
	affects = list("hair_style_name")

/datum/preference_constraint/species_resets_hair/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	var/list/valid = preferences.get_valid_hairstyles()
	var/current = preferences.read_preference(/datum/preference/text/human/h_style)
	if(current && (current in valid))
		return
	if(valid.len)
		preferences.update_preference_by_type(/datum/preference/text/human/h_style, pick(valid))
	else
		preferences.update_preference_by_type(/datum/preference/text/human/h_style, GLOB.hair_styles_list["Bald"])


/datum/preference_constraint/species_resets_facial_hair
	triggers = list("species")
	affects = list("facial_style_name")

/datum/preference_constraint/species_resets_facial_hair/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	var/list/valid = preferences.get_valid_facialhairstyles()
	var/current = preferences.read_preference(/datum/preference/text/human/f_style)
	if(current && (current in valid))
		return
	if(valid.len)
		preferences.update_preference_by_type(/datum/preference/text/human/f_style, pick(valid))
	else
		preferences.update_preference_by_type(/datum/preference/text/human/f_style, GLOB.facial_hair_styles_list["Shaved"])


/datum/preference_constraint/species_clamps_age
	triggers = list("species")
	affects = list("age")

/datum/preference_constraint/species_clamps_age/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	var/datum/species/S = GLOB.all_species[new_value]
	if(!S)
		return
	// Use isnull/isnum rather than truthy checks — a species with a legitimate min_age = 0
	// (legal for some custom species) would otherwise silently disable clamping.
	var/min_age = S.min_age
	var/max_age = S.max_age
	if(!isnum(min_age) || !isnum(max_age) || max_age < min_age)
		return
	var/age = preferences.read_preference(/datum/preference/numeric/human/age)
	if(!isnum(age))
		return
	preferences.update_preference_by_type(/datum/preference/numeric/human/age, max(min(age, max_age), min_age))


/datum/preference_constraint/species_resets_custom_base
	triggers = list("species")
	affects = list("custom_base")

/datum/preference_constraint/species_resets_custom_base/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	var/datum/species/S = GLOB.all_species[new_value]
	if(!S)
		return
	var/current = preferences.read_preference(/datum/preference/text/human/custom_base)
	if(S.selects_bodytype)
		if(!(current in preferences.get_custom_bases_for_species()))
			preferences.update_preference_by_type(/datum/preference/text/human/custom_base, S.default_custom_base)
	else if(!current || !(current in GLOB.custom_species_bases))
		preferences.update_preference_by_type(/datum/preference/text/human/custom_base, S.default_custom_base)


/datum/preference_constraint/species_clears_markings
	triggers = list("species")
	affects = list("body_markings")

/datum/preference_constraint/species_clears_markings/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	// When species changes, body markings tied to the old species become invalid. Strip any
	// that aren't on the global markings list (legacy data) plus any whose `allowed_species`
	// or marker presence depends on species — handled by the marking_species_filter constraint
	// triggered by body_markings updates.
	var/list/markings = preferences.read_preference(/datum/preference/body_markings)
	if(!islist(markings))
		return
	markings &= GLOB.body_marking_styles_list
	preferences.update_preference_by_type(/datum/preference/body_markings, markings)
