// A character's palette: five named colours that colour fields link to. A linked field saves the slot's name
// ("primary") instead of a hex, read_preference() resolves it to the slot's current colour, and so changing a slot
// moves every field linked to it while everything outside the character setup still reads plain hex.
// read_preference_raw() is the stored form, for code that reads, edits and writes back.

/// The slot pref of a slot name, or null when `name` is not one. Every linkable field stores one of these names or a hex.
/proc/dq_color_slot_type(name)
	var/static/list/slots = list(
		"primary" = /datum/preference/color/human/color_slot/primary,
		"secondary" = /datum/preference/color/human/color_slot/secondary,
		"tertiary" = /datum/preference/color/human/color_slot/tertiary,
		"extra1" = /datum/preference/color/human/color_slot/extra1,
		"extra2" = /datum/preference/color/human/color_slot/extra2,
	)
	return istext(name) ? slots[name] : null

/// The hex a stored colour (slot name or hex) stands for.
/datum/preferences/proc/resolve_color_link(stored)
	var/slot_type = dq_color_slot_type(stored)
	return slot_type ? read_preference(slot_type) : stored

/datum/preference/color/human/color_slot
	abstract_type = /datum/preference/color/human/color_slot
	savefile_identifier = PREFERENCE_CHARACTER
	category = "appearance"
	group = "palette"
	can_randomize = FALSE
	/// This slot's place in a save's old eight-colour list.
	var/old_palette_index
	/// A colour field whose saved colour seeds this slot when the old list has no entry for it.
	var/seed_key
	var/fallback = "#ffffff"

/datum/preference/color/human/color_slot/create_default_value()
	return fallback

/// Migration: the first five colours of an old palette become the slots, the rest seed from the character's own colours.
/datum/preference/color/human/color_slot/create_informed_default_value(datum/preferences/preferences)
	var/list/save_data = preferences.get_save_data_for_savefile_identifier(PREFERENCE_CHARACTER)
	var/list/old_palette = save_data?["color_palette"]
	if(islist(old_palette) && length(old_palette) >= old_palette_index && is_color_text(old_palette[old_palette_index]))
		return lowertext(sanitize_hexcolor(old_palette[old_palette_index]))
	if(seed_key && is_color_text(save_data?[seed_key]))
		return lowertext(sanitize_hexcolor(save_data[seed_key]))
	return fallback

/datum/preference/color/human/color_slot/proc/is_color_text(value)
	return istext(value) && findtext(value, GLOB.is_color)

/datum/preference/color/human/color_slot/apply_to_human(mob/living/carbon/human/target, value)
	return

/datum/preference/color/human/color_slot/primary
	savefile_key = "palette_primary"
	display_label = "Primary"
	old_palette_index = 1
	seed_key = "skin_color"

/datum/preference/color/human/color_slot/secondary
	savefile_key = "palette_secondary"
	display_label = "Secondary"
	old_palette_index = 2
	seed_key = "hair_color"

/datum/preference/color/human/color_slot/tertiary
	savefile_key = "palette_tertiary"
	display_label = "Tertiary"
	old_palette_index = 3
	seed_key = "eyes_color"

/datum/preference/color/human/color_slot/extra1
	savefile_key = "palette_extra1"
	display_label = "Extra 1"
	old_palette_index = 4
	fallback = "#c8c8cc"

/datum/preference/color/human/color_slot/extra2
	savefile_key = "palette_extra2"
	display_label = "Extra 2"
	old_palette_index = 5
	fallback = "#1c1c20"

// The fields that can link.
/datum/preference/color/human/hair_color
	linkable = TRUE
/datum/preference/color/human/facial_color
	linkable = TRUE
/datum/preference/color/human/grad_color
	linkable = TRUE
/datum/preference/color/human/eyes_color
	linkable = TRUE
/datum/preference/color/human/skin_color
	linkable = TRUE
/datum/preference/color/human/synth_color
	linkable = TRUE
/datum/preference/color/human/ears_color1
	linkable = TRUE
/datum/preference/color/human/ears_color2
	linkable = TRUE
/datum/preference/color/human/ears_color3
	linkable = TRUE
/datum/preference/color/human/tail_color1
	linkable = TRUE
/datum/preference/color/human/tail_color2
	linkable = TRUE
/datum/preference/color/human/tail_color3
	linkable = TRUE
/datum/preference/color/human/wing_color1
	linkable = TRUE
/datum/preference/color/human/wing_color2
	linkable = TRUE
/datum/preference/color/human/wing_color3
	linkable = TRUE

/// A part gaining a style starts on the palette: its channels link to Primary, Secondary and Tertiary. A part that
/// already had a style keeps its colours.
/datum/preference_constraint/new_part_links_palette
	triggers = list("ear_style", "tail_style", "wing_style")
	affects = list("ears_color1", "ears_color2", "ears_color3", "tail_color1", "tail_color2", "tail_color3", "wing_color1", "wing_color2", "wing_color3")

/datum/preference_constraint/new_part_links_palette/apply(datum/preferences/preferences, changed_key, old_value, new_value)
	if(old_value || !new_value)
		return
	var/static/list/channels_by_style = list(
		"ear_style" = list(/datum/preference/color/human/ears_color1, /datum/preference/color/human/ears_color2, /datum/preference/color/human/ears_color3),
		"tail_style" = list(/datum/preference/color/human/tail_color1, /datum/preference/color/human/tail_color2, /datum/preference/color/human/tail_color3),
		"wing_style" = list(/datum/preference/color/human/wing_color1, /datum/preference/color/human/wing_color2, /datum/preference/color/human/wing_color3),
	)
	var/list/channels = channels_by_style[changed_key]
	preferences.update_preference_by_type(channels[1], "primary")
	preferences.update_preference_by_type(channels[2], "secondary")
	preferences.update_preference_by_type(channels[3], "tertiary")

/// Write a mob's colour back to its character (round-end persistence). A colour the field already resolves to keeps
/// the field's link; a colour that changed in the round becomes the field's own.
/datum/preferences/proc/persist_color(preference_type, hex)
	if(lowertext(read_preference(preference_type)) == lowertext(sanitize_hexcolor(hex)))
		return TRUE
	return update_preference_by_type(preference_type, hex)

/// The same for a mob's markings: a zone whose colour is still what its link resolves to stays linked.
/datum/preferences/proc/persist_markings(list/incoming)
	var/list/stored = read_preference_raw(/datum/preference/body_markings)
	for(var/marking in incoming)
		var/list/zones = incoming[marking]
		var/list/old_zones = stored[marking]
		if(!islist(zones) || !islist(old_zones))
			continue
		for(var/zone in zones)
			if(zone == "color")
				if(dq_color_slot_type(old_zones[zone]) && lowertext(resolve_color_link(old_zones[zone])) == lowertext(zones[zone]))
					zones[zone] = old_zones[zone]
				continue
			var/list/entry = zones[zone]
			var/list/old_entry = old_zones[zone]
			if(!islist(entry) || !islist(old_entry) || !dq_color_slot_type(old_entry["color"]))
				continue
			if(lowertext(resolve_color_link(old_entry["color"])) == lowertext(entry["color"]))
				entry["color"] = old_entry["color"]
	return update_preference_by_type(/datum/preference/body_markings, incoming)
