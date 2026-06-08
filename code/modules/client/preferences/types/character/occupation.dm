// wholesale rewrite. The original file defined 15 bitfield prefs
// (job_civilian_high/med/low, job_medsci_*, job_engsec_*, job_talon_*, job_other_*)
// and a GetJobDepartment() helper that read them by department_flag. The whole bucket
// model is gone in DQ. Job priorities now live in
// /datum/preference/job_priorities (sparse assoc {title: "high"|"med"|"low"}) —
// see code/modules/client/preferences/types/character/job_priorities.dm.
//
// What's left in this file: just the two upstream prefs and helper that didn't change
// (alternate_option enum and player_alt_titles assoc). They're kept here so upstream
// references to /datum/preference/numeric/human/alternate_option and
// /datum/preference/player_alt_titles continue to resolve.

// Alternate option preference (0-2): RETURN_TO_LOBBY / BE_ASSISTANT / GET_RANDOM_JOB.

/datum/preference/numeric/human/alternate_option
	savefile_key = "alternate_option"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE
	minimum = 0
	maximum = 2

/datum/preference/numeric/human/alternate_option/create_default_value()
	return 1

/datum/preference/numeric/human/alternate_option/apply_to_human(mob/living/carbon/human/target, value)
	return

// Player alt titles preference (assoc list of {job_title: alt_title})

/datum/preference/player_alt_titles
	savefile_key = "player_alt_titles"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	can_randomize = FALSE

/datum/preference/player_alt_titles/create_default_value()
	return list()

/datum/preference/player_alt_titles/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/player_alt_titles/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/player_alt_titles/is_valid(value)
	return islist(value)

/datum/preference/player_alt_titles/apply_to_human(mob/living/carbon/human/target, value)
	return

/datum/preference/player_alt_titles/apply_to_living(mob/living/target, value)
	return

/datum/preference/player_alt_titles/apply_to_silicon(mob/living/silicon/target, value)
	return

/datum/preference/player_alt_titles/apply_to_animal(mob/living/simple_mob/target, value)
	return

// Note: there is no /datum/category_item/player_setup_item/occupation Bay-UI
// bridge here — that whole chain is gone. Occupation selection happens natively
// via the species picker and character setup TGUI.

/datum/preferences/proc/GetPlayerAltTitle(datum/job/job)
	var/list/alt_titles = read_preference(/datum/preference/player_alt_titles)
	return (islist(alt_titles) && (job.title in alt_titles)) ? alt_titles[job.title] : job.title
