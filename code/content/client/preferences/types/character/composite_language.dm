// DQ-migrated: language composite prefs.

/datum/preference/alternate_languages
	savefile_key = "language"   // disk-key match for existing savefiles
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/alternate_languages/create_default_value()
	return list()

/datum/preference/alternate_languages/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/alternate_languages/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/alternate_languages/is_valid(value)
	return islist(value)

/datum/preference/alternate_languages/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/alternate_languages/apply_to_living(mob/living/target, value)
	return
/datum/preference/alternate_languages/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/alternate_languages/apply_to_animal(mob/living/simple_mob/target, value)
	return


// Each language has one prefix of its own, the whole string the player types. A save from before that holds one-character keys, read as "," + key.

/datum/preference/language_custom_keys
	savefile_key = "language_custom_keys"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/language_custom_keys/create_default_value()
	return list()

/datum/preference/language_custom_keys/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	var/list/migrated = list()
	for(var/saved in input)
		migrated[language_migrate_prefix(saved)] = input[saved]
	return migrated

/datum/preference/language_custom_keys/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/language_custom_keys/is_valid(value)
	return islist(value)

/datum/preference/language_custom_keys/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/language_custom_keys/apply_to_living(mob/living/target, value)
	return
/datum/preference/language_custom_keys/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/language_custom_keys/apply_to_animal(mob/living/simple_mob/target, value)
	return

/// The species' spoken language, by name; Galactic Common without a species.
/datum/preferences/proc/species_language_name()
	var/datum/species/S = GLOB.all_species[read_preference(/datum/preference/choiced/species)]
	return S?.language || LANGUAGE_GALCOM

/// Every language this character knows, by name: the species' own first, then the picked alternates.
/datum/preferences/proc/known_language_names()
	. = list()
	var/datum/species/S = GLOB.all_species[read_preference(/datum/preference/choiced/species)]
	if(S)
		for(var/name in list(S.language, S.default_language))
			if(name && GLOB.all_languages[name])
				. |= name
	for(var/name in read_preference(/datum/preference/alternate_languages))
		if(GLOB.all_languages[name])
			. |= name
	if(!length(.))
		. += LANGUAGE_GALCOM

/// Language name -> the prefix that speaks it for this character: the saved one, else the language's own (when it has one and no earlier
/// language holds it). What the character setup shows and what apply_language_prefs gives the mob.
/datum/preferences/proc/language_key_map()
	. = list()
	var/list/custom = read_preference(/datum/preference/language_custom_keys)
	var/list/taken = list()
	var/list/known = known_language_names()
	for(var/saved in custom)
		if(custom[saved] in known)
			var/prefix = language_migrate_prefix(saved)
			.[custom[saved]] = prefix
			taken[prefix] = TRUE
	for(var/name in known)
		if(.[name])
			continue
		var/datum/language/L = GLOB.all_languages[name]
		if(!L.key || (L.flags & NONGLOBAL))
			continue
		var/own = language_default_prefix(L)
		if(taken[own])
			continue
		.[name] = own
		taken[own] = TRUE

/// Why `key` (a whole prefix) cannot speak language `name` for this character, or null when it can.
/datum/preferences/proc/language_key_problem(name, key)
	if(!(name in known_language_names()))
		return "this character does not know [name]"
	var/problem = language_prefix_problem(key)
	if(problem)
		return problem
	var/list/map = language_key_map()
	for(var/other in map)
		if(other != name && map[other] == key)
			return "[key] already speaks [other]"
	return null

/// Binds `key` to language `name` (validated). Returns null, or why it was refused.
/datum/preferences/proc/set_language_key(name, key)
	. = language_key_problem(name, key)
	if(.)
		return
	var/list/custom = read_preference(/datum/preference/language_custom_keys)
	for(var/old in custom.Copy())
		if(custom[old] == name)
			custom -= old
	custom[key] = name
	update_preference_by_type(/datum/preference/language_custom_keys, custom)

/// The language keys and preferred language of this character, on the mob it now plays. The preferred language applies only if the mob can
/// speak it, so it never replaces the species default with a language the body cannot use.
/mob/living/proc/apply_language_prefs(datum/preferences/prefs)
	var/list/map = prefs.language_key_map()
	for(var/name in map)
		var/datum/language/L = GLOB.all_languages[name]
		if(L)
			set_language_keys_at(map[name], L)
	var/datum/language/preferred = GLOB.all_languages[prefs.read_preference(/datum/preference/text/human/preferred_language)]
	if(preferred && can_speak(preferred))
		rel_set(src, nameof(default_language), preferred)
