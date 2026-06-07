// DQAdd — Species + trait synthesis. Builds the character's actual species datum from the
// chosen species + saved trait list via species.produceCopy(), applies each trait's pref,
// then writes blood color/blood reagents/species sounds.
//
// This is the heaviest cross-pref hook. It touches species + 3 trait lists + custom_base +
// blood_color + blood_reagents + species_sound + custom_say behavior. Must run early enough
// for downstream hooks (organs, accessories, markings) to see the synthesized species.

/datum/preference_apply_hook/traits
	priority = APPLY_HOOK_PRIORITY_SPECIES

/datum/preference_apply_hook/traits/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target))
		return

	// Detect synthetic vs organic so the trait filter can use it.
	// DQEdit — write_preference_by_type, not update_, to avoid re-triggering the preview
	// cascade that called this hook in the first place (would infinite-recurse).
	if(target.isSynthetic())
		preferences.write_preference_by_type(/datum/preference/toggle/human/dirty_synth, 1)
		preferences.write_preference_by_type(/datum/preference/toggle/human/gross_meatbag, 0)
	else
		preferences.write_preference_by_type(/datum/preference/toggle/human/gross_meatbag, 1)
		preferences.write_preference_by_type(/datum/preference/toggle/human/dirty_synth, 0)

	var/list/pos_traits = preferences.read_preference(/datum/preference/typed_list/traits/pos_traits)
	var/list/neu_traits = preferences.read_preference(/datum/preference/typed_list/traits/neu_traits)
	var/list/neg_traits = preferences.read_preference(/datum/preference/typed_list/traits/neg_traits)
	var/datum/species/S = target.species
	if(!S)
		return

	var/datum/species/new_S = S.produceCopy(pos_traits + neu_traits + neg_traits, target, preferences.read_preference(/datum/preference/text/human/custom_base), TRUE)

	for(var/datum/trait/T in new_S.traits)
		T.apply_pref(preferences)

	new_S.blood_color = preferences.read_preference(/datum/preference/color/human/blood_color)
	var/blood_reagents = preferences.read_preference(/datum/preference/text/human/blood_reagents)
	if(blood_reagents != "default")
		new_S.blood_reagents = blood_reagents

	var/species_sounds_to_copy = preferences.read_preference(/datum/preference/text/human/species_sound)
	if(species_sounds_to_copy == "Unset")
		species_sounds_to_copy = select_default_species_sound(preferences)
	new_S.species_sounds = species_sounds_to_copy

	if(preferences.read_preference(/datum/preference/choiced/species) == SPECIES_CUSTOM)
		var/english_traits = english_list(new_S.traits, and_text = ";", comma_text = ";")
		log_game("TRAITS [preferences.client_ckey]/([target]) with: [english_traits]")
