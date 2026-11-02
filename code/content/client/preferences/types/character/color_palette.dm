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
	/// A new character's colour, and an old save's when nothing else seeds the slot.
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
	fallback = "#c8a283"

/datum/preference/color/human/color_slot/secondary
	savefile_key = "palette_secondary"
	display_label = "Secondary"
	old_palette_index = 2
	seed_key = "hair_color"
	fallback = "#5a3b1e"

/datum/preference/color/human/color_slot/tertiary
	savefile_key = "palette_tertiary"
	display_label = "Tertiary"
	old_palette_index = 3
	seed_key = "eyes_color"
	fallback = "#3b2a1c"

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

/// The colour fields a character links, in the order that decides which spare colours become Extra 1 and Extra 2.
GLOBAL_LIST_INIT(dq_palette_fields_table, list(
		/datum/preference/color/human/skin_color = "primary",
		/datum/preference/color/human/hair_color = "secondary",
		/datum/preference/color/human/eyes_color = "tertiary",
		/datum/preference/color/human/facial_color = "secondary",
		/datum/preference/color/human/grad_color = "tertiary",
		/datum/preference/color/human/tail_color1 = "primary",
		/datum/preference/color/human/tail_color2 = "secondary",
		/datum/preference/color/human/tail_color3 = "tertiary",
		/datum/preference/color/human/ears_color1 = "primary",
		/datum/preference/color/human/ears_color2 = "secondary",
		/datum/preference/color/human/ears_color3 = "tertiary",
		/datum/preference/color/human/wing_color1 = "primary",
		/datum/preference/color/human/wing_color2 = "secondary",
		/datum/preference/color/human/wing_color3 = "tertiary",
))

/proc/dq_palette_fields()
	return GLOB.dq_palette_fields_table

/// The multiply colour closest to an old skin tone (an offset on the shaded sprite): per-channel fit against r_human's
/// body sprites. A tone above 0 brightened, which a multiply cannot: it becomes white, the unshaded sprite.
/proc/dq_skin_tone_to_color(tone)
	var/static/list/tones = list(-185, -150, -115, -75, -40, -20, 0)
	var/static/list/fits = list(list(56, 2, 0), list(94, 50, 12), list(131, 98, 69), list(174, 152, 134), list(212, 200, 190), list(234, 228, 222), list(255, 255, 255))
	tone = clamp(tone, -185, 0)
	for(var/i in 1 to length(tones) - 1)
		if(tone > tones[i + 1])
			continue
		var/weight = (tone - tones[i]) / (tones[i + 1] - tones[i])
		var/list/low = fits[i]
		var/list/high = fits[i + 1]
		return lowertext(rgb(round(LERP(low[1], high[1], weight)), round(LERP(low[2], high[2], weight)), round(LERP(low[3], high[3], weight))))
	return "#ffffff"

/// Run once per character on load (the save's "palette_linked" says it ran). A new character's fields link to the slots.
/// An existing one keeps its exact look: the slots came from its own colours, and each field or marking zone whose hex
/// equals a slot links to it; one matching no slot stays its own colour.
/datum/preferences/proc/link_palette_on_load(new_character)
	var/list/save_data = get_save_data_for_savefile_identifier(PREFERENCE_CHARACTER)
	if(save_data?["palette_linked"] || (!islist(save_data) && !new_character))
		return
	begin_update_batch()
	var/list/fields = dq_palette_fields()
	if(new_character)
		for(var/field in fields)
			update_preference_by_type(field, fields[field])
	else
		convert_old_skin_tone(save_data)
		seed_spare_slots(save_data)
		var/list/slot_of_hex = list()
		for(var/slot in list("extra2", "extra1", "tertiary", "secondary", "primary")) // the first slot wins a shared colour
			slot_of_hex[lowertext(read_preference(dq_color_slot_type(slot)))] = slot
		for(var/field in fields)
			var/stored = read_preference_raw(field)
			var/slot = istext(stored) ? slot_of_hex[lowertext(stored)] : null
			if(slot)
				update_preference_by_type(field, slot)
		var/list/markings = read_preference_raw(/datum/preference/body_markings)
		for(var/marking in markings)
			var/list/zones = markings[marking]
			if(!islist(zones))
				continue
			for(var/zone in zones)
				var/list/entry = zones[zone]
				if(zone == "color")
					if(istext(entry) && slot_of_hex[lowertext(entry)])
						zones[zone] = slot_of_hex[lowertext(entry)]
				else if(islist(entry) && istext(entry["color"]) && slot_of_hex[lowertext(entry["color"])])
					entry["color"] = slot_of_hex[lowertext(entry["color"])]
		update_preference_by_type(/datum/preference/body_markings, markings)
	end_update_batch()
	// A new character's entry exists only once the batch above has saved it.
	save_data = get_save_data_for_savefile_identifier(PREFERENCE_CHARACTER)
	if(islist(save_data))
		save_data["palette_linked"] = TRUE

