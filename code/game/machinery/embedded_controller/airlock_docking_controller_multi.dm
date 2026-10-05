//a controller for a docking port with multiple independent airlocks
//this is the master controller, that things will try to dock with.
/obj/machinery/embedded_controller/radio/docking_port_multi
	name = "docking port controller"
	program = /datum/embedded_program/docking/multi
	var/child_tags_txt
	var/child_names_txt
	var/list/child_names

/obj/machinery/embedded_controller/radio/docking_port_multi/Initialize(mapload)
	. = ..()
	var/list/names = splittext(child_names_txt, ";")
	var/list/tags = splittext(child_tags_txt, ";")
	if (names.len == tags.len)
		for (var/i = 1; i <= tags.len; i++)
			LAZYSET(child_names, tags[i], names[i])

/// The window's data.
/obj/machinery/embedded_controller/radio/docking_port_multi/ui_data(datum/act/eval/A)
	var/datum/embedded_program/docking/multi/docking_program = program // Cast to proper type

	var/list/airlocks[length(child_names)]
	var/i = 1
	for (var/child_tag in child_names)
		airlocks[i++] = list("name"=LAZYACCESS(child_names, child_tag), "override_enabled"=(docking_program.children_override[child_tag] == "enabled"))

	. = list(
		"docking_status" = docking_program.get_docking_status(),
		"airlocks" = airlocks,
		"internalTemplateName" = "DockingConsoleMulti",
	)

//a docking port based on an airlock
// This is the actual controller that will be commanded by the master defined above
/obj/machinery/embedded_controller/radio/airlock/docking_port_multi
	name = "docking port controller"
	program = /datum/embedded_program/airlock/multi_docking
	var/master_tag	//for mapping
	tag_secure = 1
	valid_actions = list("cycle_ext", "cycle_int", "force_ext", "force_int", "abort", "toggle_override")


/// The window's data.
/obj/machinery/embedded_controller/radio/airlock/docking_port_multi/ui_data(datum/act/eval/A)
	var/datum/embedded_program/airlock/multi_docking/airlock_program = program // Cast to proper type

	. = list(
		"chamber_pressure" = round(airlock_program.memory["chamber_sensor_pressure"]),
		"exterior_status" = airlock_program.memory["exterior_status"],
		"interior_status" = airlock_program.memory["interior_status"],
		"processing" = airlock_program.memory["processing"],
		"docking_status" = airlock_program.master_status,
		"airlock_disabled" = (airlock_program.docking_enabled && !airlock_program.override_enabled),
		"override_enabled" = airlock_program.override_enabled,
		"internalTemplateName" = "AirlockConsoleDocking",
	)

