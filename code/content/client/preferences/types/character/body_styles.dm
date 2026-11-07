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
	return dq_part_style_thumbs(GLOB.ear_styles_list, preferences)

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
	return dq_part_style_thumbs(GLOB.ear_styles_list, preferences)

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

/// The tail styles, and the Legs picker's Normal and Digitigrade (it shows the taur bodies among the tails' thumbnails).
/datum/preference/text/human/tail_style/get_pref_thumbnails(datum/preferences/preferences)
	var/list/out = sprite_accessory_thumbs(GLOB.tail_styles_list) || list()
	out["plantigrade"] = list("layers" = dq_body_thumb_layers(preferences))
	out["digitigrade"] = list("layers" = dq_body_thumb_layers(preferences, digitigrade = TRUE))
	return out

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
	return dq_part_style_thumbs(GLOB.wing_styles_list, preferences)

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
			"channels" = S.get_color_channel_count(),
			"taur" = istaurtail(S),
		)
	return out


/// The character's body as thumbnail layers, bottom first: the species' parts (its custom base's for a custom species),
/// in the body's gender, the legs and feet digitigrade when `digitigrade`. A species with a chosen skin colour names
/// it "skin" with the blend its body uses; the window fills in the colour. Drawn by the None style of a part and by the
/// Normal and Digitigrade legs, so they show the body the way the other styles show their sprites.
/proc/dq_body_thumb_layers(datum/preferences/preferences, digitigrade = FALSE)
	var/datum/species/S = GLOB.all_species[preferences?.read_preference(/datum/preference/choiced/species)]
	if(S?.name == SPECIES_CUSTOM)
		S = GLOB.all_species[preferences.read_preference(/datum/preference/text/human/custom_base)] || S
	if(!S)
		S = GLOB.all_species[SPECIES_HUMAN]
	if(!S)
		return list()
	var/gender = preferences?.read_preference(/datum/preference/choiced/gender/biological) == FEMALE ? "f" : "m"
	var/tint = (S.appearance_flags & HAS_SKIN_COLOR) ? "skin" : null
	var/blend = S.color_mult ? "multiply" : "add"
	var/static/list/leg_states = list("r_leg", "l_leg", "r_foot", "l_foot")
	var/list/out = list()
	for(var/state in leg_states + list("groin_[gender]", "torso_[gender]", "r_arm", "l_arm", "r_hand", "l_hand", "head_[gender]"))
		var/file = (digitigrade && (state in leg_states)) ? S.icodigi : S.icobase
		if(!file)
			continue
		out += list(list("icon" = "[REF(file)]", "icon_state" = state, "color" = tint, "blend" = blend))
	return out

/// A part's style thumbnails with None as the body without the part: its layers sit under every other style's sprite.
/proc/dq_part_style_thumbs(list/accessory_list, datum/preferences/preferences)
	var/list/out = sprite_accessory_thumbs(accessory_list) || list()
	out[""] = list("layers" = dq_body_thumb_layers(preferences), "base" = TRUE)
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


// What the preview mannequin wears: the loadout, the job outfit. (They replaced the equip_preview_mob bitfield;
// load_character() migrates an old save.)
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
