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

/obj/machinery/embedded_controller/radio/airlock/screwdriver_act(mob/user, obj/item/tool)
	return deconstructable ? ..() : ITEM_INTERACT_BLOCKING

/obj/machinery/embedded_controller/radio/airlock/crowbar_act(mob/user, obj/item/tool)
	return deconstructable ? ..() : ITEM_INTERACT_BLOCKING

/obj/machinery/embedded_controller/radio/airlock/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["panel_open"] = panel_open
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

/obj/machinery/embedded_controller/radio/airlock/tgui_act(action, params)
	. = ..()
	if(.)
		return

	if(!panel_open)
		return

	switch(action)
		if("edit_tag")
			var/datum/embedded_program/airlock/airlock_program = program

			var/tag = params["tag"]
			var/current = airlock_program.get_tag(tag)
			om_ask(usr, /datum/om/prompt/text/airlock_tag, PROC_REF(airlock_tag_entered), message = "What would you like to set [tag] to?", title = "New [tag]?", default = current, max_length = 30, tag_name = tag)
			return TRUE

		if("set_frequency")
			set_frequency(sanitize_frequency(text2num(params["freq"]), RADIO_LOW_FREQ, RADIO_HIGH_FREQ))
			return TRUE

/datum/om/prompt/text/airlock_tag
	requires = PROMPT_USABLE
	var/tag_name

/obj/machinery/embedded_controller/radio/airlock/proc/airlock_tag_entered(datum/om/prompt/text/airlock_tag/ask)
	var/new_tag = ask.text
	var/datum/embedded_program/airlock/airlock_program = program
	if(new_tag && airlock_program)
		airlock_program.set_tag(ask.tag_name, new_tag)
		SStgui.update_uis(src)

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

/obj/machinery/embedded_controller/radio/airlock/advanced_airlock_controller/tgui_data(mob/user)
	var/list/data = ..()

	// Deliberately not using UNTYPED_LIST_ADD, we want this to be appended
	data += list(
		"chamber_pressure" = round(program.memory["chamber_sensor_pressure"]),
		"external_pressure" = round(program.memory["external_sensor_pressure"]),
		"internal_pressure" = round(program.memory["internal_sensor_pressure"]),
		"processing" = program.memory["processing"],
		"purge" = program.memory["purge"],
		"secure" = program.memory["secure"],
		"internalTemplateName" = "AirlockConsoleAdvanced",
	)

	return data

//Airlock controller for airlock control - most airlocks on the station use this
/obj/machinery/embedded_controller/radio/airlock/airlock_controller
	name = "Airlock Controller"
	tag_secure = 1
	valid_actions = list("cycle_ext", "cycle_int", "force_ext", "force_int", "abort")
	deconstructable = TRUE
	circuit = /obj/item/circuitboard/airlock_cycling

/obj/machinery/embedded_controller/radio/airlock/airlock_controller/tgui_data(mob/user)
	var/list/data = ..()

	// Deliberately not using UNTYPED_LIST_ADD, we want this to be appended
	data += list(
		"chamber_pressure" = round(program.memory["chamber_sensor_pressure"]),
		"exterior_status" = program.memory["exterior_status"],
		"interior_status" = program.memory["interior_status"],
		"processing" = program.memory["processing"],
		"internalTemplateName" = "AirlockConsoleSimple",
	)

	return data

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

/obj/machinery/embedded_controller/radio/airlock/access_controller/tgui_data(mob/user)
	var/list/data = ..()

	// Deliberately not using UNTYPED_LIST_ADD, we want this to be appended
	data += list(
		"exterior_status" = program.memory["exterior_status"],
		"interior_status" = program.memory["interior_status"],
		"processing" = program.memory["processing"],
		"internalTemplateName" = "DoorAccessConsole",
	)

	return data
