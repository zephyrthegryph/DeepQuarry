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
	widget = PREF_WIDGET_NUMBER  // slider over 0–10000 was nonsense precision; use a number input.
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	minimum = 0
	maximum = 10000

/datum/preference/numeric/human/weight_vr/create_default_value()
	return 137

/datum/preference/numeric/human/weight_vr/apply_to_human(mob/living/carbon/human/target, value)
	target.weight = value


/datum/preference/numeric/human/weight_gain
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "weight_gain"
	display_label = "Weight Gain Rate"
	widget = PREF_WIDGET_NUMBER
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	minimum = 0
	maximum = 1000

/datum/preference/numeric/human/weight_gain/create_default_value()
	return 100

/datum/preference/numeric/human/weight_gain/apply_to_human(mob/living/carbon/human/target, value)
	target.weight_gain = value


/datum/preference/numeric/human/weight_loss
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "weight_loss"
	display_label = "Weight Loss Rate"
	widget = PREF_WIDGET_NUMBER
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	minimum = 0
	maximum = 1000

/datum/preference/numeric/human/weight_loss/create_default_value()
	return 50

/datum/preference/numeric/human/weight_loss/apply_to_human(mob/living/carbon/human/target, value)
	target.weight_loss = value


/datum/preference/toggle/human/fuzzy
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "fuzzy"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/fuzzy/apply_to_human(mob/living/carbon/human/target, value)
	target.fuzzy = value


/datum/preference/toggle/human/offset_override
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "offset_override"
	default_value = TRUE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/offset_override/apply_to_human(mob/living/carbon/human/target, value)
	target.offset_override = value


/datum/preference/numeric/human/voice_freq
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "voice_freq"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	// DQEdit — was 0..999999 (every audible frequency ever); the useful range for voice
	// pitching is roughly 20000-80000Hz with 42500 as the natural-sounding default.
	minimum = 20000
	maximum = 80000
	step = 500

/datum/preference/numeric/human/voice_freq/create_default_value()
	return 42500

/datum/preference/numeric/human/voice_freq/apply_to_human(mob/living/carbon/human/target, value)
	target.voice_freq = value


/datum/preference/text/human/voice_sound
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "voice_sound"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/voice_sound/create_default_value()
	return "beep-boop"

/datum/preference/text/human/voice_sound/get_pref_choices(datum/preferences/preferences)
	return SSsounds?.talk_sound_map ? assoc_to_keys(SSsounds.talk_sound_map) : null

/datum/preference/text/human/voice_sound/apply_to_human(mob/living/carbon/human/target, value)
	if(!value)
		target.voice_sounds_list = DEFAULT_TALK_SOUNDS
	else
		target.voice_sounds_list = get_talk_sound(value)


/datum/preference/text/human/custom_speech_bubble
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "custom_speech_bubble"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/custom_speech_bubble/create_default_value()
	return "default"

/datum/preference/text/human/custom_speech_bubble/get_pref_choices(datum/preferences/preferences)
	return GLOB.selectable_speech_bubbles

/datum/preference/text/human/custom_speech_bubble/apply_to_human(mob/living/carbon/human/target, value)
	target.custom_speech_bubble = value


/datum/preference/text/human/custom_footstep
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "custom_footstep"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/custom_footstep/create_default_value()
	return "Default"

/datum/preference/text/human/custom_footstep/get_pref_choices(datum/preferences/preferences)
	// GLOB.selectable_footstep is display-name -> FOOTSTEP_MOB_* constant. Showing display
	// names in the dropdown and translating on apply.
	return GLOB.selectable_footstep ? assoc_to_keys(GLOB.selectable_footstep) : null

/datum/preference/text/human/custom_footstep/apply_to_human(mob/living/carbon/human/target, value)
	target.custom_footstep = GLOB.selectable_footstep[value] || FOOTSTEP_MOB_HUMAN


/datum/preference/text/human/species_sound
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "species_sound"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/species_sound/create_default_value()
	return "Unset"

/datum/preference/text/human/species_sound/get_pref_choices(datum/preferences/preferences)
	if(!GLOB.species_sound_map)
		return null
	return list("Unset") + assoc_to_keys(GLOB.species_sound_map)

/datum/preference/text/human/species_sound/apply_to_human(mob/living/carbon/human/target, value)
	return
