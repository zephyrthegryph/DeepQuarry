//base type for controllers of two-door systems
/obj/machinery/embedded_controller/radio/airlock
	maintenance_flags = MACHINE_MAINT_STANDARD
	// Setup parameters only
	radio_filter = RADIO_AIRLOCK
	program = /datum/embedded_program/airlock
	var/tag_exterior_door
	var/tag_interior_door
	var/tag_airpump
	var/tag_chamber_sensor
	var/tag_exterior_sensor
	var/tag_interior_sensor
	var/tag_airlock_mech_sensor
	var/tag_shuttle_mech_sensor
	var/tag_secure = 0
	var/list/dummy_terminals
	var/cycle_to_external_air = 0
	valid_actions = list("cycle_ext", "cycle_int", "force_ext", "force_int", "abort", "purge", "secure")
	layer = ABOVE_WINDOW_LAYER

	var/deconstructable = FALSE

/obj/machinery/embedded_controller/radio/airlock/tgui_status(mob/user, datum/tgui_state/state)
	. = ..()
	if(!allowed(user))
		return min(STATUS_UPDATE, .)

/// Only a controller built to come apart opens its panel or comes off the wall (the others take the click and do nothing).
/obj/machinery/embedded_controller/radio/airlock/proc/may_deconstruct(datum/act/op/A)
	return (deconstructable) ? null : MSG(req_failed)

/// The window's data.
/obj/machinery/embedded_controller/radio/airlock/ui_data(datum/act/eval/A)
	. = list()
	.["panel_open"] = panel_open
	var/list/part = ui_data_part_airlock(A)
	for(var/key in part)
		.[key] = part[key]

/// The computed part of the window's data.
/obj/machinery/embedded_controller/radio/airlock/proc/ui_data_part_airlock(datum/act/eval/A)
	var/list/data = list()

	data["tags"] = null

	data["frequency"] = null
	data["min_freq"] = null
	data["max_freq"] = null

	if(panel_open)
		var/datum/embedded_program/airlock/airlock_program = program
		data["tags"] = airlock_program.get_all_tags()

		data["frequency"] = frequency
		data["min_freq"] = RADIO_LOW_FREQ
		data["max_freq"] = RADIO_HIGH_FREQ

	return data

// The tag and frequency settings are behind the maintenance panel (the program's commands are not: the old tgui_act() ran them before its panel check).
CAPABILITIES(/obj/machinery/embedded_controller/radio/airlock)
	space(SPACE_PANEL, door = nameof(panel_open))
	op("edit_tag", ui_act("edit_tag", arg("tag", schema_text(4096))), at(SPACE_PANEL),
		asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(edit_tag_question)), "title" = computed(PROC_REF(edit_tag_title)), "default" = computed(PROC_REF(edit_tag_default)), "max_len" = 30, "name_text" = TRUE, "timeout" = 0), step = "tag"),
		then(PROC_REF(ui_act_edit_tag)))
	op("set_frequency", ui_act("set_frequency", arg("freq", num())), at(SPACE_PANEL), then(PROC_REF(ui_act_set_frequency)))
	extend("machine_panel", needs(req(PROC_REF(may_deconstruct), silent = TRUE)))
	extend("machine_panel_close", needs(req(PROC_REF(may_deconstruct), silent = TRUE)))
	extend("machine_deconstruct", needs(req(PROC_REF(may_deconstruct), silent = TRUE)))

/obj/machinery/embedded_controller/radio/airlock/proc/edit_tag_question(datum/act/op/A)
	return "What would you like to set [A.args["tag"]] to?"

/obj/machinery/embedded_controller/radio/airlock/proc/edit_tag_title(datum/act/op/A)
	return "New [A.args["tag"]]?"

/obj/machinery/embedded_controller/radio/airlock/proc/edit_tag_default(datum/act/op/A)
	var/datum/embedded_program/airlock/airlock_program = program
	return airlock_program?.get_tag(A.args["tag"])

/// The answered tag is set on the program.
/obj/machinery/embedded_controller/radio/airlock/proc/ui_act_edit_tag(datum/act/op/A, tag)
	var/new_tag = A.step_value("tag")
	var/datum/embedded_program/airlock/airlock_program = program
	if(new_tag && airlock_program)
		airlock_program.set_tag(tag, new_tag)
	return TRUE

/obj/machinery/embedded_controller/radio/airlock/proc/ui_act_set_frequency(datum/act/op/A, freq)
	set_frequency(sanitize_frequency(freq, RADIO_LOW_FREQ, RADIO_HIGH_FREQ))
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/machinery/embedded_controller/radio/airlock, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/embedded_controller/radio/airlock/appearance_overlays()
	. = list()
	if(panel_open)
		. += "airlock_control_open"

//Advanced airlock controller for when you want a more versatile airlock controller - useful for turning simple access control rooms into airlocks
/obj/machinery/embedded_controller/radio/airlock/advanced_airlock_controller
	name = "Advanced Airlock Controller"
	deconstructable = TRUE
	circuit = /obj/item/circuitboard/airlock_cycling


//Airlock controller for airlock control - most airlocks on the station use this
/obj/machinery/embedded_controller/radio/airlock/airlock_controller
	name = "Airlock Controller"
	tag_secure = 1
	valid_actions = list("cycle_ext", "cycle_int", "force_ext", "force_int", "abort")
	deconstructable = TRUE
	circuit = /obj/item/circuitboard/airlock_cycling


//Access controller for door control - used in virology and the like
/obj/machinery/embedded_controller/radio/airlock/access_controller
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "access_control_standby"

	name = "Access Controller"
	tag_secure = 1
	valid_actions = list("cycle_ext_door", "cycle_int_door", "force_ext", "force_int")
	deconstructable = TRUE
	circuit = /obj/item/circuitboard/airlock_cycling

DECLARE_APPEARANCE_PROC(/obj/machinery/embedded_controller/radio/airlock/access_controller, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/embedded_controller/radio/airlock/access_controller/appearance_overlays()
	. = list()
	if(on && program)
		if(program.memory["processing"])
			icon_state = "access_control_process"
		else
			icon_state = "access_control_standby"
	else
		icon_state = "access_control_off"

