#define LOADOUT_BAN_STRING "Custom loadout"

/datum/gear_tweak/proc/get_contents(metadata)
	return

/// A gear tweak's questions as a sequence. The step keyed "value" lands in `value` (and a second answer keyed "detail" in `detail`);
/// keyed "[i]" answers are read with get("[i]"). Callers that need their own state on the answer subtype this with typed vars and hand
/// ask_metadata() an instance (see /datum/ask_sequence/gear_tweak/loadout).
/datum/ask_sequence/gear_tweak
	var/value
	var/detail
	/// The metadata before the change.
	var/metadata
	/// Called as on_changed(user, new_value, sequence) when the answers give a new value.
	var/datum/requester
	var/on_changed

/// The questions a change of this tweak asks: a list of ask_sequence() steps (question_step() specs, see gear_ask_*()), or null when there is
/// nothing to ask. `gear` is the gear datum, when known. ask_metadata() runs them and hands the answers to metadata_answered().
/datum/gear_tweak/proc/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	return null

/// The new metadata from the answers to metadata_steps() (seq.value, seq.detail, seq.get("[i]")), or null to keep it. The old metadata is
/// seq.metadata.
/datum/gear_tweak/proc/metadata_answered(datum/ask_sequence/gear_tweak/seq)
	return seq.value

/// Asks `user` for a new value of this tweak. When they finish, `on_changed` is called on `requester` as (user, new_value, sequence); a
/// cancel changes nothing. `sequence` is an optional /datum/ask_sequence/gear_tweak subtype instance carrying the caller's own typed
/// state. `common_fields` are request fields every question gets (the re-checks: usable_state, ask_flags). Returns FALSE when there is
/// nothing to ask.
/datum/gear_tweak/proc/ask_metadata(mob/user, metadata, datum/gear/gear, title, datum/requester, on_changed, datum/ask_sequence/gear_tweak/sequence, list/common_fields)
	var/list/steps = metadata_steps(user, metadata, gear, title || "Character Preference")
	if(!length(steps))
		return FALSE
	var/datum/ask_sequence/gear_tweak/seq = sequence || new /datum/ask_sequence/gear_tweak
	seq.metadata = metadata
	seq.requester = requester // ALLOW(ownership): a plain reference: the sequence lives only while one of its questions is open
	seq.on_changed = on_changed
	var/result = ask_sequence_begin(src, seq, user, isatom(requester) ? requester : null, steps, PROC_REF(metadata_sequence_done), null, common_fields, null)
	return !istext(result)

/datum/gear_tweak/proc/metadata_sequence_done(datum/ask_sequence/gear_tweak/seq)
	var/new_value = metadata_answered(seq)
	if(isnull(new_value))
		return
	var/datum/requester = seq.requester
	if(!requester || QDELETED(requester))
		return
	call(requester, seq.on_changed)(seq.actor(), new_value, seq)

// Step builders for metadata_steps().

/proc/gear_ask_choice(key, title, message, list/choices, default)
	return question_step(key, /datum/prompt/choice, title = title, question = message, choices = choices, default = default)

/proc/gear_ask_color(key, title, message, default)
	return question_step(key, /datum/prompt/color, title = title, question = message, default = default)

/proc/gear_ask_text(key, title, message, default, max_length = MAX_MESSAGE_LEN, multiline = FALSE)
	return question_step(key, /datum/prompt/text, title = title, question = message, default = default, max_len = max_length, multiline = multiline, name_text = (max_length <= MAX_NAME_LEN))

/proc/gear_ask_colormatrix(key, title, message, preview, list/default, matrix_only = FALSE)
	return question_step(key, /datum/prompt/colormatrix, title = title, question = message, preview = preview, default = default, matrix_only = matrix_only)

/datum/gear_tweak/proc/get_default()
	return

/datum/gear_tweak/proc/tweak_gear_data(metadata, datum/gear_data)
	return

/datum/gear_tweak/proc/tweak_item(obj/item/I, metadata)
	return

