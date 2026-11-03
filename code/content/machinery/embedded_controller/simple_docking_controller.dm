// A docking port with a single hatch door: its port (/datum/docking_port) opens and bolts the hatch when docked, and closes and bolts it
// to undock. The hatch is the door the map tags `tag_door` ("<id_tag>_hatch" by default), a keyed relation linked when the map loads.
/obj/machinery/embedded_controller/radio/simple_docking_controller
	name = "docking hatch controller"
	port = /datum/docking_port
	var/tag_door
	/// The hatch door(s) carrying `tag_door`.
	var/list/obj/machinery/door/airlock/hatches
	valid_actions = list("force_door", "toggle_override")

CAPABILITIES(/obj/machinery/embedded_controller/radio/simple_docking_controller)
	setup(PROC_REF(default_hatch_tag))
	ref_many(nameof(hatches), /obj/machinery/door/airlock, by = nameof(tag_door), target_key = nameof(/obj/machinery/door/airlock::id_tag))

/// The map's hatch tag, or the default one, before the keyed relation links.
/obj/machinery/embedded_controller/radio/simple_docking_controller/proc/default_hatch_tag()
	if(!tag_door)
		tag_door = "[id_tag]_hatch"

/obj/machinery/embedded_controller/radio/simple_docking_controller/port_hatches()
	return hatches ? hatches.Copy() : list()

/// The window's data.
/obj/machinery/embedded_controller/radio/simple_docking_controller/ui_data(datum/act/eval/A)
	. = list(
		"docking_status" = port.get_docking_status(),
		"override_enabled" = port.override_enabled,
		"exterior_status" = port.hatch_status(),
		"internalTemplateName" = "DockingConsoleSimple",
	)
