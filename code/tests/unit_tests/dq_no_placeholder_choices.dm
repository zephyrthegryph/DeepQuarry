/// Walks every offered choice list (each preference's choices, the sprite accessory style
/// lists, spawn points, playable species) and fails on an abstract base type or its
/// placeholder name (DEVELOPER_WARNING_NAME, "you should not see this...").
/datum/unit_test/dq_no_placeholder_choices

/datum/unit_test/dq_no_placeholder_choices/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	for(var/key in GLOB.preference_entries_by_key)
		var/datum/preference/pref = GLOB.preference_entries_by_key[key]
		if(istype(pref, /datum/preference/choiced))
			var/datum/preference/choiced/choiced = pref
			check_list("[pref.type] get_choices()", choiced.get_choices())
		var/list/choices = pref.get_pref_choices(P)
		if(islist(choices))
			check_list("[pref.type] get_pref_choices()", choices)

	check_list("hair_styles_list", GLOB.hair_styles_list)
	check_list("facial_hair_styles_list", GLOB.facial_hair_styles_list)
	check_list("body_marking_styles_list", GLOB.body_marking_styles_list)
	check_list("ear_styles_list", GLOB.ear_styles_list)
	check_list("tail_styles_list", GLOB.tail_styles_list)
	check_list("wing_styles_list", GLOB.wing_styles_list)
	check_list("hair_accesories_list", GLOB.hair_accesories_list)
	check_list("spawntypes", GLOB.spawntypes)
	check_list("playable_species", GLOB.playable_species)

	// A placeholder is never accepted as a saved value either.
	var/datum/preference/hair = GLOB.preference_entries[/datum/preference/text/human/h_style]
	TEST_ASSERT(!hair.validate(P, DEVELOPER_WARNING_NAME), "h_style accepted the placeholder name as a saved value")

/datum/unit_test/dq_no_placeholder_choices/proc/check_list(label, list/L)
	for(var/key in L)
		if(isnull(key) || key == "")
			TEST_FAIL("[label]: offers an empty entry")
			continue
		if(is_placeholder_choice(key))
			TEST_FAIL("[label]: offers placeholder entry [key]")
		if(!isnum(key))
			var/value = L[key]
			if(!isnull(value) && is_placeholder_choice(value))
				TEST_FAIL("[label]: entry [key] holds placeholder [value]")
