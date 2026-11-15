// DQ-migrated: persistence + resleeve prefs.

/datum/preference/numeric/human/persistence_settings
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "persistence_settings"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	minimum = 0
	maximum = 65535
	widget = PREF_WIDGET_HIDDEN  // bitfield of PERSIST_* flags; needs a checkbox panel, not a slider

/datum/preference/numeric/human/persistence_settings/create_default_value()
	return PERSIST_DEFAULT

/datum/preference/numeric/human/persistence_settings/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/toggle/human/resleeve_lock
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "resleeve_lock"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/resleeve_lock/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/toggle/human/resleeve_scan
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "resleeve_scan"
	default_value = TRUE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/resleeve_scan/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/toggle/human/mind_scan
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "mind_scan"
	default_value = TRUE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/mind_scan/apply_to_human(mob/living/carbon/human/target, value)
	return