// --- Inline-editing virtual dispatch (loadout TGUI) ----------------------
//
// Tweaks that want to expose a React inline widget (dropdown, text, boolean,
// color) override these two procs. The loadout editor calls them
// polymorphically — no istype chain.
//
// get_inline_choices() returns a flat list of valid options for a dropdown,
// or null when the tweak doesn't support inline editing (must use the modal
// tgui_input_X flow via get_metadata).
//
// validate_inline_value(value, user) sanity-checks (and may normalise) a
// value coming back from the React widget. Returns either:
//   - PREF_UPDATE_REJECTED if the value is invalid
//   - the (possibly normalised) value to persist
// Default rejects everything so a subtype must explicitly opt in.

/datum/gear_tweak/proc/get_inline_choices()
	return null

/datum/gear_tweak/proc/validate_inline_value(value, mob/user)
	return PREF_UPDATE_REJECTED

/*
* Color adjustment
*/

/datum/gear_tweak/color
	var/list/valid_colors

/datum/gear_tweak/color/New(list/valid_colors)
	src.valid_colors = valid_colors
	..()

/datum/gear_tweak/color/get_contents(metadata)
	return "Color: <font color='[metadata]'>&#11044;</font>"

/datum/gear_tweak/color/get_default()
	return valid_colors ? valid_colors[1] : COLOR_GRAY

/datum/gear_tweak/color/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	if(valid_colors)
		return list(gear_ask_choice("value", title, "Choose a color.", valid_colors, metadata))
	return list(gear_ask_color("value", title, "Choose a color.", metadata))

/datum/gear_tweak/color/tweak_item(obj/item/I, metadata)
	if(valid_colors && !(metadata in valid_colors))
		return
	if(!metadata || (metadata == "#ffffff"))
		return
	if(istype(I))
		I.add_atom_colour(metadata, FIXED_COLOUR_PRIORITY)
	else
		I.color = metadata

GLOBAL_DATUM_INIT(gear_tweak_free_matrix_recolor, /datum/gear_tweak/matrix_recolor, new)

/datum/gear_tweak/matrix_recolor

/datum/gear_tweak/matrix_recolor/get_contents(metadata)
	if(islist(metadata) && length(metadata))
		return "Matrix Recolor: [english_list(metadata)]"
	return "Matrix Recolor"

/datum/gear_tweak/matrix_recolor/get_default()
	return null

/datum/gear_tweak/matrix_recolor/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	if(!istype(gear))
		CRASH("Matrix metadata called by [user] without gear!")
	return list(gear_ask_colormatrix("value", "Matrix Recolor", "Pick a color matrix for this item", gear.path, metadata, TRUE))

/datum/gear_tweak/matrix_recolor/metadata_answered(datum/ask_sequence/gear_tweak/seq)
	var/list/returned = seq.value
	if(!islist(returned))
		return null
	var/identity = TRUE
	var/static/list/ones = list(1, 5, 9)
	var/static/list/offsets = list(10, 11, 12)
	for(var/i in 1 to length(returned))
		if(returned[i] != ((i in ones) ? 1 : 0))
			identity = FALSE
			break
		if(returned[i] != ((i in offsets) ? 0 : 1))
			identity = FALSE
			break
	return identity ? list() : returned

/datum/gear_tweak/matrix_recolor/tweak_item(obj/item/I, metadata)
	. = ..()
	if(!islist(metadata) || (length(metadata) < 12))
		return
	if(istype(I))
		I.add_atom_colour(metadata, FIXED_COLOUR_PRIORITY)
	else
		I.color = metadata

/*
* Path adjustment
*/

/datum/gear_tweak/path
	var/list/valid_paths

/datum/gear_tweak/path/New(list/valid_paths)
	src.valid_paths = valid_paths
	..()

/datum/gear_tweak/path/get_contents(metadata)
	return "Type: [metadata]"

/datum/gear_tweak/path/get_default()
	return valid_paths[1]

/datum/gear_tweak/path/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	return list(gear_ask_choice("value", title, "Choose a type.", valid_paths, metadata))

/datum/gear_tweak/path/tweak_gear_data(metadata, datum/gear_data/gear_data)
	if(!(metadata in valid_paths))
		return
	gear_data.path = valid_paths[metadata]

/*
* Content adjustment
*/

/datum/gear_tweak/contents
	var/list/valid_contents

/datum/gear_tweak/contents/New()
	valid_contents = args.Copy()
	..()

