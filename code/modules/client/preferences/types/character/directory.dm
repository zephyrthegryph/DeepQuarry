// DQ-migrated: character-directory + per-character flag prefs.
//
// Previously these were monolithic vars on /datum/preferences with their
// load/save/sanitize handled by /datum/category_item/player_setup_item/general/
// vore_misc (Bay UI bridge). They're now individual /datum/preference
// subtypes — savefile_keys match the previous JSON keys so existing
// player savefiles continue to load without migration.

// --- show_in_directory ------------------------------------------------------

/datum/preference/toggle/human/show_in_directory
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "show_in_directory"
	default_value = TRUE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/show_in_directory/apply_to_human(mob/living/carbon/human/target, value)
	return // read directly via prefs at runtime


// --- directory tags (4 choice prefs) ----------------------------------------

/datum/preference/choiced/human/directory_tag
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "directory_tag"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/choiced/human/directory_tag/init_possible_values()
	return GLOB.char_directory_tags

/datum/preference/choiced/human/directory_tag/create_default_value()
	return "Unset"

/datum/preference/choiced/human/directory_tag/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/choiced/human/directory_gendertag
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "directory_gendertag"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/choiced/human/directory_gendertag/init_possible_values()
	return GLOB.char_directory_gendertags

/datum/preference/choiced/human/directory_gendertag/create_default_value()
	return "Unset"

/datum/preference/choiced/human/directory_gendertag/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/choiced/human/directory_sexualitytag
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "directory_sexualitytag"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/choiced/human/directory_sexualitytag/init_possible_values()
	return GLOB.char_directory_sexualitytags

/datum/preference/choiced/human/directory_sexualitytag/create_default_value()
	return "Unset"

/datum/preference/choiced/human/directory_sexualitytag/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/choiced/human/directory_erptag
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "directory_erptag"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/choiced/human/directory_erptag/init_possible_values()
	return GLOB.char_directory_erptags

/datum/preference/choiced/human/directory_erptag/create_default_value()
	return "Unset"

/datum/preference/choiced/human/directory_erptag/apply_to_human(mob/living/carbon/human/target, value)
	return


// --- directory_ad ----------------------------------------------------------

/datum/preference/text/human/directory_ad
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "directory_ad"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_MESSAGE_LEN

/datum/preference/text/human/directory_ad/create_default_value()
	return ""

/datum/preference/text/human/directory_ad/apply_to_human(mob/living/carbon/human/target, value)
	return


// --- sensorpref ------------------------------------------------------------

/datum/preference/numeric/human/sensorpref
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "sensorpref"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	minimum = 1
	maximum = 5
	step = 1

/datum/preference/numeric/human/sensorpref/create_default_value()
	return 5

/datum/preference/numeric/human/sensorpref/apply_to_human(mob/living/carbon/human/target, value)
	target.sensorpref = value


// --- capture_crystal -------------------------------------------------------

/datum/preference/toggle/human/capture_crystal
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "capture_crystal"
	default_value = TRUE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/capture_crystal/apply_to_human(mob/living/carbon/human/target, value)
	target.capture_crystal = value


// --- auto_backup_implant ---------------------------------------------------

/datum/preference/toggle/human/auto_backup_implant
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "auto_backup_implant"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/auto_backup_implant/apply_to_human(mob/living/carbon/human/target, value)
	return // read at spawn-time by ticker.dm


// --- borg_petting ----------------------------------------------------------

/datum/preference/toggle/human/borg_petting
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "borg_petting"
	default_value = TRUE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/borg_petting/apply_to_human(mob/living/carbon/human/target, value)
	return
