// DQ-migrated: language scalar prefs.
// alternate_languages/language_prefixes/language_custom_keys remain
// as monolithic lists for now (composite data — separate refactor).

/datum/preference/numeric/human/extra_languages
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "extra_languages"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	minimum = 0
	maximum = 10

/datum/preference/numeric/human/extra_languages/create_default_value()
	return 0

/datum/preference/numeric/human/extra_languages/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/text/human/preferred_language
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "preflang"   // disk-key match for existing savefiles
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/preferred_language/create_default_value()
	return "common"

/datum/preference/text/human/preferred_language/get_pref_choices(datum/preferences/preferences)
	if(!GLOB.all_languages)
		return null
	// DQEdit — only surface languages the player can actually speak: their
	// species default plus everything in alternate_languages. The old "every
	// language ever" list was overwhelming and let the player pick a tongue
	// their character would never know.
	var/list/out = list()
	var/list/picked = preferences?.read_preference(/datum/preference/alternate_languages)
	if(islist(picked))
		for(var/name in picked)
			var/datum/language/L = GLOB.all_languages[name]
			if(istype(L) && !(L.name in out))
				out += L.name
	// Species default — pull from the currently-picked species so the dropdown
	// always offers at least one safe value even with no alternates picked.
	var/species_name = preferences?.read_preference(/datum/preference/choiced/species)
	var/datum/species/S = GLOB.all_species[species_name]
	if(S?.default_language)
		var/datum/language/D = GLOB.all_languages[S.default_language]
		if(istype(D) && !(D.name in out))
			out += D.name
	// Galactic Common as a universal fallback so the dropdown is never empty
	// for a freshly-loaded character with no alternate_languages set.
	if(!length(out))
		var/datum/language/C = GLOB.all_languages["Galactic Common"]
		if(istype(C))
			out += C.name
	return out

/datum/preference/text/human/preferred_language/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/color/human/runechat_color
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "runechat_color"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/color/human/runechat_color/create_default_value()
	return COLOR_BLACK

/datum/preference/color/human/runechat_color/apply_to_human(mob/living/carbon/human/target, value)
	return
