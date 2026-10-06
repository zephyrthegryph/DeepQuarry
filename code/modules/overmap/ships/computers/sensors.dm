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

// The sensors window: one op per button; the range is asked in the op (asks()), and applied by its handler.
CAPABILITIES(/obj/machinery/computer/ship/sensors)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))
	interface("OvermapShipSensors")
	without("ui_open")
	op("viewing", ui_act("viewing"), then(PROC_REF(ui_act_viewing)))
	op("link", ui_act("link"), then(PROC_REF(ui_act_link)))
	op("scan", ui_act("scan", arg("scan", schema_ref(/obj/effect/overmap))), then(PROC_REF(ui_act_scan)))
	op("range", ui_act("range"),
		asks(/datum/prompt/number/ship_sensor_range, fields = list("default" = computed(PROC_REF(sensor_range_default)), "displayed_max" = computed(PROC_REF(sensor_range_max))), step = "range"),
		then(PROC_REF(ui_act_range)))
	op("toggle_sensor", ui_act("toggle_sensor"), then(PROC_REF(ui_act_toggle_sensor)))

/obj/machinery/computer/ship/sensors/ui_prepare(mob/user, datum/tgui/ui)
	if(!linked())
		display_reconnect_dialog(user, "sensors")
		return FALSE

	return TRUE

/obj/machinery/computer/ship/sensors/ui_title(mob/user)
	return "[linked().name] Sensors Control"

/// The window data.
/obj/machinery/computer/ship/sensors/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
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

/// The console's guard: it works a linked ship.
/obj/machinery/computer/ship/sensors/ui_gate(datum/act/op/A)
	if(!..())
		return FALSE
	return !!linked()

/obj/machinery/computer/ship/sensors/proc/sensor_range_default(datum/act/op/A)
	return sensors()?.range

/obj/machinery/computer/ship/sensors/proc/sensor_range_max(datum/act/op/A)
	return world.view

/obj/machinery/computer/ship/sensors/proc/ui_act_viewing(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!(A.authority & AUTH_REMOTE_ACCESS)) // a silicon views over its link, from anywhere it can work the console
		if(get_dist(user, src) > 1 || user.blinded || !linked())
			. = FALSE
		else if(!viewing_overmap(user) && linked())
			start_coordinated_remoteview(src, user, linked(), viewers)
		else
			user.reset_perspective()
	terminal_typed(user)
	return TRUE

/obj/machinery/computer/ship/sensors/proc/ui_act_link(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	find_sensors()
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/sensors/proc/ui_act_scan(datum/act/op/A, obj/effect/overmap/scan)
	if(!ui_gate(A))
		return FALSE
	if(istype(scan) && !QDELETED(scan) && (scan in view(7,linked())))
		new/obj/item/paper/(get_turf(src), scan.get_scan_data(A.actor), "paper (Sensor Scan - [scan])")
		playsound(src, "sound/machines/printer.ogg", 30, 1)
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/sensors/proc/ui_act_range(datum/act/op/A)
	if(!ui_gate(A) || !sensors())
		return FALSE
	var/nrange = A.step_value("range")
	if(nrange)
		sensors().set_range(CLAMP(nrange, 1, world.view))
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/sensors/proc/ui_act_toggle_sensor(datum/act/op/A)
	if(!ui_gate(A) || !sensors())
		return FALSE
	sensors().toggle()
	terminal_typed(A.actor)
	return TRUE

/obj/machinery/computer/ship/sensors/proc/work_step(datum/act/timer/A)
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

/obj/machinery/shipsensors/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	var/damage = max_integrity - get_integrity()
	if(!damage)
		return OP_DECLINE
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder?.isOn())
		return OP_OK
	if(!welder.remove_fuel(0, user))
		to_chat(user, span_notice("You need more welding fuel to complete this task."))
		return OP_OK
	to_chat(user, span_notice("You start repairing the damage to [src]."))
	play_sfx(src, SFX_ITEMS_WELDER)
	task_timed(user, max(5, damage / 5), src, src, PROC_REF(weld_repair_done), list(user, welder))
	return OP_OK

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

/// The look (the draw sweep: from its template).
/obj/machinery/shipsensors/draw(datum/look/look)
	..()
	look.state("[use_power ? "sensors" : "sensors_off"]")

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
	work_start(src)

// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/shipsensors)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))
	op("use_welder", tool(TOOL_WELDER), priority(OP_PRIORITY_DEFAULT), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))

/obj/machinery/shipsensors/proc/work_step(datum/act/timer/A)
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

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/shipsensors/step_start_condition()
	return use_power

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/computer/ship/sensors/step_start_condition()
	return TRUE // its sensor light

/// Accessor for the sensors var.
/obj/machinery/computer/ship/sensors/proc/sensors() as /obj/machinery/shipsensors
	return sensors

/datum/prompt/number/ship_sensor_range
	question = "Set new sensors range"
	title = "Sensor range"
	timeout = 0
	var/displayed_max

/datum/prompt/number/ship_sensor_range/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default || 0, displayed_max, 0, timeout, FALSE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box