/datum/gear_tweak/contents/get_contents(metadata)
	return "Contents: [english_list(metadata, and_text = ", ")]"

/datum/gear_tweak/contents/get_default()
	. = list()
	for(var/i = 1 to valid_contents.len)
		. += "Random"

/datum/gear_tweak/contents/metadata_steps(mob/user, list/metadata, datum/gear/gear, title = "Character Preference")
	. = list()
	for(var/i = 1 to valid_contents.len)
		. += list(gear_ask_choice("[i]", title, "Choose an entry.", valid_contents[i] + list("Random", "None"), LAZYACCESS(metadata, i)))

/datum/gear_tweak/contents/metadata_answered(datum/ask_sequence/gear_tweak/seq)
	. = list()
	for(var/i = 1 to valid_contents.len)
		var/entry = seq.get("[i]")
		if(!entry)
			return null
		. += entry

/datum/gear_tweak/contents/tweak_item(obj/item/I, list/metadata)
	if(metadata.len != valid_contents.len)
		return
	for(var/i = 1 to valid_contents.len)
		var/path
		var/list/contents = valid_contents[i]
		if(metadata[i] == "Random")
			path = pick(contents)
			path = contents[path]
		else if(metadata[i] == "None")
			continue
		else
			path = 	contents[metadata[i]]
		if(!path)
			var/mob/user = ismob(I.loc) ? I.loc : I.loc?.loc
			if(istype(user))
				to_chat(user, span_warning("The content \"[metadata[i]]\" from \"[I]\" does no longer exist and has not been loaded. Please replace it in the character setup."))
			continue
		new path(I)

/*
* Ragent adjustment
*/

/datum/gear_tweak/reagents
	var/list/valid_reagents

/datum/gear_tweak/reagents/New(list/reagents)
	valid_reagents = reagents.Copy()
	..()

/datum/gear_tweak/reagents/get_contents(metadata)
	return "Reagents: [metadata]"

/datum/gear_tweak/reagents/get_default()
	return "Random"

/datum/gear_tweak/reagents/metadata_steps(mob/user, list/metadata, datum/gear/gear, title = "Character Preference")
	return list(gear_ask_choice("value", title, "Choose an entry.", valid_reagents + list("Random", "None"), metadata))

/datum/gear_tweak/reagents/tweak_item(obj/item/I, list/metadata)
	if(metadata == "None")
		return
	if(metadata == "Random")
		. = valid_reagents[pick(valid_reagents)]
	else
		. = valid_reagents[metadata]
	I.reagents.add_reagent(., I.reagents.get_free_space())

//Custom name and desciption code
//note to devs downstream: where 'gear_tweaks = list(GLOB.gear_tweak_free_color_choice)' was used before for color selection
//in the loadout, now an owned color tweak must be added to gear_tweaks (see _gear.dm), otherwise the item will not
// be able to be given a custom name or description
/*
Custom Name
*/

GLOBAL_DATUM_INIT(gear_tweak_free_name, /datum/gear_tweak/custom_name, new)

/datum/gear_tweak/custom_name
	var/list/valid_custom_names

/datum/gear_tweak/custom_name/New(list/valid_custom_names)
	src.valid_custom_names = valid_custom_names
	..()

/datum/gear_tweak/custom_name/get_contents(metadata)
	return "Name: [metadata]"

/datum/gear_tweak/custom_name/get_default()
	return ""

/datum/gear_tweak/custom_name/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	if(jobban_isbanned(user, LOADOUT_BAN_STRING))
		to_chat(user, span_warning("You are banned from using custom loadout names/descriptions."))
		return null
	if(valid_custom_names)
		return list(gear_ask_choice("value", title, "Choose an item name.", valid_custom_names, metadata))
	return list(gear_ask_text("value", "Item Name", "Choose the item's name. Leave it blank to use the default name.", metadata, MAX_LNAME_LEN, FALSE))

/datum/gear_tweak/custom_name/metadata_answered(datum/ask_sequence/gear_tweak/seq)
	var/answer = seq.value
	if(isnull(answer))
		return null
	return answer ? answer : get_default()

/datum/gear_tweak/custom_name/tweak_item(obj/item/I, metadata)
	if(!metadata)
		return I.name
	I.name = metadata

