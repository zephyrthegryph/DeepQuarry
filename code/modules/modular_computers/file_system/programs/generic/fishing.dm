/datum/computer_file/program/fishing
	filename = "fishingminigame"
	filedesc = "Fishy Fishy 905"
	program_icon_state = "arcade"
	extended_desc = "A little fishing minigame for when you're really bored."
	size = 3
	requires_ntnet = FALSE
	available_on_ntnet = TRUE
	tgui_id = "NtosFishing"
	usage_flags = PROGRAM_ALL

CAPABILITIES(/datum/computer_file/program/fishing)
	op("lose", ui_act(), then(PROC_REF(native_ui_act_lose)))
	op("win", ui_act(), then(PROC_REF(native_ui_act_win)))

UI_DATA_REPLACE(/datum/computer_file/program/fishing, "merge:ui_data_datum_computer_file_program_fishing{}")

/// The computed part of /datum/computer_file/program/fishing's window data (declared on its UI_DATA row).
/datum/computer_file/program/fishing/proc/ui_data_datum_computer_file_program_fishing(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return get_header_data()

/datum/computer_file/program/fishing/proc/native_ui_act_lose(datum/act/op/A)
	play_sfx(computer(), SFX_ARCADE_LOSE)
	return OP_OK

/datum/computer_file/program/fishing/proc/native_ui_act_win(datum/act/op/A)
	play_sfx(computer(), SFX_ARCADE_WIN)
	return OP_OK
