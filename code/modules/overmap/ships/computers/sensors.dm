/obj/machinery/computer/ship/sensors
	name = "sensors console"
	icon_keyboard = "teleport_key"
	icon_screen = "teleport"
	light_color = "#77fff8"
	circuit = /obj/item/circuitboard/sensors
	extra_view = 4
	var/tmp/obj/machinery/shipsensors/sensors

// fancy sprite
/obj/machinery/computer/ship/sensors/adv
	icon_keyboard = null
	icon_state = "adv_sensors"
	icon_screen = "adv_sensors_screen"
	light_color = "#05A6A8"

/obj/machinery/computer/ship/sensors/attempt_hook_up(obj/effect/overmap/visitable/ship/sector)
	if(!(. = ..()))
		return
	find_sensors()

/obj/machinery/computer/ship/sensors/proc/find_sensors()
	if(!linked())
		return
	for(var/obj/machinery/shipsensors/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(linked().check_ownership(S))
			rel_set(src, nameof(sensors), S)
			refresh_sensor_light()
			break

/obj/machinery/computer/ship/sensors/proc/refresh_sensor_light()
	if(!linked())
		return
	if(sensors() && sensors().use_power && sensors().powered())
		var/sensor_range = round(sensors().range * 1.5) + 1
		linked().set_light(sensor_range + 0.5)
	else
		linked().set_light(0)

DECLARE_UI(/obj/machinery/computer/ship/sensors, "OvermapShipSensors")

/obj/machinery/computer/ship/sensors/ui_prepare(mob/user, datum/tgui/ui)
	if(!linked())
		display_reconnect_dialog(user, "sensors")
		return FALSE

	return TRUE

/obj/machinery/computer/ship/sensors/ui_title(mob/user)
	return "[linked().name] Sensors Control"

UI_DATA_REPLACE(/obj/machinery/computer/ship/sensors, "merge:ui_data_obj_machinery_computer_ship_sensors{viewing:unknown,on:unknown,range:unknown,health:unknown,max_health:num,heat:num,critical_heat:num,status:text,contacts:list}")

/// The computed part of /obj/machinery/computer/ship/sensors's window data (declared on its UI_DATA row).
/obj/machinery/computer/ship/sensors/proc/ui_data_obj_machinery_computer_ship_sensors(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["viewing"] = viewing_overmap(user)
	data["on"] = 0
	data["range"] = "N/A"
	data["health"] = 0
	data["max_health"] = 0
	data["heat"] = 0
	data["critical_heat"] = 0
	data["status"] = "MISSING"
	data["contacts"] = list()

	if(sensors())
		data["on"] = sensors().use_power
		data["range"] = sensors().range
		data["health"] = sensors().get_integrity()
		data["max_health"] = sensors().max_integrity
		data["heat"] = sensors().heat
		data["critical_heat"] = sensors().critical_heat
		if(sensors().get_integrity() <= 0)
			data["status"] = "DESTROYED"
		else if(!sensors().powered())
			data["status"] = "NO POWER"
		else if(!sensors().in_vacuum())
			data["status"] = "VACUUM SEAL BROKEN"
		else
			data["status"] = "OK"
		var/list/contacts = list()
		for(var/obj/effect/overmap/O in range(7,linked()))
			if(linked() == O)
				continue
			if(!O.scannable)
				continue
			var/bearing = round(90 - ATAN2(O.x - linked().x, O.y - linked().y),5)
			if(bearing < 0)
				bearing += 360
			contacts.Add(list(list("name"=O.name, "ref"="\ref[O]", "bearing"=bearing)))
		data["contacts"] = contacts

	return data

/obj/machinery/computer/ship/sensors/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!linked())
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/computer/ship/sensors, "viewing", ui_act_viewing)
UI_ACT_PROC(/obj/machinery/computer/ship/sensors, ui_act_viewing)
	if(ui.user && !isAI(ui.user))
		if(get_dist(ui.user, src) > 1 || ui.user.blinded || !linked())
			. = FALSE
		else if(!viewing_overmap(ui.user) && linked())
			start_coordinated_remoteview(src, ui.user, linked(), viewers)
		else
			ui.user.reset_perspective()
	. = TRUE
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/sensors, "link", ui_act_link)
UI_ACT_PROC(/obj/machinery/computer/ship/sensors, ui_act_link)
	find_sensors()
	. = TRUE
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/sensors, "scan", ui_act_scan, UI_ARG_REF("scan", null, /obj/effect/overmap))
UI_ACT_PROC(/obj/machinery/computer/ship/sensors, ui_act_scan)
	var/obj/effect/overmap/O = params["scan"]
	if(istype(O) && !QDELETED(O) && (O in view(7,linked())))
		new/obj/item/paper/(get_turf(src), O.get_scan_data(ui.user), "paper (Sensor Scan - [O])")
		playsound(src, "sound/machines/printer.ogg", 30, 1)
	. = TRUE
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/sensors, "range", ui_act_range)
UI_ACT_PROC(/obj/machinery/computer/ship/sensors, ui_act_range)
	if(!(sensors()))
		return FALSE
	if(!istype(ui) || QDELETED(ui) || !ismob(ui.user) || QDELETED(ui.user))
		return
	open_request(ui, /datum/prompt/number/ship_sensor_range, TYPE_PROC_REF(/datum/tgui, ship_sensor_range_answered), answerer = ui.user, default = sensors().range, displayed_max = world.view)

