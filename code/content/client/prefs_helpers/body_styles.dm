// equip_preview_mob, animations_toggle, bgstate, ear_style, ear_secondary_style,
// ear_secondary_colors, tail_style, wing_style migrated to /datum/preference subtypes.
// bgstate_options moved onto /datum/preference/text/human/bgstate as bgstate_choices.
// Sanitize ear/wing/tail styles
/datum/preferences/proc/get_available_styles(style_list)
	. = list("Normal" = null)
	var/pref_species = read_preference(/datum/preference/choiced/species)
	for(var/path in style_list)
		var/datum/sprite_accessory/instance = style_list[path]
		if(!istype(instance))
			continue
		if(instance.name == DEVELOPER_WARNING_NAME)
			continue
		if(instance.ckeys_allowed && (!client() || !(client().ckey in instance.ckeys_allowed)))
			continue
		var/_custom_base = read_preference(/datum/preference/text/human/custom_base) // migrated pref
		if(instance.species_allowed && (!pref_species || !(pref_species in instance.species_allowed)) && (!client() || !check_rights_for(client(), R_ADMIN | R_EVENT | R_FUN)) && (!_custom_base || !(_custom_base in instance.species_allowed)))
			continue
		if(!instance.can_be_selected && (!client() || !check_rights_for(client(), R_HOLDER)))
			continue
		.[instance.name] = instance

/datum/preferences/proc/mass_edit_marking_list(marking, change_on = TRUE, change_color = TRUE, marking_value = null, on = TRUE, color = "#000000")
	var/datum/sprite_accessory/marking/mark_datum = GLOB.body_marking_styles_list[marking]
	// A new marking gets its own zone table: editing the accessory's shared body_parts list in place turned it into this
	// character's zone -> state table for every player (and the window's catalog then listed states, not parts).
	var/list/new_marking = marking_value || mark_datum.body_parts_for_edit().Copy()
	for (var/NM in new_marking)
		if (marking_value && !islist(new_marking[NM])) continue
		new_marking[NM] = list("on" = (!change_on && marking_value) ? marking_value[NM]["on"] : on, "color" = (!change_color && marking_value) ? marking_value[NM]["color"] : color)
	if (change_color)
		new_marking["color"] = color
	return new_marking


// /datum/category_item/player_setup_item/general/body and all its tgui_data/
// tgui_act/tgui_constant_data/has_flag/reset_limbs helpers were the Bay-prefs Body tab.
// Deleted; the new auto-renderer + accessories/markings apply_hooks own the equivalent.