/*
Custom Description
*/
GLOBAL_DATUM_INIT(gear_tweak_free_desc, /datum/gear_tweak/custom_desc, new)

/datum/gear_tweak/custom_desc
	var/list/valid_custom_desc

/datum/gear_tweak/custom_desc/New(list/valid_custom_desc)
	src.valid_custom_desc = valid_custom_desc
	..()

/datum/gear_tweak/custom_desc/get_contents(metadata)
	return "Description: [metadata]"

/datum/gear_tweak/custom_desc/get_default()
	return ""

/datum/gear_tweak/custom_desc/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	if(jobban_isbanned(user, LOADOUT_BAN_STRING))
		to_chat(user, span_warning("You are banned from using custom loadout names/descriptions."))
		return null
	if(valid_custom_desc)
		return list(gear_ask_choice("value", title, "Choose an item description.", valid_custom_desc, metadata))
	return list(gear_ask_text("value", "Item Description", "Choose the item's description. Leave it blank to use the default description.", metadata, MAX_MESSAGE_LEN, TRUE))

/datum/gear_tweak/custom_desc/metadata_answered(datum/ask_sequence/gear_tweak/seq)
	var/answer = seq.value
	if(isnull(answer))
		return null
	return answer ? answer : get_default()

/datum/gear_tweak/custom_desc/tweak_item(obj/item/I, metadata)
	if(!metadata)
		return I.desc
	I.desc = metadata

/*
Toggle Digestable
*/

GLOBAL_DATUM_INIT(gear_tweak_free_digestable, /datum/gear_tweak/toggle_digestable, new)

/datum/gear_tweak/toggle_digestable

/datum/gear_tweak/toggle_digestable/get_contents(metadata)
	return "Digestable: [metadata ? "Yes" : "No"]"

/datum/gear_tweak/toggle_digestable/get_default()
	return TRUE

/datum/gear_tweak/toggle_digestable/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	return list(question_step("value", /datum/prompt/choice, title = "Toggle Digestable", question = "Turn digestable on or off", choices = list("Enable", "Disable", "Cancel"), buttons = TRUE))

/datum/gear_tweak/toggle_digestable/metadata_answered(datum/ask_sequence/gear_tweak/seq)
	switch(seq.value)
		if("Enable")
			return TRUE
		if("Disable")
			return FALSE
	return null

/datum/gear_tweak/toggle_digestable/tweak_item(obj/item/I, metadata)
	if(isnull(metadata))
		return I.digestable
	I.digestable = metadata

//end of custom description

/datum/gear_tweak/tablet
	var/static/list/ValidProcessors = list(/obj/item/computer_hardware/processor_unit/small)
	var/static/list/ValidBatteries = list(/obj/item/computer_hardware/battery_module/nano, /obj/item/computer_hardware/battery_module/micro, /obj/item/computer_hardware/battery_module)
	var/static/list/ValidHardDrives = list(/obj/item/computer_hardware/hard_drive/micro, /obj/item/computer_hardware/hard_drive/small, /obj/item/computer_hardware/hard_drive)
	var/static/list/ValidNetworkCards = list(/obj/item/computer_hardware/network_card, /obj/item/computer_hardware/network_card/advanced)
	var/static/list/ValidNanoPrinters = list(null, /obj/item/computer_hardware/nano_printer)
	var/static/list/ValidCardSlots = list(null, /obj/item/computer_hardware/card_slot)
	var/static/list/ValidTeslaLinks = list(null, /obj/item/computer_hardware/tesla_link)

/datum/gear_tweak/tablet/get_contents(list/metadata)
	var/list/names = list()
	var/obj/O = ValidProcessors[metadata[1]]
	if(O)
		names += initial(O.name)
	O = ValidBatteries[metadata[2]]
	if(O)
		names += initial(O.name)
	O = ValidHardDrives[metadata[3]]
	if(O)
		names += initial(O.name)
	O = ValidNetworkCards[metadata[4]]
	if(O)
		names += initial(O.name)
	O = ValidNanoPrinters[metadata[5]]
	if(O)
		names += initial(O.name)
	O = ValidCardSlots[metadata[6]]
	if(O)
		names += initial(O.name)
	O = ValidTeslaLinks[metadata[7]]
	if(O)
		names += initial(O.name)
	return "[english_list(names, and_text = ", ")]"

