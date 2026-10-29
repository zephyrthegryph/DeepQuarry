// A character's own colour palette: up to DQ_COLOR_PALETTE_MAX colours the character setup offers first in
// every colour picker (body parts, hair, markings, ...). Pure UI state: it changes nothing on the mob.

#define DQ_COLOR_PALETTE_MAX 8

/datum/preference/color_palette
	savefile_key = "color_palette"
	savefile_identifier = PREFERENCE_CHARACTER
	category = "appearance"
	group = "palette"
	widget = PREF_WIDGET_PALETTE
	display_label = "Palette"
	can_randomize = FALSE

/datum/preference/color_palette/create_default_value()
	return list()

/// A list of "#rrggbb" strings, deduplicated (case-insensitive), at most DQ_COLOR_PALETTE_MAX; anything else is dropped.
/datum/preference/color_palette/proc/clean(input)
	var/list/out = list()
	if(!islist(input))
		return out
	for(var/entry in input)
		if(!istext(entry) || !findtext(entry, GLOB.is_color))
			continue
		var/hex = lowertext(sanitize_hexcolor(entry))
		if(hex in out)
			continue
		out += hex
		if(length(out) >= DQ_COLOR_PALETTE_MAX)
			break
	return out

/datum/preference/color_palette/pref_deserialize(input, datum/preferences/preferences)
	return clean(input)

/datum/preference/color_palette/pref_serialize(input)
	return clean(input)

/datum/preference/color_palette/is_valid(value)
	if(!islist(value) || length(value) > DQ_COLOR_PALETTE_MAX)
		return FALSE
	for(var/entry in value)
		if(!istext(entry) || !findtext(entry, GLOB.is_color))
			return FALSE
	return TRUE

/datum/preference/color_palette/apply_to_human(mob/living/carbon/human/target, value)
	return
/datum/preference/color_palette/apply_to_living(mob/living/target, value)
	return
/datum/preference/color_palette/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/color_palette/apply_to_animal(mob/living/simple_mob/target, value)
	return

#undef DQ_COLOR_PALETTE_MAX
