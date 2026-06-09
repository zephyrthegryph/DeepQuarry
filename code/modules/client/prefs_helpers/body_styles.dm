// equip_preview_mob, animations_toggle, bgstate, ear_style, ear_secondary_style,
// ear_secondary_colors, tail_style, wing_style migrated to /datum/preference subtypes.
// bgstate_options moved onto /datum/preference/text/human/bgstate as bgstate_choices.
// markings_subwindow stays as runtime UI state.
/datum/preferences
	var/datum/browser/markings_subwindow = null

// Sanitize ear/wing/tail styles
/datum/preferences/proc/sanitize_body_styles()
	// migrated ear/tail/wing styles to /datum/preference
	var/_ear_style = read_preference(/datum/preference/text/human/ear_style)
	var/_ear_secondary_style = read_preference(/datum/preference/text/human/ear_secondary_style)
	var/_wing_style = read_preference(/datum/preference/text/human/wing_style)
	var/_tail_style = read_preference(/datum/preference/text/human/tail_style)

	// Grandfather in anyone loading paths from a save.
	if(ispath(_ear_style, /datum/sprite_accessory))
		var/datum/sprite_accessory/instance = GLOB.ear_styles_list[_ear_style]
		if(istype(instance))
			_ear_style = instance.name
			update_preference_by_type(/datum/preference/text/human/ear_style, _ear_style)
	if(ispath(_wing_style, /datum/sprite_accessory))
		var/datum/sprite_accessory/instance = GLOB.wing_styles_list[_wing_style]
		if(istype(instance))
			_wing_style = instance.name
			update_preference_by_type(/datum/preference/text/human/wing_style, _wing_style)
	if(ispath(_tail_style, /datum/sprite_accessory))
		var/datum/sprite_accessory/instance = GLOB.tail_styles_list[_tail_style]
		if(istype(instance))
			_tail_style = instance.name
			update_preference_by_type(/datum/preference/text/human/tail_style, _tail_style)

	// Sanitize for non-existent keys.
	if(_ear_style && !(_ear_style in get_available_styles(GLOB.ear_styles_list)))
		update_preference_by_type(/datum/preference/text/human/ear_style, null)
	if(_ear_secondary_style && !(_ear_secondary_style in get_available_styles(GLOB.ear_styles_list)))
		update_preference_by_type(/datum/preference/text/human/ear_secondary_style, null)
	if(_wing_style && !(_wing_style in get_available_styles(GLOB.wing_styles_list)))
		update_preference_by_type(/datum/preference/text/human/wing_style, null)
	if(_tail_style && !(_tail_style in get_available_styles(GLOB.tail_styles_list)))
		update_preference_by_type(/datum/preference/text/human/tail_style, null)

/datum/preferences/proc/get_available_styles(style_list)
	. = list("Normal" = null)
	var/pref_species = read_preference(/datum/preference/choiced/species)
	for(var/path in style_list)
		var/datum/sprite_accessory/instance = style_list[path]
		if(!istype(instance))
			continue
		if(instance.name == DEVELOPER_WARNING_NAME)
			continue
		if(instance.ckeys_allowed && (!client || !(client.ckey in instance.ckeys_allowed)))
			continue
		var/_custom_base = read_preference(/datum/preference/text/human/custom_base) // migrated pref
		if(instance.species_allowed && (!pref_species || !(pref_species in instance.species_allowed)) && (!client || !check_rights_for(client, R_ADMIN | R_EVENT | R_FUN)) && (!_custom_base || !(_custom_base in instance.species_allowed)))
			continue
		if(!instance.can_be_selected && (!client || !check_rights_for(client, R_HOLDER)))
			continue
		.[instance.name] = instance

/datum/preferences/proc/mass_edit_marking_list(marking, change_on = TRUE, change_color = TRUE, marking_value = null, on = TRUE, color = "#000000")
	var/datum/sprite_accessory/marking/mark_datum = GLOB.body_marking_styles_list[marking]
	var/list/new_marking = marking_value||mark_datum.body_parts
	for (var/NM in new_marking)
		if (marking_value && !islist(new_marking[NM])) continue
		new_marking[NM] = list("on" = (!change_on && marking_value) ? marking_value[NM]["on"] : on, "color" = (!change_color && marking_value) ? marking_value[NM]["color"] : color)
	if (change_color)
		new_marking["color"] = color
	return new_marking


// /datum/category_item/player_setup_item/general/body and all its tgui_data/
// tgui_act/tgui_constant_data/has_flag/reset_limbs helpers were the Bay-prefs Body tab.
// Deleted; the new auto-renderer + accessories/markings apply_hooks own the equivalent.
