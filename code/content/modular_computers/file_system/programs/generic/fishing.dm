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
	op("lose", ui_act(), then(PROC_REF(ui_act_lose)))
	op("win", ui_act(), then(PROC_REF(ui_act_win)))
	interface("NtosFishing")
	ui_shape(PC_device_theme = schema_text(), PC_batteryicon = schema_text(), PC_batterypercent = schema_text(), PC_showbatteryicon = bool(), PC_apclinkicon = nullable(schema_text()), PC_ntneticon = nullable(schema_text()), PC_programheaders = list_of(row(icon = schema_text())), PC_stationtime = schema_text(), PC_hasheader = bool(), PC_showexitprogram = bool())

/datum/computer_file/program/fishing/ui_data(datum/act/eval/A)
	return get_header_data()

/datum/computer_file/program/fishing/proc/ui_act_lose(datum/act/op/A)
	play_sfx(computer(), SFX_ARCADE_LOSE)
	return OP_OK

/datum/computer_file/program/fishing/proc/ui_act_win(datum/act/op/A)
	play_sfx(computer(), SFX_ARCADE_WIN)
	return OP_OK