/datum/gear_tweak/tablet/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	return computer_hardware_steps("Tablet Gear", list(ValidProcessors, ValidBatteries, ValidHardDrives, ValidNetworkCards, ValidNanoPrinters, ValidCardSlots, ValidTeslaLinks))

/datum/gear_tweak/tablet/metadata_answered(datum/ask_sequence/gear_tweak/seq)
	return computer_hardware_answered(seq, list(ValidProcessors, ValidBatteries, ValidHardDrives, ValidNetworkCards, ValidNanoPrinters, ValidCardSlots, ValidTeslaLinks))

/datum/gear_tweak/tablet/get_default()
	// ALLOW(sys_const_list_alloc): default metadata stored into a player\'s loadout preferences, where it is saved and edited per character; each caller needs its own list
	return list(1, 1, 1, 1, 1, 1, 1)

/datum/gear_tweak/tablet/tweak_item(obj/item/modular_computer/tablet/I, list/metadata)
	if(ValidProcessors[metadata[1]])
		var/t = ValidProcessors[metadata[1]]
		rel_set(I, nameof(I.processor_unit), new t(I))
	if(ValidBatteries[metadata[2]])
		var/t = ValidBatteries[metadata[2]]
		rel_set(I, nameof(I.battery_module), new t(I))
		I.battery_module.charge_to_full()
	if(ValidHardDrives[metadata[3]])
		var/t = ValidHardDrives[metadata[3]]
		rel_set(I, nameof(I.hard_drive), new t(I))
	if(ValidNetworkCards[metadata[4]])
		var/t = ValidNetworkCards[metadata[4]]
		rel_set(I, nameof(I.network_card), new t(I))
	if(ValidNanoPrinters[metadata[5]])
		var/t = ValidNanoPrinters[metadata[5]]
		rel_set(I, nameof(I.nano_printer), new t(I))
	if(ValidCardSlots[metadata[6]])
		var/t = ValidCardSlots[metadata[6]]
		rel_set(I, nameof(I.card_slot), new t(I))
	if(ValidTeslaLinks[metadata[7]])
		var/t = ValidTeslaLinks[metadata[7]]
		rel_set(I, nameof(I.tesla_link), new t(I))

/datum/gear_tweak/laptop
	var/static/list/ValidProcessors = list(/obj/item/computer_hardware/processor_unit/small, /obj/item/computer_hardware/processor_unit)
	var/static/list/ValidBatteries = list(/obj/item/computer_hardware/battery_module, /obj/item/computer_hardware/battery_module/advanced, /obj/item/computer_hardware/battery_module/super)
	var/static/list/ValidHardDrives = list(/obj/item/computer_hardware/hard_drive, /obj/item/computer_hardware/hard_drive/advanced, /obj/item/computer_hardware/hard_drive/super)
	var/static/list/ValidNetworkCards = list(/obj/item/computer_hardware/network_card, /obj/item/computer_hardware/network_card/advanced)
	var/static/list/ValidNanoPrinters = list(null, /obj/item/computer_hardware/nano_printer)
	var/static/list/ValidCardSlots = list(null, /obj/item/computer_hardware/card_slot)
	var/static/list/ValidTeslaLinks = list(null, /obj/item/computer_hardware/tesla_link)

/datum/gear_tweak/laptop/get_contents(list/metadata)
	var/list/names = list()
	var/obj/O = ValidProcessors[metadata[1]]
	if(O)
		names += initial(O.name)
	O = ValidBatteries[metadata[2]]
	if(O)
		names += initial(O.name)
	O = ValidHardDrives[metadata[3]]
	if(O)
		names += initial(O.name)
	O = ValidNetworkCards[metadata[4]]
	if(O)
		names += initial(O.name)
	O = ValidNanoPrinters[metadata[5]]
	if(O)
		names += initial(O.name)
	O = ValidCardSlots[metadata[6]]
	if(O)
		names += initial(O.name)
	O = ValidTeslaLinks[metadata[7]]
	if(O)
		names += initial(O.name)
	return "[english_list(names, and_text = ", ")]"

