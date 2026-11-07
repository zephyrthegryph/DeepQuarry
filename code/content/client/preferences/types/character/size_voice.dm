// DQ-migrated: size + voice + footstep scalar prefs.

/datum/preference/numeric/human/size_multiplier
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "size_multiplier"
	display_label = "Body Size"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	// 0.5×–2× covers everything from very small to very large; previous 0.1–10 range had
	// useless slider precision at the extremes.
	minimum = 0.5
	maximum = 2
	step = 0.05

/datum/preference/numeric/human/size_multiplier/create_default_value()
	return RESIZE_NORMAL

/datum/preference/numeric/human/size_multiplier/apply_to_human(mob/living/carbon/human/target, value)
	target.resize(value, animate = FALSE, ignore_prefs = TRUE)


/datum/preference/numeric/human/weight_vr
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "weight_vr"
	display_label = "Body Weight"
	widget = PREF_WIDGET_NUMBER
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	minimum = WEIGHT_MIN // pounds; saved values outside are clamped on load (numeric pref_deserialize, and the sanitize below)
	maximum = WEIGHT_MAX

/datum/preference/numeric/human/weight_vr/create_default_value()
	return 137

/datum/preference/numeric/human/weight_vr/apply_to_human(mob/living/carbon/human/target, value)
	STATE_SET(target, bodyweight, weight, value)






/datum/preference/numeric/human/voice_freq
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "voice_freq"
	savefile_identifier = PREFERENCE_CHARACTER
	applies_live = TRUE
	can_randomize = FALSE
	// was 0..999999 (every audible frequency ever); the useful range for voice
	// pitching is roughly 20000-80000Hz with 42500 as the natural-sounding default.
	minimum = 20000
	maximum = 80000
	step = 500

/datum/preference/numeric/human/voice_freq/create_default_value()
	return 42500

/datum/preference/numeric/human/voice_freq/apply_to_human(mob/living/carbon/human/target, value)
	STATE_SET(target, mob_misc, voice_freq, value)


/datum/preference/text/human/voice_sound
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "voice_sound"
	savefile_identifier = PREFERENCE_CHARACTER
	applies_live = TRUE
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/voice_sound/create_default_value()
	return "beep-boop"

/datum/preference/text/human/voice_sound/get_pref_choices(datum/preferences/preferences)
	return assoc_to_keys(SSsounds.ready().talk_sound_sets())

/datum/preference/text/human/voice_sound/apply_to_human(mob/living/carbon/human/target, value)
	if(!value)
		STATE_SET(target, mob_misc, voice_sounds_list, DEFAULT_TALK_SOUNDS)
	else
		STATE_SET(target, mob_misc, voice_sounds_list, get_talk_sound(value))



