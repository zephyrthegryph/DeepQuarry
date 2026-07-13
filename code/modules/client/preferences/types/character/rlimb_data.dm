// Robolimb data preference for character creation
// Stores an assoc list mapping organ tags to robolimb manufacturer model names.
// Values are strings corresponding to keys in GLOB.all_robolimbs.

/datum/preference/rlimb_data
	savefile_key = "rlimb_data"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/rlimb_data/create_default_value()
	return list()

/datum/preference/rlimb_data/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	var/list/input_list = input
	// Sanitize: remove entries with invalid robolimb keys
	for(var/limb in input_list.Copy())
		var/key = input_list[limb]
		if(!istext(key) || !LAZYACCESS(GLOB.all_robolimbs, key))
			input_list -= limb
	return input_list

/datum/preference/rlimb_data/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/rlimb_data/is_valid(value)
	return islist(value)

/datum/preference/rlimb_data/apply_to_human(mob/living/carbon/human/target, value)
	return // handled by /datum/preference_apply_hook/organs (apply_hooks/organs.dm)

/datum/preference/rlimb_data/apply_to_living(mob/living/target, value)
	return

/datum/preference/rlimb_data/apply_to_silicon(mob/living/silicon/target, value)
	return

/datum/preference/rlimb_data/apply_to_animal(mob/living/simple_mob/target, value)
	return
