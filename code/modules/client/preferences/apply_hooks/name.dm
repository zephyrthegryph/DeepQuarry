// DQAdd — Re-sanitize the character's real_name on spawn using species rules + FBP
// classification, then inject a surname if config requires one. This depends on both
// real_name and species so it can't live on either pref alone.

/datum/preference_apply_hook/name_sanitization
	priority = APPLY_HOOK_PRIORITY_NAME
	skip_on_preview = TRUE

/datum/preference_apply_hook/name_sanitization/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target))
		return

	var/char_real_name = preferences.read_preference(/datum/preference/name/real_name)
	var/char_id_gender = preferences.read_preference(/datum/preference/choiced/gender/identifying)
	var/pref_species = preferences.read_preference(/datum/preference/choiced/species)

	// Inline FBP detection — mirrors /datum/category_item/player_setup_item/proc/is_FBP()
	// which keys off the saved organ_data showing a cyborg torso.
	var/list/organ_data = preferences.read_preference(/datum/preference/organ_data)
	var/is_fbp = !(organ_data && organ_data[BP_TORSO] != "cyborg")

	// Fixes being able to swap from FBP to organic before round join to be organic with numbers in name.
	char_real_name = sanitize_name(char_real_name, pref_species, is_fbp)
	if(!char_real_name)
		char_real_name = random_name(char_id_gender, pref_species)

	if(CONFIG_GET(flag/humans_need_surnames))
		var/firstspace = findtext(char_real_name, " ")
		var/name_length = length(char_real_name)
		if(!firstspace)
			char_real_name += " [pick(GLOB.last_names)]"
		else if(firstspace == name_length)
			char_real_name += "[pick(GLOB.last_names)]"

	target.real_name = char_real_name
	target.name = target.real_name
	if(target.dna)
		target.dna.real_name = target.real_name
