// DQ-migrated: NIF prefs route through the main per-character savefile alongside everything else.

/datum/preference/nif_path
	savefile_key = "nif_path"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/nif_path/create_default_value()
	return null

/datum/preference/nif_path/pref_deserialize(input, datum/preferences/preferences)
	if(istext(input))
		var/path = text2path(input)
		if(ispath(path, /obj/item/nif))
			return path
		return null
	if(ispath(input, /obj/item/nif))
		return input
	return null

/datum/preference/nif_path/pref_serialize(input)
	if(ispath(input, /obj/item/nif))
		return "[input]"
	return null

/datum/preference/nif_path/is_valid(value)
	return isnull(value) || ispath(value, /obj/item/nif)

/datum/preference/nif_path/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/nif_path/apply_to_living(mob/living/target, value)
	return
/datum/preference/nif_path/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/nif_path/apply_to_animal(mob/living/simple_mob/target, value)
	return


/datum/preference/numeric/nif_durability
	savefile_key = "nif_durability"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE
	minimum = 0
	maximum = 100000

/datum/preference/numeric/nif_durability/create_default_value()
	return null

// Bypass /datum/preference/numeric/pref_(de)serialize which round-trips through
// sanitize_float and silently coerces null → 0 — that 0 then fails is_valid below,
// which makes write_preference return FALSE and CRASHes the whole read_preference
// chain (every prefs read/write blew up on character load and on render).
/datum/preference/numeric/nif_durability/pref_deserialize(input, datum/preferences/preferences)
	if(isnull(input))
		return null
	return ..()

/datum/preference/numeric/nif_durability/pref_serialize(input)
	if(isnull(input))
		return null
	return ..()

/datum/preference/numeric/nif_durability/is_valid(value)
	// Tighter than the default isnum check: durability seeded with `null` means "no NIF
	// installed" and the nif_durability_hydration constraint relies on isnull(...) to
	// know it should hydrate from the spawned NIF's initial. sanitize_float coerces null
	// to 0 silently, so 0 would otherwise sneak in and skip hydration. Treat 0 the same
	// as null here so the constraint catches both.
	return isnull(value) || (isnum(value) && value > 0)

/datum/preference/numeric/nif_durability/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/nif_savedata
	savefile_key = "nif_savedata"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/nif_savedata/create_default_value()
	return list()

/datum/preference/nif_savedata/pref_deserialize(input, datum/preferences/preferences)
	if(!islist(input))
		return list()
	return input

/datum/preference/nif_savedata/pref_serialize(input)
	if(!islist(input))
		return list()
	return check_list_copy(input)

/datum/preference/nif_savedata/is_valid(value)
	return islist(value)

/datum/preference/nif_savedata/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/nif_savedata/apply_to_living(mob/living/target, value)
	return
/datum/preference/nif_savedata/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/nif_savedata/apply_to_animal(mob/living/simple_mob/target, value)
	return