/// Each robotic limb's tint: organ tag -> a palette slot's name or a hex. Read as hex, like every linked colour.
/datum/preference/limb_colors
	savefile_key = "limb_colors"
	savefile_identifier = PREFERENCE_CHARACTER
	category = PREFERENCE_CATEGORY_MANUALLY_RENDERED
	can_randomize = FALSE

/datum/preference/limb_colors/create_default_value()
	return list()

/datum/preference/limb_colors/pref_deserialize(input, datum/preferences/preferences)
	return islist(input) ? input : list()

/datum/preference/limb_colors/pref_serialize(input)
	return islist(input) ? check_list_copy(input) : list()

/datum/preference/limb_colors/is_valid(value)
	return islist(value)

/datum/preference/limb_colors/resolve_read(list/value, datum/preferences/preferences)
	if(!islist(value))
		return value
	for(var/limb in value)
		value[limb] = preferences.resolve_color_link(value[limb])
	return value

/datum/preference/limb_colors/apply_to_human(mob/living/carbon/human/target, value)
	return // the organs apply hook, once the limbs are robotic
/datum/preference/limb_colors/apply_to_living(mob/living/target, value)
	return
/datum/preference/limb_colors/apply_to_silicon(mob/living/silicon/target, value)
	return
/datum/preference/limb_colors/apply_to_animal(mob/living/simple_mob/target, value)
	return

/// Whether a species' own limbs are robotic: it has no Cybernetic rows, its whole body takes one colour.
/proc/dq_species_robotic_body(species_name)
	var/datum/species/species = GLOB.all_species[species_name]
	if(!species)
		return FALSE
	for(var/tag in species.has_limbs)
		var/list/limb = species.has_limbs[tag]
		var/obj/item/organ/external/path = limb["path"]
		if(initial(path.robotic) >= ORGAN_ROBOT)
			return TRUE
	return species_name == SPECIES_PROTEAN // its limbs turn robotic when it forms, not by type

/// Give each robotic limb its tint: its own colour, else its nearest ancestor's (robotize() recurses into children), else
/// the body's colour for a robotic species, Tertiary until that is set.
/datum/preferences/proc/apply_limb_colors(mob/living/carbon/human/target)
	var/list/colors = read_preference(/datum/preference/limb_colors)
	var/fallback
	if(dq_species_robotic_body(read_preference(/datum/preference/choiced/species)))
		fallback = colors[DQ_LIMB_COLOR_BODY] || read_preference(/datum/preference/color/human/color_slot/tertiary)
	for(var/name in target.organs_by_name)
		var/obj/item/organ/external/limb = target.organs_by_name[name]
		if(!istype(limb) || !limb.is_robotic())
			continue
		var/obj/item/organ/external/source = limb
		var/color
		while(source && !color)
			color = colors[source.organ_tag]
			source = source.parent
		limb.synth_rgb = color || fallback

/// Once per character. Every robotic limb (for a robotic species, its body) takes the old single synth colour when the old toggle
/// was on with a colour, otherwise Tertiary. The old keys stay in the save, unread after this.
/datum/preferences/proc/migrate_limb_colors()
	var/list/save_data = get_save_data_for_savefile_identifier(PREFERENCE_CHARACTER)
	if(save_data?["limb_colors_set"])
		return
	var/old_rgb = save_data?["synth_color_rgb"]
	var/value = (save_data?["synth_color"] && istext(old_rgb) && findtext(old_rgb, GLOB.is_color)) ? lowertext(sanitize_hexcolor(old_rgb)) : "tertiary"
	var/list/colors = list()
	var/list/organ_data = read_preference(/datum/preference/organ_data)
	var/robotic_body = dq_species_robotic_body(read_preference(/datum/preference/choiced/species))
	if(robotic_body)
		colors[DQ_LIMB_COLOR_BODY] = value
	for(var/limb in list(BP_TORSO, BP_HEAD, BP_GROIN, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT))
		if(organ_data?[limb] == "cyborg")
			colors[limb] = value
	update_preference_by_type(/datum/preference/limb_colors, colors)
	save_data = get_save_data_for_savefile_identifier(PREFERENCE_CHARACTER)
	if(islist(save_data))
		save_data["limb_colors_set"] = TRUE