/datum/gear_tweak/laptop/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	return computer_hardware_steps("Laptop Gear", list(ValidProcessors, ValidBatteries, ValidHardDrives, ValidNetworkCards, ValidNanoPrinters, ValidCardSlots, ValidTeslaLinks))

/datum/gear_tweak/laptop/metadata_answered(datum/ask_sequence/gear_tweak/seq)
	return computer_hardware_answered(seq, list(ValidProcessors, ValidBatteries, ValidHardDrives, ValidNetworkCards, ValidNanoPrinters, ValidCardSlots, ValidTeslaLinks))

/// A modular computer's parts are picked one slot at a time; the metadata is each pick's index.
/proc/computer_hardware_part_names(list/parts)
	. = list()
	var/counter = 1
	for(var/i in parts)
		if(i)
			var/obj/O = i
			.[initial(O.name)] = counter++
		else
			.["None"] = counter++

/proc/computer_hardware_steps(title, list/slots)
	var/static/list/questions = list("Choose a processor:", "Choose a battery:", "Choose a hard drive:", "Choose a network card:", "Choose a nanoprinter:", "Choose a card slot:", "Choose a tesla link:")
	. = list()
	for(var/i in 1 to length(slots))
		. += list(gear_ask_choice("[i]", title, questions[i], computer_hardware_part_names(slots[i]), null))

/proc/computer_hardware_answered(datum/ask_sequence/seq, list/slots)
	. = list()
	for(var/i in 1 to length(slots))
		var/list/names = computer_hardware_part_names(slots[i])
		. += names[seq.get("[i]")]

/datum/gear_tweak/laptop/get_default()
	// ALLOW(sys_const_list_alloc): default metadata stored into a player\'s loadout preferences, where it is saved and edited per character; each caller needs its own list
	return list(1, 1, 1, 1, 1, 1, 1)

/datum/gear_tweak/laptop/tweak_item(obj/item/modular_computer/laptop/preset/I, list/metadata)
	if(ValidProcessors[metadata[1]])
		var/t = ValidProcessors[metadata[1]]
		rel_set(I, nameof(I.processor_unit), new t(I))
	if(ValidBatteries[metadata[2]])
		var/t = ValidBatteries[metadata[2]]
		rel_set(I, nameof(I.battery_module), new t(I))
		I.battery_module.charge_to_full()
	if(ValidHardDrives[metadata[3]])
		var/t = ValidHardDrives[metadata[3]]
		rel_set(I, nameof(I.hard_drive), new t(I))
	if(ValidNetworkCards[metadata[4]])
		var/t = ValidNetworkCards[metadata[4]]
		rel_set(I, nameof(I.network_card), new t(I))
	if(ValidNanoPrinters[metadata[5]])
		var/t = ValidNanoPrinters[metadata[5]]
		rel_set(I, nameof(I.nano_printer), new t(I))
	if(ValidCardSlots[metadata[6]])
		var/t = ValidCardSlots[metadata[6]]
		rel_set(I, nameof(I.card_slot), new t(I))
	if(ValidTeslaLinks[metadata[7]])
		var/t = ValidTeslaLinks[metadata[7]]
		rel_set(I, nameof(I.tesla_link), new t(I))

/datum/gear_tweak/implant_location
	var/static/list/bodypart_names_to_tokens = list(
		"head" =       BP_HEAD,
		"upper body" = BP_TORSO,
		"lower body" = BP_GROIN,
		"left hand" =  BP_L_HAND,
		"left arm" =   BP_L_ARM,
		"right hand" = BP_R_HAND,
		"right arm" =  BP_R_ARM,
		"left foot" =  BP_L_FOOT,
		"left leg" =   BP_L_LEG,
		"right foot" = BP_R_FOOT,
		"right leg" =  BP_R_LEG
	)
	var/static/list/bodypart_tokens_to_names = list(
		BP_HEAD =       "head",
		BP_TORSO =      "upper body",
		BP_GROIN =      "lower body",
		BP_LEFT_HAND =  "left hand",
		BP_LEFT_ARM =   "left arm",
		BP_RIGHT_HAND = "right hand",
		BP_RIGHT_ARM =  "right arm",
		BP_LEFT_FOOT =  "left foot",
		BP_LEFT_LEG =   "left leg",
		BP_RIGHT_FOOT = "right foot",
		BP_RIGHT_LEG =  "right leg"
	)

