// DQ-migrated: loadout composite prefs.
// all_underwear / all_underwear_metadata are assoc lists; gear_list /
// gear_slot are the gear loadout state. Migrated as /datum/preference
// subtypes so the legacy vars can be deleted; the data shape stays
// composite (proper slot-based refactor is a separate future pass).

/datum/preference/all_underwear
	savefile_key = "all_underwear"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/all_underwear/create_default_value()
	return list()

/datum/preference/all_underwear/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/all_underwear/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/all_underwear/is_valid(value)
	return islist(value)

/datum/preference/all_underwear/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/all_underwear/apply_to_living(mob/living/target, value)
	return
/datum/preference/all_underwear/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/all_underwear/apply_to_animal(mob/living/simple_mob/target, value)
	return


/datum/preference/all_underwear_metadata
	savefile_key = "all_underwear_metadata"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/all_underwear_metadata/create_default_value()
	return list()

/datum/preference/all_underwear_metadata/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	for(var/i in input)
		input[i] = path2text_list(input[i])
	return input

/datum/preference/all_underwear_metadata/pref_serialize(input)
	if(!islist(input))
		return list()
	var/list/out = list()
	for(var/i in input)
		out[i] = check_list_copy(input[i])
	return out

/datum/preference/all_underwear_metadata/is_valid(value)
	return islist(value)

/datum/preference/all_underwear_metadata/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/all_underwear_metadata/apply_to_living(mob/living/target, value)
	return
/datum/preference/all_underwear_metadata/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/all_underwear_metadata/apply_to_animal(mob/living/simple_mob/target, value)
	return


/datum/preference/gear_list
	savefile_key = "gear_list"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/gear_list/create_default_value()
	return list()

/datum/preference/gear_list/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/gear_list/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/gear_list/is_valid(value)
	return islist(value)

/datum/preference/gear_list/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/gear_list/apply_to_living(mob/living/target, value)
	return
/datum/preference/gear_list/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/gear_list/apply_to_animal(mob/living/simple_mob/target, value)
	return


// DQEdit — gear_slot was numeric (1/2/3) under the old "you have 3 loadout slots" model.
// New shape: the editor target is a job title (or the literal "_default") indicating
// which per-job loadout is being edited / applied. Stored as text now.
/datum/preference/text/human/gear_slot
	savefile_key = "gear_slot"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE
	maximum_value_length = 64

/datum/preference/text/human/gear_slot/create_default_value()
	return "_default"

/datum/preference/text/human/gear_slot/apply_to_human(mob/living/carbon/human/target, value)
	return
