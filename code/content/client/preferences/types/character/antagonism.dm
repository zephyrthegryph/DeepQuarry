// DQ-migrated: antagonism + candidacy prefs.

/datum/preference/numeric/human/be_special
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "be_special"
	savefile_identifier = PREFERENCE_PLAYER  // per-account, role opt-ins
	can_randomize = FALSE
	minimum = 0
	maximum = 65535
	widget = PREF_WIDGET_HIDDEN  // bitmask of antag opt-ins; managed by the antag panel

/datum/preference/numeric/human/be_special/create_default_value()
	return 0

/datum/preference/numeric/human/be_special/apply_to_human(mob/living/carbon/human/target, value)
	return

/datum/preference/choiced/human/vantag_preference
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "vantag_preference"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

TYPE_TABLE(/datum/preference/choiced/human/vantag_preference, pref_choices, GLOB.vantag_choices_list)
/datum/preference/choiced/human/vantag_preference/create_default_value()
	return VANTAG_NONE

/// Values are HUD icon states (VANTAG_NONE is "hudblank"); the dropdown shows each one's role name.
/datum/preference/choiced/human/vantag_preference/get_pref_choices(datum/preferences/preferences)
	var/list/out = list()
	for(var/choice in GLOB.vantag_choices_list)
		out["[choice]"] = GLOB.vantag_choices_list[choice]
	return out

/datum/preference/choiced/human/vantag_preference/apply_to_human(mob/living/carbon/human/target, value)
	target.set_vantag_pref(value)