// getter so the loadout editor can access this without tripping
// DreamChecker's spurious unused_var on the cast var (static-var reads
// don't count as "uses" of the instance).
/datum/gear_tweak/implant_location/proc/get_bodypart_names_to_tokens()
	return bodypart_names_to_tokens

/datum/gear_tweak/implant_location/get_default()
	return bodypart_names_to_tokens[1]

/datum/gear_tweak/implant_location/tweak_item(obj/item/implant/I, metadata)
	if(istype(I))
		I.initialize_loc = bodypart_names_to_tokens[metadata] || BP_TORSO

/datum/gear_tweak/implant_location/get_contents(metadata)
	return "Location: [metadata]"

/datum/gear_tweak/implant_location/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	return list(gear_ask_choice("value", "Implant Location", "Select a bodypart for the implant to be implanted inside.", bodypart_names_to_tokens, null))

/datum/gear_tweak/collar_tag/get_contents(metadata)
	return "Tag: [metadata]"

/datum/gear_tweak/collar_tag/get_default()
	return ""

/datum/gear_tweak/collar_tag/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	return list(gear_ask_text("value", title, "Choose the tag text.", metadata, MAX_NAME_LEN, FALSE))

/datum/gear_tweak/collar_tag/tweak_item(obj/item/clothing/accessory/collar/C, metadata)
	if(metadata == "")
		return ..()
	else
		C.initialize_tag(metadata)

// --- Inline-editing overrides ---------------------------------------------
//
// Each tweak that supports inline editing in the loadout TGUI panel
// overrides get_inline_choices (for dropdowns) and/or validate_inline_value
// (for any value coming back from a React widget). See base proc comments
// on /datum/gear_tweak.

/datum/gear_tweak/path/get_inline_choices()
	return valid_paths ? assoc_to_keys(valid_paths) : list()

/datum/gear_tweak/path/validate_inline_value(value, mob/user)
	if(!(value in valid_paths))
		return PREF_UPDATE_REJECTED
	return value

/datum/gear_tweak/reagents/get_inline_choices()
	return (valid_reagents ? assoc_to_keys(valid_reagents) : list()) + list("Random", "None")

/datum/gear_tweak/reagents/validate_inline_value(value, mob/user)
	if(value != "Random" && value != "None" && !(value in valid_reagents))
		return PREF_UPDATE_REJECTED
	return value

/datum/gear_tweak/implant_location/get_inline_choices()
	return assoc_to_keys(bodypart_names_to_tokens)

/datum/gear_tweak/implant_location/validate_inline_value(value, mob/user)
	if(!(value in bodypart_names_to_tokens))
		return PREF_UPDATE_REJECTED
	return value

/datum/gear_tweak/toggle_digestable/validate_inline_value(value, mob/user)
	return value ? TRUE : FALSE

/datum/gear_tweak/color/validate_inline_value(value, mob/user)
	// Hex sanity check — "#rrggbb" (7), "#rgb" (4), "#rrggbbaa" (9).
	if(!istext(value) || length(value) < 4 || length(value) > 9 || copytext(value, 1, 2) != "#")
		return PREF_UPDATE_REJECTED
	return value

/datum/gear_tweak/custom_name/validate_inline_value(value, mob/user)
	return validate_loadout_text(value, user)

/datum/gear_tweak/custom_desc/validate_inline_value(value, mob/user)
	return validate_loadout_text(value, user)

/datum/gear_tweak/collar_tag/validate_inline_value(value, mob/user)
	return validate_loadout_text(value, user)

/// Shared text validator for custom_name / custom_desc / collar_tag.
/// Empty submissions reset to default; jobban-restricted; HTML-stripped;
/// multibyte-safe length-capped at MAX_MESSAGE_LEN.
/proc/validate_loadout_text(value, mob/user)
	if(!istext(value))
		value = ""
	if(jobban_isbanned(user, LOADOUT_BAN_STRING))
		return PREF_UPDATE_REJECTED
	value = strip_html_simple(value)
	if(length_char(value) > MAX_MESSAGE_LEN)
		value = copytext_char(value, 1, MAX_MESSAGE_LEN + 1)
	return value

#undef LOADOUT_BAN_STRING
