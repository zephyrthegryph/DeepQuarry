/datum/computer_file/program/revelation
	filename = "revelation"
	filedesc = "Revelation"
	program_icon_state = "hostile"
	program_key_state = "security_key"
	program_menu_icon = "home"
	extended_desc = "This virus can destroy hard drive of system it is executed on. It may be obfuscated to look like another non-malicious program. Once armed, it will destroy the system upon next execution."
	size = 13
	requires_ntnet = FALSE
	available_on_ntnet = FALSE
	available_on_syndinet = TRUE
	tgui_id = "NtosRevelation"
	var/armed = 0

/datum/computer_file/program/revelation/run_program(mob/living/user)
	. = ..(user)
	if(armed)
		activate()

/datum/computer_file/program/revelation/proc/activate()
	if(!computer())
		return

	computer().visible_message(span_notice("\The [computer()]'s screen brightly flashes and loud electrical buzzing is heard."))
	computer().set_enabled(FALSE)
	computer().last_power_usage = 0
	computer().update_icon()
	fx_sparks(computer().loc, 10)

	if(computer().hard_drive)
		qdel(computer().hard_drive)

	if(computer().battery_module && prob(25))
		qdel(computer().battery_module)

	if(computer().tesla_link && prob(50))
		qdel(computer().tesla_link)

CAPABILITIES(/datum/computer_file/program/revelation)
	op("PRG_arm", ui_act(), then(PROC_REF(native_ui_act_prg_arm)))
	op("PRG_activate", ui_act(), then(PROC_REF(native_ui_act_prg_activate)))

/datum/computer_file/program/revelation/proc/native_ui_act_prg_arm(datum/act/op/A)
	armed = !armed
	return OP_OK

/datum/computer_file/program/revelation/proc/native_ui_act_prg_activate(datum/act/op/A)
	activate()
	return OP_OK

UI_ACT(/datum/computer_file/program/revelation, "PRG_obfuscate", ui_act_prg_obfuscate, UI_ARG_TEXT("new_name"))
UI_ACT_PROC(/datum/computer_file/program/revelation, ui_act_prg_obfuscate)
	var/newname = params["new_name"]
	if(!newname)
		return
	filedesc = newname
	return TRUE

/datum/computer_file/program/revelation/clone()
	var/datum/computer_file/program/revelation/temp = ..()
	temp.armed = armed
	return temp

UI_DATA_REPLACE(/datum/computer_file/program/revelation, "armed:num", "merge:ui_data_datum_computer_file_program_revelation{}")

/// The computed part of /datum/computer_file/program/revelation's window data (declared on its UI_DATA row).
/datum/computer_file/program/revelation/proc/ui_data_datum_computer_file_program_revelation(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = get_header_data()


	return data
