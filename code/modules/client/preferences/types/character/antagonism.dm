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


/datum/preference/text/human/antag_faction
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "antag_faction"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/antag_faction/create_default_value()
	return "None"

/datum/preference/text/human/antag_faction/get_pref_choices(datum/preferences/preferences)
	return GLOB.faction_choices + list("None")

/datum/preference/text/human/antag_faction/apply_to_human(mob/living/carbon/human/target, value)
	target.antag_faction = value


/datum/preference/choiced/human/antag_vis
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "antag_vis"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/choiced/human/antag_vis/init_possible_values()
	return GLOB.antag_visiblity_choices

/datum/preference/choiced/human/antag_vis/create_default_value()
	return "Hidden"

/datum/preference/choiced/human/antag_vis/apply_to_human(mob/living/carbon/human/target, value)
	target.antag_vis = value


/datum/preference/text/human/exploit_record
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "exploit_record"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_RECORD_LENGTH

/datum/preference/text/human/exploit_record/create_default_value()
	return ""

/datum/preference/text/human/exploit_record/apply_to_human(mob/living/carbon/human/target, value)
	target.exploit_record = value


/datum/preference/toggle/human/vantag_volunteer
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "vantag_volunteer"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/vantag_volunteer/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/choiced/human/vantag_preference
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "vantag_preference"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/choiced/human/vantag_preference/init_possible_values()
	return GLOB.vantag_choices_list

/datum/preference/choiced/human/vantag_preference/create_default_value()
	return VANTAG_NONE

/datum/preference/choiced/human/vantag_preference/apply_to_human(mob/living/carbon/human/target, value)
	target.vantag_pref = value
