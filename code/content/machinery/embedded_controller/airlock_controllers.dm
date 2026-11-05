//base type for controllers of two-door systems: the airlock itself (its cycle is in airlock_cycle.dm)
/obj/machinery/embedded_controller/radio/airlock
	radio_filter = RADIO_AIRLOCK
	// The map's device tags: each one is the keyed relation it names (airlock_cycle.dm), defaulted from id_tag at setup.
	var/tag_exterior_door
	var/tag_interior_door
	var/tag_airpump
	var/tag_chamber_sensor
	var/tag_exterior_sensor
	var/tag_interior_sensor
	var/tag_airlock_mech_sensor
	var/tag_shuttle_mech_sensor
	var/tag_secure = 0
	var/cycle_to_external_air = 0
	valid_actions = list("cycle_ext", "cycle_int", "force_ext", "force_int", "abort", "purge", "secure")
	layer = ABOVE_WINDOW_LAYER

	var/deconstructable = FALSE
	/// The docking port that has this airlock docked (from its prepare until the undock finishes), or null.
	var/datum/docking_port/docked_port
	/// This airlock's own override: its port leaves it to the crew when docking (a multi-airlock port's children).
	var/override_enabled = FALSE

/// The tags an airlock console's panel edits: each is a var of the console, and a keyed relation re-links when it changes.
GLOBAL_LIST_INIT(airlock_editable_tags, list("id_tag", "tag_exterior_door", "tag_interior_door", "tag_airpump", "tag_chamber_sensor", "tag_exterior_sensor", "tag_interior_sensor", "tag_airlock_mech_sensor", "tag_shuttle_mech_sensor"))

/obj/machinery/embedded_controller/radio/airlock/proc/editable_tags()
	return GLOB.airlock_editable_tags

/// While docked, the airlock refuses its own cycle and door commands unless an override is on.
/obj/machinery/embedded_controller/radio/airlock/proc/dock_locked()
	return docked_port && !docked_port.override_enabled && !override_enabled

// ---- what its docking port asks of it (direct calls: the airlock steps at once, nothing to wake for) ----

/obj/machinery/embedded_controller/radio/airlock/proc/dock_prepare(datum/docking_port/P)
	rel_set(src, nameof(docked_port), P)
	if(!override_enabled)
		begin_dock_cycle()

/obj/machinery/embedded_controller/radio/airlock/proc/dock_ready()
	return done_cycling()

/obj/machinery/embedded_controller/radio/airlock/proc/dock_finish()
	if(!override_enabled)
		set_mech_regulation(TRUE)
		open_doors()

/obj/machinery/embedded_controller/radio/airlock/proc/undock_prepare()
	if(!override_enabled)
		stop_cycling()
		close_doors()
		set_mech_regulation(FALSE)

/// Ready to leave: either door shut and bolted (read from the doors).
/obj/machinery/embedded_controller/radio/airlock/proc/undock_ready()
	return check_exterior_door_secured() || check_interior_door_secured()

/obj/machinery/embedded_controller/radio/airlock/proc/undock_finish()
	rel_set(src, nameof(docked_port), null)

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
		var/list/tags = list()
		for(var/tag_name in editable_tags())
			tags[tag_name] = vars[tag_name]
		data["tags"] = tags

		data["frequency"] = frequency
		data["min_freq"] = RADIO_LOW_FREQ
		data["max_freq"] = RADIO_HIGH_FREQ

	return data

