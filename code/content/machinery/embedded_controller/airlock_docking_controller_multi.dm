// A docking port with several independent airlocks. The master console runs the port (/datum/docking_port); its airlocks are the child
// controllers whose `master_tag` names it, a keyed relation linked when the map loads. The port commands them by direct calls, so a child
// never has to wake for a message. `child_tags_txt` / `child_names_txt` only name the children in the master's window.
/obj/machinery/embedded_controller/radio/docking_port_multi
	name = "docking port controller"
	port = /datum/docking_port
	var/child_tags_txt
	var/child_names_txt
	var/list/child_names
	/// The child airlocks: every airlock docking controller whose master_tag is this console's id_tag.
	var/list/obj/machinery/embedded_controller/radio/airlock/docking_port_multi/child_airlocks

CAPABILITIES(/obj/machinery/embedded_controller/radio/docking_port_multi)
	setup(PROC_REF(split_child_names))
	interface("DockingConsoleMulti")
	ui_shape(docking_status = enum(list("undocked", "docking", "undocking", "docked")), airlocks = list_of(row(name = schema_text(), override_enabled = bool())))
	ref_many(nameof(child_airlocks), /obj/machinery/embedded_controller/radio/airlock/docking_port_multi, by = nameof(id_tag), target_key = nameof(/obj/machinery/embedded_controller/radio/airlock/docking_port_multi::master_tag))

/obj/machinery/embedded_controller/radio/docking_port_multi/proc/split_child_names()
	var/list/names = splittext(child_names_txt, ";")
	var/list/tags = splittext(child_tags_txt, ";")
	if (names.len == tags.len)
		for (var/i = 1; i <= tags.len; i++)
			set_child_names_at(tags[i], names[i])

/obj/machinery/embedded_controller/radio/docking_port_multi/port_airlocks()
	return child_airlocks ? child_airlocks.Copy() : list()

/// The window's data.
/obj/machinery/embedded_controller/radio/docking_port_multi/ui_data(datum/act/eval/A)
	var/list/airlocks = list()
	for(var/obj/machinery/embedded_controller/radio/airlock/docking_port_multi/child as anything in port_airlocks())
		airlocks += list(list("name" = LAZYACCESS(child_names, child.id_tag) || child.id_tag, "override_enabled" = child.override_enabled))

	. = list(
		"docking_status" = port.get_docking_status(),
		"airlocks" = airlocks,
	)

// One airlock of a multi-airlock docking port: an ordinary airlock its master's port docks; its own override leaves it to the crew.
/obj/machinery/embedded_controller/radio/airlock/docking_port_multi
	name = "docking port controller"
	var/master_tag	//for mapping
	tag_secure = 1
	valid_actions = list("cycle_ext", "cycle_int", "force_ext", "force_int", "abort", "toggle_override")

CAPABILITIES(/obj/machinery/embedded_controller/radio/airlock/docking_port_multi)
	interface("AirlockConsoleDocking")
	ui_shape(chamber_pressure = num(), exterior_status = row(state = enum(list("open", "closed")), lock = enum(list("locked", "unlocked"))), interior_status = row(state = enum(list("open", "closed")), lock = enum(list("locked", "unlocked"))), processing = bool(), docking_status = enum(list("undocked", "docking", "undocking", "docked")), airlock_disabled = bool(), override_enabled = bool(), docking_codes = nullable(schema_text()), name = nullable(schema_text()))
	op("toggle_override", ui_act("toggle_override"), needs(req(PROC_REF(command_listed), silent = TRUE)), then(PROC_REF(ui_act_program_command)))

/obj/machinery/embedded_controller/radio/airlock/docking_port_multi/run_command(command)
	if(command == "toggle_override")
		set_override_enabled(!override_enabled)
		return TRUE
	return ..()

/// The window's data.
/obj/machinery/embedded_controller/radio/airlock/docking_port_multi/ui_data(datum/act/eval/A)
	. = list(
		"chamber_pressure" = round(chamber_pressure()),
		"exterior_status" = exterior_status(),
		"interior_status" = interior_status(),
		"processing" = cycling(),
		"docking_status" = docked_port ? docked_port.get_docking_status() : "undocked",
		"airlock_disabled" = dock_locked(),
		"override_enabled" = override_enabled,
		"docking_codes" = null,
		"name" = null,
	)
