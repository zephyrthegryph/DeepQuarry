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





