/*

Note that these have to be in the same /area that the controller is in for them to function.
You still need to set the controller's "id_tag" to something unique.
Any frequency works, it's self-setting, but it seems like people have decided AUTODOCK_FREQ for airlocks so maybe set that on the controller too.

*/

/obj/effect/map_helper/airlock
	name = "use a subtype!"
	icon = 'icons/misc/map_helpers.dmi'
	plane = 20 //I dunno just high.
	alpha = 170

	//The controller we're wanting our device to use
	var/my_controller_type = /obj/machinery/embedded_controller/radio/airlock
	//The device we're setting up
	var/my_device_type
	//Most things have a radio tag of some sort that needs adjusting
	var/tag_addon
	/// Sensors and buttons: the command they send.
	var/command

// Resolved at map time; the setup waits for the load so the device and controller exist.
CAPABILITIES(/obj/effect/map_helper/airlock)
	configure(map_resolver(GLOBAL_PROC_REF(resolve_airlock_helper), vars = list("command", "my_controller_type", "my_device_type", "tag_addon")))

/proc/resolve_airlock_helper(atom/loc, path, list/varedits)
	map_resolve_later(GLOBAL_PROC_REF(airlock_helper_setup), get_turf(loc), path, varedits)
	return TRUE

/// Wires the helper's device on `T` to the nearest controller of its type in the area.
/proc/airlock_helper_setup(turf/T, path, list/varedits)
	var/obj/effect/map_helper/airlock/P = path
	var/name = MAP_VAR(P, varedits, name)
	if(!T)
		return
	var/device = locate_within(T, MAP_VAR(P, varedits, my_device_type))
	var/obj/machinery/embedded_controller/radio/controller = airlock_helper_controller(T, MAP_VAR(P, varedits, my_controller_type))
	if(!device)
		to_chat(world, span_world("[span_red("WARNING:")][span_black("Airlock helper '[name]' couldn't find what it wanted at: X:[T.x] Y:[T.y] Z:[T.z]")]"))
		log_mapping("WARNING: Airlock helper '[name]' couldn't find what it wanted at: X:[T.x] Y:[T.y] Z:[T.z]")
	else if(!controller)
		to_chat(world, span_world("[span_red("WARNING:")][span_black("Airlock helper '[name]' couldn't find a controller at: X:[T.x] Y:[T.y] Z:[T.z]")]"))
		log_mapping("WARNING: Airlock helper '[name]' couldn't find a controller at: X:[T.x] Y:[T.y] Z:[T.z]")
	else if(!controller.id_tag)
		to_chat(world, span_world("[span_red("WARNING:")][span_black("Airlock helper '[name]' found a controller without an 'id_tag' set: X:[T.x] Y:[T.y] Z:[T.z]")]"))
		log_mapping("WARNING: Airlock helper '[name]' found a controller without an 'id_tag' set: X:[T.x] Y:[T.y] Z:[T.z]")
	else
		airlock_helper_configure(device, controller, MAP_VAR(P, varedits, tag_addon), MAP_VAR(P, varedits, command))

/// The controller of `controller_type` in T's area closest to T.
/proc/airlock_helper_controller(turf/T, controller_type)
	var/area/A = get_area(T)
	if(!A)
		return null
	var/closest
	var/closest_dist
	for(var/obj/O in area_contents_of_type(A, /obj))
		if(!istype(O, controller_type))
			continue
		var/dist = get_dist(T, O)
		if(!closest || dist < closest_dist)
			closest = O
			closest_dist = dist
	return closest

/// Applies the controller's tags, frequency and access to the helper's device.
/proc/airlock_helper_configure(device, obj/machinery/embedded_controller/radio/controller, tag_addon, command)
	if(istype(device, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/my_airlock = device
		set_bolted(my_airlock, TRUE)
		keyed_set_id(my_airlock, nameof(my_airlock.id_tag), controller.id_tag + tag_addon) // airlocks are keyed targets by id_tag
		my_airlock.frequency = controller.frequency
		my_airlock.set_frequency(controller.frequency)
		my_airlock.req_access = controller.req_access
		my_airlock.req_one_access = controller.req_one_access
	else if(istype(device, /obj/machinery/atmospherics/unary/vent_pump))
		var/obj/machinery/atmospherics/unary/vent_pump/my_pump = device
		my_pump.set_frequency(controller.frequency) // the setters re-tune it and re-key it in its area
		my_pump.set_id_tag(controller.id_tag + tag_addon)
	else if(istype(device, /obj/machinery/airlock_sensor))
		var/obj/machinery/airlock_sensor/my_sensor = device
		my_sensor.id_tag = controller.id_tag + tag_addon
		my_sensor.master_tag = controller.id_tag
		my_sensor.frequency = controller.frequency
		my_sensor.set_frequency(controller.frequency)
		my_sensor.req_access = controller.req_access
		my_sensor.req_one_access = controller.req_one_access
		if(command)
			my_sensor.command = command
	else if(istype(device, /obj/machinery/access_button))
		var/obj/machinery/access_button/my_button = device
		my_button.master_tag = controller.id_tag
		my_button.frequency = controller.frequency
		my_button.set_frequency(controller.frequency)
		my_button.req_access = controller.req_access
		my_button.req_one_access = controller.req_one_access
		if(command)
			my_button.command = command

/*
	Doors
*/
/obj/effect/map_helper/airlock/door
	name = "use a subtype! - airlock door"
	my_device_type = /obj/machinery/door/airlock

/obj/effect/map_helper/airlock/door/ext_door
	name = "exterior airlock door"
	icon_state = "doorout"
	tag_addon = "_outer"

/obj/effect/map_helper/airlock/door/int_door
	name = "interior airlock door"
	icon_state = "doorin"
	tag_addon = "_inner"

/obj/effect/map_helper/airlock/door/simple
	name = "simple docking controller hatch"
	icon_state = "doorsimple"
	tag_addon = "_hatch"
	my_controller_type = /obj/machinery/embedded_controller/radio/simple_docking_controller

/*
	Atmos
*/
/obj/effect/map_helper/airlock/atmos
	name = "use a subtype! - airlock pump"
	my_device_type = /obj/machinery/atmospherics/unary/vent_pump

/obj/effect/map_helper/airlock/atmos/chamber_pump
	name = "chamber pump"
	icon_state = "pump"
	tag_addon = "_pump"

/obj/effect/map_helper/airlock/atmos/pump_out_internal
	name = "air dump intake"
	icon_state = "pumpdin"
	tag_addon = "_pump_out_internal"

/obj/effect/map_helper/airlock/atmos/pump_out_external
	name = "air dump output"
	icon_state = "pumpdout"
	tag_addon = "_pump_out_external"

/*
	Sensors - did you know they function as buttons? You don't also need a button.
	They don't function identically to buttons. They're also entirely unnecessary for station use because of their complexity.
				They do function well and should be used for shuttle airlocks but unchanging environments don't need sensors.
				A chamber sensor is still necessary.
*/
/obj/effect/map_helper/airlock/sensor
	name = "use a subtype! - airlock sensor"
	my_device_type = /obj/machinery/airlock_sensor

/obj/effect/map_helper/airlock/sensor/ext_sensor
	name = "exterior sensor"
	icon_state = "sensout"
	tag_addon = "_exterior_sensor"
	command = "cycle_exterior"

/obj/effect/map_helper/airlock/sensor/chamber_sensor
	name = "chamber sensor"
	icon_state = "sens"
	tag_addon = "_sensor"
	command = "cycle"

/obj/effect/map_helper/airlock/sensor/int_sensor
	name = "interior sensor"
	icon_state = "sensin"
	tag_addon = "_interior_sensor"
	command = "cycle_interior"

/*
	Buttons
*/

// ition: Button helpers, because they didn't exist before due to 'just use sensors'
/obj/effect/map_helper/airlock/button
	name = "Use a subtype! - button"
	my_device_type = /obj/machinery/access_button

/obj/effect/map_helper/airlock/button/ext_button
	name = "exterior button"
	icon_state = "btnout"
	tag_addon = "_exterior_button"
	command = "cycle_exterior"

/obj/effect/map_helper/airlock/button/int_button
	name = "interior button"
	icon_state = "btnin"
	tag_addon = "_interior_button"
	command = "cycle_interior"
// ition End

