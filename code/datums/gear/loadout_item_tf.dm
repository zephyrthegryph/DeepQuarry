// file modified by multiple recent fork commits:
//   - fd3e36a673 (DeepQuarry preferences + loadout rewrite): Bay preference_setup framework deleted; /datum/gear loadout catalog relocated from code/modules/client/preference_setup/loadout/ to code/datums/gear/.
//   - cc0126f33e (polymorphic gear_tweak inline dispatch): /datum/gear_tweak gained get_inline_choices() + validate_inline_value() virtual procs; subtypes override them instead of the loadout editor doing istype chains.
// Per-line archaeology lives in those commits; this header marker
// is here so an upstream merge knows to investigate.

GLOBAL_DATUM_INIT(gear_tweak_item_tf_spawn, /datum/gear_tweak/item_tf_spawn, new())

/datum/gear_tweak/item_tf_spawn

/datum/gear_tweak/item_tf_spawn/get_contents(metadata)
	if(!islist(metadata) || metadata["state"] == "Not Enabled")
		return "Item TF spawnpoint: Not Enabled"
	else if(metadata["state"] == "Anyone")
		return "Item TF spawnpoint: Enabled"
	else
		return "Item TF spawnpoint: Only ckeys [english_list(metadata["valid"], and_text = ", ")]"

/datum/gear_tweak/item_tf_spawn/get_default()
	. = list()
	.["state"] = "Not Enabled"
	.["valid"] = list()

/datum/gear_tweak/item_tf_spawn/metadata_steps(mob/user, list/metadata, datum/gear/gear, title = "Character Preference")
	metadata = islist(metadata) ? metadata : get_default()
	return list(
		gear_ask_choice("value", title, "Choose an entry.", list("Not Enabled", "Anyone", "Only Specific Players"), metadata["state"]),
		TYPE_PROC_REF(/datum/gear_tweak/item_tf_spawn, ask_valid_ckeys),
	)

/// Step proc (run with the tweak as the sequence owner): only specific players need a ckey list.
/datum/gear_tweak/item_tf_spawn/proc/ask_valid_ckeys(datum/ask_sequence/gear_tweak/seq)
	if(seq.value != "Only Specific Players")
		return null
	var/list/current = seq.metadata
	return gear_ask_text("detail", "Allowed Players", "Input ckeys allowed to join on separate lines", islist(current) ? jointext(current["valid"], "\n") : "", MAX_MESSAGE_LEN, TRUE)

/datum/gear_tweak/item_tf_spawn/metadata_answered(datum/ask_sequence/gear_tweak/seq)
	var/entry = seq.value
	if(!entry)
		return null
	var/list/metadata = islist(seq.metadata) ? seq.metadata : get_default()
	. = get_default()
	.["state"] = entry
	if(entry == "Only Specific Players")
		.["valid"] = splittext(lowertext(seq.detail), "\n")
	else
		.["valid"] = metadata["valid"]

/datum/gear_tweak/item_tf_spawn/tweak_item(obj/item/I, metadata)
	if(!islist(metadata))
		return
	if(metadata["state"] == "Not Enabled")
		return
	else if(metadata["state"] == "Anyone")
		I.item_tf_spawnpoint_set()
	else if(metadata["state"] == "Only Specific Players")
		I.item_tf_spawnpoint_set()
		I.ckeys_allowed_itemspawn = metadata["valid"]

// React inline-edit accepts a boolean: TRUE -> "Anyone" with empty valid list,
// FALSE -> "Not Enabled". The per-ckey gating (Only Specific Players) needs the
// modal flow via get_metadata.
/datum/gear_tweak/item_tf_spawn/validate_inline_value(value, mob/user)
	return value \
		? list("state" = "Anyone",      "valid" = list()) \
		: list("state" = "Not Enabled", "valid" = list())

/datum/gear_tweak/simplemob_picker
	var/list/simplemob_list

/datum/gear_tweak/simplemob_picker/New(list/valid_simplemobs)
	src.simplemob_list = valid_simplemobs
	..()

/datum/gear_tweak/simplemob_picker/get_contents(metadata)
	return "Type: [metadata]"

/datum/gear_tweak/simplemob_picker/get_default()
	return simplemob_list[1]

/datum/gear_tweak/simplemob_picker/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	return list(gear_ask_choice("value", title, "Choose a type.", simplemob_list, metadata))

/datum/gear_tweak/simplemob_picker/tweak_item(obj/item/capture_crystal/I, metadata)
	if(!(metadata in simplemob_list))
		return
	if(!istype(I))
		return
	I.set_spawn_mob_type(simplemob_list[metadata])
	I.spawn_mob_name = metadata