// The tag and frequency settings are behind the maintenance panel (the console's commands are not: the old tgui_act() ran them before its panel check).
CAPABILITIES(/obj/machinery/embedded_controller/radio/airlock)
	ref_one(nameof(docked_port), /datum/docking_port)
	setup(PROC_REF(default_device_tags))
	ref_many(nameof(exterior_doors), /obj/machinery/door/airlock, by = nameof(tag_exterior_door), target_key = nameof(/obj/machinery/door/airlock::id_tag))
	ref_many(nameof(interior_doors), /obj/machinery/door/airlock, by = nameof(tag_interior_door), target_key = nameof(/obj/machinery/door/airlock::id_tag))
	ref_many(nameof(chamber_pumps), /obj/machinery/atmospherics/unary/vent_pump, by = nameof(tag_airpump), target_key = nameof(/obj/machinery/atmospherics/unary/vent_pump::id_tag))
	ref_many(nameof(chamber_dp_pumps), /obj/machinery/atmospherics/binary/dp_vent_pump, by = nameof(tag_airpump), target_key = nameof(/obj/machinery/atmospherics/binary/dp_vent_pump::id))
	ref_many(nameof(pumps_out_internal), /obj/machinery/atmospherics/unary/vent_pump, by = nameof(tag_pump_out_internal), target_key = nameof(/obj/machinery/atmospherics/unary/vent_pump::id_tag))
	ref_many(nameof(pumps_out_external), /obj/machinery/atmospherics/unary/vent_pump, by = nameof(tag_pump_out_external), target_key = nameof(/obj/machinery/atmospherics/unary/vent_pump::id_tag))
	ref_one(nameof(chamber_sensor), /obj/machinery/airlock_sensor, by = nameof(tag_chamber_sensor), target_key = nameof(/obj/machinery/airlock_sensor::id_tag))
	ref_one(nameof(exterior_sensor), /obj/machinery/airlock_sensor, by = nameof(tag_exterior_sensor), target_key = nameof(/obj/machinery/airlock_sensor::id_tag))
	ref_one(nameof(interior_sensor), /obj/machinery/airlock_sensor, by = nameof(tag_interior_sensor), target_key = nameof(/obj/machinery/airlock_sensor::id_tag))
	ref_many(nameof(airlock_mech_sensors), /obj/machinery/mech_sensor, by = nameof(tag_airlock_mech_sensor), target_key = nameof(/obj/machinery/mech_sensor::id_tag))
	ref_many(nameof(shuttle_mech_sensors), /obj/machinery/mech_sensor, by = nameof(tag_shuttle_mech_sensor), target_key = nameof(/obj/machinery/mech_sensor::id_tag))
	owns_many(nameof(chamber_watches), /datum/native_watch/world)
	configure(machine_rules(maintenance_flags = MACHINE_MAINT_STANDARD))
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
	var/tag_name = A.args["tag"]
	return (tag_name in editable_tags()) ? vars[tag_name] : null

/// The answered tag is set: its keyed relation drops the old devices and links the new ones.
/obj/machinery/embedded_controller/radio/airlock/proc/ui_act_edit_tag(datum/act/op/A, tag)
	var/new_tag = A.step_value("tag")
	if(new_tag && (tag in editable_tags()))
		keyed_set_id(src, tag, new_tag)
	return TRUE

/obj/machinery/embedded_controller/radio/airlock/proc/ui_act_set_frequency(datum/act/op/A, freq)
	set_frequency(sanitize_frequency(freq, RADIO_LOW_FREQ, RADIO_HIGH_FREQ))
	return TRUE

/// An airlock controller also shows its open panel.
/obj/machinery/embedded_controller/radio/airlock/draw(datum/look/look)
	..()
	look.overlay("airlock_control_open", panel_open)

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
	display_base = "access_control"

	name = "Access Controller"
	tag_secure = 1
	valid_actions = list("cycle_ext_door", "cycle_int_door", "force_ext", "force_int")
	deconstructable = TRUE
	circuit = /obj/item/circuitboard/airlock_cycling

/// The access controller's sprite has no open-panel layer.
/obj/machinery/embedded_controller/radio/airlock/access_controller/draw(datum/look/look)
	..()
	look.hide("airlock_control_open")

// Each controller's window picks its console by internalTemplateName (tgui/packages/tgui/interfaces/EmbeddedController/index.tsx throws
// without one) and reads the airlock's state. dq_ops_menu_airlock_controller_window pins them.

/obj/machinery/embedded_controller/radio/airlock/advanced_airlock_controller/ui_data(datum/act/eval/A)
	. = ..()
	.["chamber_pressure"] = round(chamber_pressure())
	.["external_pressure"] = round(external_pressure())
	.["internal_pressure"] = round(internal_pressure())
	.["processing"] = cycling()
	.["purge"] = purge
	.["secure"] = secure
	.["internalTemplateName"] = "AirlockConsoleAdvanced"

/obj/machinery/embedded_controller/radio/airlock/airlock_controller/ui_data(datum/act/eval/A)
	. = ..()
	.["chamber_pressure"] = round(chamber_pressure())
	.["exterior_status"] = exterior_status()
	.["interior_status"] = interior_status()
	.["processing"] = cycling()
	.["internalTemplateName"] = "AirlockConsoleSimple"

/obj/machinery/embedded_controller/radio/airlock/access_controller/ui_data(datum/act/eval/A)
	. = ..()
	.["exterior_status"] = exterior_status()
	.["interior_status"] = interior_status()
	.["processing"] = cycling()
	.["internalTemplateName"] = "DoorAccessConsole"