/obj/machinery/computer/ship/sensors/proc/apply_sensor_range_answer(datum/tgui/ui, nrange)
	if(nrange)
		sensors().set_range(CLAMP(nrange, 1, world.view))
	. = TRUE
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

UI_ACT(/obj/machinery/computer/ship/sensors, "toggle_sensor", ui_act_toggle_sensor)
UI_ACT_PROC(/obj/machinery/computer/ship/sensors, ui_act_toggle_sensor)
	if(!(sensors()))
		return FALSE
	sensors().toggle()
	. = TRUE
	if(. && !issilicon(ui.user))
		play_sfx(src, SFX_TERMINAL_TYPE)

/obj/machinery/computer/ship/sensors/machine_step()
	..()
	refresh_sensor_light()
	return PROCESS_KILL

/obj/machinery/shipsensors
	// EMPs burn out the delicate sensor elements (20 integrity from a heavy pulse).
	emp_integrity_factor = 0.2
	name = "sensors suite"
	desc = "Long range gravity scanner with various other sensors, used to detect irregularities in surrounding space. Can only run in vacuum to protect delicate quantum BS elements."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "sensors"
	anchored = TRUE
	max_integrity = 200
	var/critical_heat = 50 // sparks and takes damage when active & above this heat
	var/heat_reduction = 1.5 // mitigates this much heat per tick
	var/heat = 0
	var/range = 1
	idle_power_usage = 5000

