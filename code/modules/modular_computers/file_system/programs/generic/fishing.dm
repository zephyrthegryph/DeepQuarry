/datum/computer_file/program/fishing
	filename = "fishingminigame"
	filedesc = "Fishy Fishy 905"
	program_icon_state = "arcade"
	extended_desc = "A little fishing minigame for when you're really bored."
	size = 3
	requires_ntnet = FALSE
	available_on_ntnet = TRUE
	usage_flags = PROGRAM_ALL

CAPABILITIES(/datum/computer_file/program/fishing)
	interface("NtosFishing")
	op("lose", ui_act("lose"), then(PROC_REF(ui_act_lose)))
	op("win", ui_act("win"), then(PROC_REF(ui_act_win)))

/datum/computer_file/program/fishing/ui_data(datum/act/eval/A)
	return get_header_data()

/datum/computer_file/program/fishing/proc/ui_act_lose(datum/act/op/A)
	play_sfx(computer(), SFX_ARCADE_LOSE)
	. = TRUE

/datum/computer_file/program/fishing/proc/ui_act_win(datum/act/op/A)
	play_sfx(computer(), SFX_ARCADE_WIN)
	. = TRUE
