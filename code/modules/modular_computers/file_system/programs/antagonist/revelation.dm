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
	var/armed = 0

/datum/computer_file/program/revelation/run_program(mob/living/user)
	. = ..(user)
	if(armed)
		activate()

/datum/computer_file/program/revelation/proc/activate()
	var/obj/item/modular_computer/target = computer()
	if(!target)
		return

	target.visible_message(span_notice("\The [target]'s screen brightly flashes and loud electrical buzzing is heard."))
	target.set_enabled(FALSE)
	target.last_power_usage = 0
	target.update_icon()
	fx_sparks(target.loc, 10)

	if(target.hard_drive)
		rel_clear(target, nameof(target.hard_drive))

	if(target.battery_module && prob(25))
		rel_clear(target, nameof(target.battery_module))

	if(target.tesla_link && prob(50))
		rel_clear(target, nameof(target.tesla_link))

CAPABILITIES(/datum/computer_file/program/revelation)
	op("PRG_arm", ui_act(), then(PROC_REF(ui_act_prg_arm)))
	op("PRG_activate", ui_act(), then(PROC_REF(ui_act_prg_activate)))
	interface("NtosRevelation")
	op("PRG_obfuscate", ui_act("PRG_obfuscate", arg("new_name", schema_text(4096))), then(PROC_REF(ui_act_prg_obfuscate)))

/datum/computer_file/program/revelation/proc/ui_act_prg_arm(datum/act/op/A)
	armed = !armed
	return OP_OK

/datum/computer_file/program/revelation/proc/ui_act_prg_activate(datum/act/op/A)
	activate()
	return OP_OK

/datum/computer_file/program/revelation/proc/ui_act_prg_obfuscate(datum/act/op/A, new_name)
	var/newname = new_name
	if(!newname)
		return
	filedesc = newname
	return TRUE

/datum/computer_file/program/revelation/clone()
	var/datum/computer_file/program/revelation/temp = ..()
	temp.armed = armed
	return temp

/datum/computer_file/program/revelation/ui_data(datum/act/eval/A)
	var/list/data = get_header_data()
	data["armed"] = armed

	return data
