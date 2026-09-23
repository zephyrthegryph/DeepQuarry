// /data/ files store data in string format.
// They don't contain other logic for now.
/datum/computer_file/data
	filetype = "DAT"

	var/stored_data = "" 			// Stored data in string format.
	var/block_size = 250
	var/do_not_edit = FALSE			// Whether the user will be reminded that the file probably shouldn't be edited.

/datum/computer_file/data/clone()
	var/datum/computer_file/data/temp = ..()
	temp.stored_data = stored_data
	return temp

// Calculates file size from amount of characters in saved string
/datum/computer_file/data/proc/calculate_size()
	size = max(1, round(length(stored_data) / block_size))

/datum/computer_file/data/proc/generate_file_data(mob/user)
	return digitalPencode2html(stored_data)

/datum/computer_file/data/logfile
	filetype = "LOG"

/datum/computer_file/data/text
	filetype = "TXT"

/// Mapping tool - creates a named modular computer file in a computer's storage on late initialize.
/// Use this to do things like automatic records and blackboxes. Alternative for paper records.
/// Values can be in the editor for each map or as a subtype.
/// This is an obj because raw atoms can't be placed in DM or third-party mapping tools.
///obj/effect/computer_file_creator

///obj/effect/computer_file_creator/Initialize(mapload)
//	. = ..()
//	return INITIALIZE_HINT_LATELOAD

///obj/effect/computer_file_creator/LateInitialize()