/// The two species that drew from skin tone now draw from skin colour. Every other species ignored the tone. The old key
/// stays in the save, unread after this.
/datum/preferences/proc/convert_old_skin_tone(list/save_data)
	var/tone = save_data["skin_tone"]
	var/static/list/tone_species = list(SPECIES_EVENT1, "Virtual Reality Human")
	if(isnum(tone) && (read_preference(/datum/preference/choiced/species) in tone_species))
		update_preference_by_type(/datum/preference/color/human/skin_color, dq_skin_tone_to_color(tone))
		// Primary was seeded from the old skin colour, which these species never showed.
		update_preference_by_type(/datum/preference/color/human/color_slot/primary, dq_skin_tone_to_color(tone))

/// Extra 1 and 2, when no old palette set them: the next most used colours among the fields.
/datum/preferences/proc/seed_spare_slots(list/save_data)
	var/list/old_palette = save_data["color_palette"]
	var/list/taken = list()
	for(var/slot in list("primary", "secondary", "tertiary"))
		taken += lowertext(read_preference(dq_color_slot_type(slot)))
	var/list/counts = list()
	var/list/fields = dq_palette_fields()
	for(var/field in fields)
		var/stored = read_preference_raw(field)
		if(istext(stored) && !dq_color_slot_type(stored) && !(lowertext(stored) in taken))
			counts[lowertext(stored)] += 1
	for(var/datum/preference/color/human/color_slot/slot_type as anything in list(/datum/preference/color/human/color_slot/extra1, /datum/preference/color/human/color_slot/extra2))
		if(islist(old_palette) && length(old_palette) >= initial(slot_type.old_palette_index))
			continue
		var/best
		for(var/hex in counts)
			if(!best || counts[hex] > counts[best])
				best = hex
		if(!best)
			return
		counts -= best
		update_preference_by_type(slot_type, best)

/// Once per character: the ears a Kitsuhana body used to draw by itself when no ear style was set are now that ear style.
/datum/preferences/proc/migrate_robotic_ears()
	var/list/save_data = get_save_data_for_savefile_identifier(PREFERENCE_CHARACTER)
	if(!islist(save_data) || save_data["robotic_ears_migrated"])
		return
	save_data["robotic_ears_migrated"] = TRUE
	if(read_preference(/datum/preference/text/human/ear_style) || read_preference(/datum/preference/text/human/ear_secondary_style))
		return
	var/list/organ_data = read_preference(/datum/preference/organ_data)
	var/list/rlimb_data = read_preference(/datum/preference/rlimb_data)
	for(var/limb in list(BP_TORSO, BP_HEAD))
		if(organ_data?[limb] == "cyborg" && rlimb_data?[limb] == "Kitsuhana")
			update_preference_by_type(/datum/preference/text/human/ear_style, "Kitsuhana cybernetic ears")
			log_world("PREFS: [client_ckey] robotic ears became the Kitsuhana ear style")
			return

/// Skin is always Primary and eyes always Tertiary. A character whose colour differs keeps its look: the slot takes that
/// colour, and whatever was linked to the slot is pinned to the colour it showed, so no custom colour is lost and nothing else shifts.
/datum/preferences/proc/link_skin_and_eyes()
	var/static/list/pairs = list(/datum/preference/color/human/skin_color = "primary", /datum/preference/color/human/eyes_color = "tertiary")
	for(var/field in pairs)
		var/slot = pairs[field]
		if(read_preference_raw(field) == slot)
			continue
		var/shown = lowertext(read_preference(field))
		var/slot_type = dq_color_slot_type(slot)
		var/old_hex = lowertext(read_preference(slot_type))
		begin_update_batch()
		if(shown != old_hex)
			log_world("PREFS: [client_ckey] [slot] moved from [old_hex] to [shown] to keep the [field] colour; links to it pinned")
			pin_slot_links(slot, old_hex)
			update_preference_by_type(slot_type, shown)
		update_preference_by_type(field, slot)
		end_update_batch()

/// Everything linked to a palette slot takes this colour as its own.
/datum/preferences/proc/pin_slot_links(slot, hex)
	var/list/fields = dq_palette_fields()
	for(var/field in fields)
		if(read_preference_raw(field) == slot)
			update_preference_by_type(field, hex)
	var/list/colors = read_preference_raw(/datum/preference/limb_colors)
	for(var/limb in colors)
		if(colors[limb] == slot)
			colors[limb] = hex
	update_preference_by_type(/datum/preference/limb_colors, colors)
	var/list/markings = read_preference_raw(/datum/preference/body_markings)
	for(var/marking in markings)
		var/list/zones = markings[marking]
		if(!islist(zones))
			continue
		for(var/zone in zones)
			var/list/entry = zones[zone]
			if(zone == "color")
				if(entry == slot)
					zones[zone] = hex
			else if(islist(entry) && entry["color"] == slot)
				entry["color"] = hex
	update_preference_by_type(/datum/preference/body_markings, markings)
