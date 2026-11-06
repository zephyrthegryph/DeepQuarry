// A docking port that is one airlock: the controller is the airlock (its cycle, doors and pump) and also runs the port
// (/datum/docking_port), whose one airlock is itself. While a ship is docked the airlock refuses its own commands unless the port's
// override is on.
/obj/machinery/embedded_controller/radio/airlock/docking_port
	name = "docking port controller"
	port = /datum/docking_port
	var/display_name		// For mappers to override the port's display_name (how it shows up on the docking monitoring program)
	tag_secure = 1
	valid_actions = list("cycle_ext", "cycle_int", "force_ext", "force_int", "abort", "toggle_override")

CAPABILITIES(/obj/machinery/embedded_controller/radio/airlock/docking_port)
	setup(PROC_REF(name_port))
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(multitool_used)))

/obj/machinery/embedded_controller/radio/airlock/docking_port/proc/name_port()
	if(display_name)
		port.display_name = display_name

/obj/machinery/embedded_controller/radio/airlock/docking_port/port_airlocks()
	return list(src)

/obj/machinery/embedded_controller/radio/airlock/docking_port/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	var/code = port.docking_codes
	code = code ? stars(code) : "N/A"
	to_chat(user, "[tool]'s screen displays '[code]'")
	return OP_OK

/// The window's data.
/obj/machinery/embedded_controller/radio/airlock/docking_port/ui_data(datum/act/eval/A)
	. = list(
		"chamber_pressure" = round(chamber_pressure()),
		"exterior_status" = exterior_status(),
		"interior_status" = interior_status(),
		"processing" = cycling(),
		"docking_status" = port.get_docking_status(),
		"airlock_disabled" = !(port.undocked() || port.override_enabled),
		"override_enabled" = port.override_enabled,
		"docking_codes" = port.docking_codes,
		"name" = port.get_name(),
		"internalTemplateName" = "AirlockConsoleDocking",
	)
