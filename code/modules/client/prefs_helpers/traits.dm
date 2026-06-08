#define POSITIVE_MODE 1
#define NEUTRAL_MODE 2
#define NEGATIVE_MODE 3

// custom_base, blood_color, pos_traits/neu_traits/neg_traits,
// traits_cheating/starting_trait_points/max_traits, dirty_synth, gross_meatbag
// all migrated to /datum/preference subtypes. Legacy declarations deleted.

/datum/preferences/proc/get_custom_bases_for_species(new_species)
	if (!new_species)
		new_species = read_preference(/datum/preference/choiced/species)
	var/list/choices
	var/datum/species/spec = GLOB.all_species[new_species]
	if (spec.selects_bodytype == SELECTS_BODYTYPE_SHAPESHIFTER)
		choices = spec.get_valid_shapeshifter_forms()
		choices = choices.Copy()
	else if (spec.selects_bodytype == SELECTS_BODYTYPE_CUSTOM)
		choices = GLOB.custom_species_bases.Copy()
		if(new_species != SPECIES_CUSTOM)
			choices = (choices | new_species)
	else if (spec.selects_bodytype == SELECTS_BODYTYPE_ZORREN)
		choices = list(SPECIES_ZORREN_HIGH,SPECIES_ZORREN_DARK)
		choices = choices.Copy()
	return choices

// /datum/category_item/player_setup_item/general/traits and helpers (the Bay
// trait picker UI) were deleted. /datum/preference_editor/trait_picker owns the new UI.

/proc/check_trait_conflict(datum/trait/our_trait, datum/trait/other_trait)
	if(our_trait.type in other_trait.excludes)
		return TRUE

	for(var/V in our_trait.var_changes)
		if(V == "flags") // Flags can stack
			continue
		if(V in other_trait.var_changes)
			return TRUE

	for(var/V in our_trait.var_changes_pref)
		if(V in other_trait.var_changes_pref)
			return TRUE

	return FALSE

#undef POSITIVE_MODE
#undef NEUTRAL_MODE
#undef NEGATIVE_MODE
