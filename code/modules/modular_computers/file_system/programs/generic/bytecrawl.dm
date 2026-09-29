/datum/computer_file/program/bytecrawl
	filename = "bytecrawl"
	filedesc = "BYTECRAWL"
	extended_desc = "A CLI hacking idle terminal. Run crack jobs, sell stolen data, upgrade your rig."
	size = 3
	requires_ntnet = FALSE
	available_on_ntnet = TRUE
	tgui_id = "NtosBytecrawl"
	program_icon_state = "generic"
	usage_flags = PROGRAM_ALL

UI_DATA_REPLACE(/datum/computer_file/program/bytecrawl, "merge:ui_data_datum_computer_file_program_bytecrawl{}")

/// The computed part of /datum/computer_file/program/bytecrawl's window data (declared on its UI_DATA row).
/datum/computer_file/program/bytecrawl/proc/ui_data_datum_computer_file_program_bytecrawl(mob/user, datum/tgui/ui, datum/tgui_state/state)
	. = get_header_data()

