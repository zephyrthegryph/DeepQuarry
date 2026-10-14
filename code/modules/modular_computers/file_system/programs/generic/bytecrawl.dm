/datum/computer_file/program/bytecrawl
	filename = "bytecrawl"
	filedesc = "BYTECRAWL"
	extended_desc = "A CLI hacking idle terminal. Run crack jobs, sell stolen data, upgrade your rig."
	size = 3
	requires_ntnet = FALSE
	available_on_ntnet = TRUE
	program_icon_state = "generic"
	usage_flags = PROGRAM_ALL

CAPABILITIES(/datum/computer_file/program/bytecrawl)
	interface("NtosBytecrawl")
	ui_shape(PC_batteryicon = schema_text(), PC_batterypercent = schema_text(), PC_showbatteryicon = bool())

/datum/computer_file/program/bytecrawl/ui_data(datum/act/eval/A)
	. = get_header_data()
