/datum/preference/toggle/living/dark_retreat_toggle
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_key = "DARK_RETREAT_TOGGLE"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/living/dark_retreat_toggle/apply_to_living(mob/living/target, value)
	var/datum/shadekin/our_SK = target.get_shadekin_state()
	if(our_SK)
		our_SK.set_no_retreat(value)

/datum/preference/toggle/living/shadekin_nutrition_conversion
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_key = "SHADEKIN_NUTRITION_CONVERSION"
	default_value = FALSE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/living/shadekin_nutrition_conversion/apply_to_living(mob/living/target, value)
	var/datum/shadekin/our_SK = target.get_shadekin_state()
	if(our_SK)
		our_SK.set_nutrition_energy_conversion(value)

/datum/preference/toggle/living/shadekin_hide_voice_in_phase
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	savefile_key = "SHADEKIN_HIDE_VOICE_IN_PHASE"
	default_value = TRUE
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/toggle/living/shadekin_hide_voice_in_phase/apply_to_living(mob/living/target, value)
	var/datum/shadekin/our_SK = target.get_shadekin_state()
	if(our_SK)
		our_SK.set_hide_voice_in_phase(value)
