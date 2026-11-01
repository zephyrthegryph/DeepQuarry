// DQ-migrated: body-style + character preview prefs.

/datum/preference/text/human/ear_style
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "ear_style"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/ear_style/create_default_value()
	return null

/datum/preference/text/human/ear_style/get_pref_choices(datum/preferences/preferences)
	return sprite_accessory_names(GLOB.ear_styles_list)

/datum/preference/text/human/ear_style/get_pref_thumbnails(datum/preferences/preferences)
	return sprite_accessory_thumbs(GLOB.ear_styles_list)

/datum/preference/text/human/ear_style/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/text/human/ear_secondary_style
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "ear_secondary_style"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/ear_secondary_style/create_default_value()
	return null

/datum/preference/text/human/ear_secondary_style/get_pref_choices(datum/preferences/preferences)
	return sprite_accessory_names(GLOB.ear_styles_list)

/datum/preference/text/human/ear_secondary_style/get_pref_thumbnails(datum/preferences/preferences)
	return sprite_accessory_thumbs(GLOB.ear_styles_list)

/datum/preference/text/human/ear_secondary_style/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/text/human/tail_style
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "tail_style"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/tail_style/create_default_value()
	return null

/datum/preference/text/human/tail_style/get_pref_choices(datum/preferences/preferences)
	return sprite_accessory_names(GLOB.tail_styles_list)

/datum/preference/text/human/tail_style/get_pref_thumbnails(datum/preferences/preferences)
	return sprite_accessory_thumbs(GLOB.tail_styles_list)

/datum/preference/text/human/tail_style/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/text/human/wing_style
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "wing_style"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN

/datum/preference/text/human/wing_style/create_default_value()
	return null

/datum/preference/text/human/wing_style/get_pref_choices(datum/preferences/preferences)
	return sprite_accessory_names(GLOB.wing_styles_list)

/datum/preference/text/human/wing_style/get_pref_thumbnails(datum/preferences/preferences)
	return sprite_accessory_thumbs(GLOB.wing_styles_list)

/datum/preference/text/human/wing_style/apply_to_human(mob/living/carbon/human/target, value)
	return

/// The style choices of a sprite_accessory global: instance names, what a saved style holds and the apply hook looks up.
/proc/sprite_accessory_names(list/accessory_list)
	if(!accessory_list)
		return null
	var/list/out = list()
	for(var/key in accessory_list)
		var/datum/sprite_accessory/S = accessory_list[key]
		if(istype(S))
			out += S.name
	return out

// / Shared helper: build a {style_name -> {icon, icon_state}} payload from a
/// sprite_accessory global. Lives on /datum/preferences so any subtype can call it.
/// `state_suffix`: what the drawing code appends to icon_state (hair and beards are drawn from "<state>_s").
/proc/sprite_accessory_thumbs(list/accessory_list, state_suffix = "")
	if(!accessory_list)
		return null
	var/list/out = list()
	for(var/key in accessory_list)
		var/datum/sprite_accessory/S = accessory_list[key]
		if(!istype(S) || !S.icon)
			continue
		out[S.name] = list(
			"icon" = "[REF(S.icon)]",
			"icon_state" = "[S.icon_state][state_suffix]",
		)
	return out


/datum/preference/text/human/bgstate
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "bgstate"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	maximum_value_length = MAX_NAME_LEN
	// own the choice list here so get_pref_choices() returns it directly.
	var/static/list/bgstate_choices = list("steel", "000", "midgrey", "FFF", "white", "techmaint", "desert", "grass", "snow")

/datum/preference/text/human/bgstate/create_default_value()
	return "steel"

/datum/preference/text/human/bgstate/get_pref_choices(datum/preferences/preferences)
	return bgstate_choices

/datum/preference/text/human/bgstate/get_widget(datum/preferences/preferences)
	return PREF_WIDGET_DROPDOWN

/datum/preference/text/human/bgstate/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/numeric/human/equip_preview_mob
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "equip_preview_mob"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	minimum = 0
	maximum = 65535
	widget = PREF_WIDGET_HIDDEN  // bitfield; surfaced via the two toggles below

// two toggles that mirror the equip_preview_mob bitfield. Cleaner UX than a single
// 0-65535 numeric. The actual pref stays a bitfield so existing consumers keep working;
// the toggles bridge into it via apply hooks.
/datum/preference/toggle/human/preview_loadout
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "preview_loadout"
	savefile_identifier = PREFERENCE_CHARACTER
	default_value = TRUE
	can_randomize = FALSE

/datum/preference/toggle/human/preview_loadout/apply_to_human(mob/living/carbon/human/target, value)
	return

/datum/preference/toggle/human/preview_job
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "preview_job"
	savefile_identifier = PREFERENCE_CHARACTER
	default_value = TRUE
	can_randomize = FALSE

/datum/preference/toggle/human/preview_job/apply_to_human(mob/living/carbon/human/target, value)
	return

/datum/preference/numeric/human/equip_preview_mob/create_default_value()
	return EQUIP_PREVIEW_ALL

/datum/preference/numeric/human/equip_preview_mob/apply_to_human(mob/living/carbon/human/target, value)
	return


/datum/preference/toggle/human/animations_toggle
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "animations_toggle"
	default_value = FALSE
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE

/datum/preference/toggle/human/animations_toggle/apply_to_human(mob/living/carbon/human/target, value)
	return


// Ears, tail and wings are optional: an empty value (the default) means the character has none, and the
// character setup's "Remove" writes it. Any other value must still be one of the styles on offer.
/datum/preference/text/human/ear_style/validate(datum/preferences/preferences, value)
	return !value || ..()

/datum/preference/text/human/ear_secondary_style/validate(datum/preferences/preferences, value)
	return !value || ..()

/datum/preference/text/human/tail_style/validate(datum/preferences/preferences, value)
	return !value || ..()

/datum/preference/text/human/wing_style/validate(datum/preferences/preferences, value)
	return !value || ..()