// sensor consoles lose it.
/obj/machinery/shipsensors/lifecycle_dematerialize()
	for(var/obj/machinery/computer/ship/sensors/console in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(!(console.sensors == src))
			continue
		rel_clear(console, nameof(console.sensors))
		console.refresh_sensor_light()
	return ..()

/obj/machinery/shipsensors/proc/refresh_linked_consoles()
	for(var/obj/machinery/computer/ship/sensors/console in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(console.sensors() == src)
			console.refresh_sensor_light()

/obj/machinery/shipsensors/welder_act(mob/user, obj/item/tool)
	var/damage = max_integrity - get_integrity()
	if(!damage)
		return ..()
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder?.isOn())
		return ITEM_INTERACT_BLOCKING
	if(!welder.remove_fuel(0, user))
		to_chat(user, span_notice("You need more welding fuel to complete this task."))
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You start repairing the damage to [src]."))
	play_sfx(src, SFX_ITEMS_WELDER)
	om_task_timed(user, max(5, damage / 5), src, src, PROC_REF(weld_repair_done), list(user, welder))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/shipsensors/proc/weld_repair_done(mob/user, obj/item/weldingtool/welder)
	if(!welder.isOn())
		return
	to_chat(user, span_notice("You finish repairing the damage to [src]."))
	repair_damage(max_integrity - get_integrity())

/obj/machinery/shipsensors/proc/in_vacuum()
	var/turf/T=get_turf(src)
	if(istype(T))
		var/datum/gas_mixture/environment = T.return_air()
		if(environment && environment.return_pressure() > MINIMUM_PRESSURE_DIFFERENCE_TO_SUSPEND)
			return 0
	return 1

APPEARANCE_TEMPLATE(/obj/machinery/shipsensors, "{use_power?sensors:sensors_off}")

/obj/machinery/shipsensors/examine(mob/user)
	. = ..()
	if(get_integrity() <= 0)
		. += span_danger("It is wrecked.")
	else if(get_integrity() < max_integrity * 0.25)
		. += span_danger("It looks like it's about to break!")
	else if(get_integrity() < max_integrity * 0.5)
		. += span_danger("It looks seriously damaged!")
	else if(get_integrity() < max_integrity * 0.75)
		. += "It shows signs of damage!"

/obj/machinery/shipsensors/proc/toggle()
	if(!use_power && (get_integrity() <= 0 || !in_vacuum()))
		return // No turning on if broken or misplaced.
	if(!use_power) //need some juice to kickstart
		use_power_oneoff(idle_power_usage*5)
	set_use_power(!use_power)
	refresh_linked_consoles()
	MACHINE_WAKE(src)

/obj/machinery/shipsensors/machine_step()
	if(use_power) //can't run in non-vacuum
		if(!in_vacuum())
			toggle()
		if(heat > critical_heat)
			src.visible_message(span_danger("\The [src] violently spews out sparks!"))
			fx_sparks(src, 3)

			take_damage(rand(10,50), BURN, FIRE)
			toggle()
		heat += idle_power_usage/15000

	if (heat > 0)
		heat = max(0, heat - heat_reduction)
	if(!use_power && heat <= 0)
		return PROCESS_KILL

/obj/machinery/shipsensors/power_change()
	. = ..()
	if(use_power && !powered())
		toggle()

/obj/machinery/shipsensors/proc/set_range(nrange)
	range = nrange
	change_power_consumption(1500 * (range**2), USE_POWER_IDLE) //Exponential increase, also affects speed of overheating
	refresh_linked_consoles()

DAMAGE_REACTION(/obj/machinery/shipsensors, DAMAGE_EMP, PROC_REF(sensors_emp_shutdown))

/// A pulse knocks running sensors offline.
/obj/machinery/shipsensors/proc/sensors_emp_shutdown(datum/damage_packet/packet)
	if(!use_power)
		return
	toggle()

/obj/machinery/shipsensors/atom_destruction(damage_flag)
	. = ..()
	if(use_power)
		toggle()

/obj/machinery/shipsensors/weak
	heat_reduction = 0.2
	desc = "Miniaturized gravity scanner with various other sensors, used to detect irregularities in surrounding space. Can only run in vacuum to protect delicate quantum bluespace elements."

/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/shipsensors/step_start_condition()
	return use_power

/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/computer/ship/sensors/step_start_condition()
	return TRUE // its sensor light

/// Accessor for the sensors var.
/obj/machinery/computer/ship/sensors/proc/sensors() as /obj/machinery/shipsensors
	return sensors

/datum/tgui/proc/ship_sensor_range_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/obj/machinery/computer/ship/sensors/computer = src_object()
	if(computer.apply_sensor_range_answer(src, context.answer.value))
		SStgui.update_uis(computer)

/datum/prompt/number/ship_sensor_range
	question = "Set new sensors range"
	title = "Sensor range"
	timeout = 0
	recheck_on_open = TRUE
	var/displayed_max

/datum/prompt/number/ship_sensor_range/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default || 0, displayed_max, 0, timeout, FALSE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/number/ship_sensor_range/recheck_extra()
	var/datum/tgui/original_ui = owner
	var/mob/user = answerer
	if(!istype(original_ui) || QDELETED(original_ui) || !istype(user) || QDELETED(user))
		return "gone"
	var/obj/machinery/computer/ship/sensors/computer = original_ui.src_object()
	if(!istype(computer) || QDELETED(computer))
		return "gone"
	if(computer.tgui_status(original_ui.user, original_ui.state()) != STATUS_INTERACTIVE)
		return "the sensors console is not interactive"
	if(original_ui.status != STATUS_INTERACTIVE)
		return "the original window is not interactive"
	if(!computer.ui_act_allowed(original_ui.user, "range", original_ui, original_ui.state()))
		return "the sensors console action is unavailable"
	if(!isnull(value) && !computer.sensors())
		return "the sensor is missing"
	return null
