/datum/ship_engine/ion
	name = "ion thruster"
	var/tmp/obj/machinery/ion_engine/thruster

/datum/ship_engine/ion/New(obj/machinery/_holder)
	..()
	rel_set(src, nameof(thruster), _holder)

/datum/ship_engine/ion/get_status()
	return thruster().get_status()

/datum/ship_engine/ion/get_thrust()
	return thruster().get_thrust()

/datum/ship_engine/ion/burn()
	return thruster().thrust_burn()

/datum/ship_engine/ion/set_thrust_limit(new_limit)
	thruster().thrust_limit = new_limit

/datum/ship_engine/ion/get_thrust_limit()
	return thruster().thrust_limit

/datum/ship_engine/ion/is_on()
	return thruster().on && thruster().powered()

/datum/ship_engine/ion/toggle()
	thruster().on = !thruster().on

/datum/ship_engine/ion/can_burn()
	return thruster().on && thruster().powered()

/obj/machinery/ion_engine
	name = "ion propulsion device"
	desc = "An advanced ion propulsion device, using energy and minutes amount of gas to generate thrust."
	icon = 'icons/turf/shuttle_parts_vr.dmi' // New icons
	icon_state = "ion" // New icons
	power_channel = ENVIRON
	idle_power_usage = 100
	anchored = TRUE
	var/datum/ship_engine/ion/controller
	var/thrust_limit = 1
	on = 1
	var/burn_cost = 7500
	var/generated_thrust = 2.5

CAPABILITIES(/obj/machinery/ion_engine)
	after_init(0, then(PROC_REF(init_glow)))
	owns_one(nameof(controller), starts = /datum/ship_engine/ion)

/obj/machinery/ion_engine/proc/init_glow(datum/act/timer/A)
	add_glow()



/obj/machinery/ion_engine/proc/add_glow()
	var/image/i = image('icons/turf/shuttle_parts_vr.dmi', "ion_overlay")
	i.plane = PLANE_LIGHTING_ABOVE
	add_overlay(i)

/obj/machinery/ion_engine/proc/get_status()
	. = list()
	.+= "Location: [get_area(src)]."
	if(!powered())
		.+= list(list("Insufficient power to operate.", "bad"))

/obj/machinery/ion_engine/proc/thrust_burn()
	if(!on && !powered())
		return 0
	use_power_oneoff(burn_cost)
	. = thrust_limit * generated_thrust

/obj/machinery/ion_engine/proc/get_thrust()
	return thrust_limit * generated_thrust * on

/obj/item/circuitboard/engine/ion
	name = T_BOARD("ion propulsion device")
	board_type = "machine"
	icon_state = "mcontroller"
	build_path = /obj/machinery/ion_engine
	req_components = list(
							/obj/item/stack/cable_coil = 2,
							/obj/item/stock_parts/matter_bin = 1,
							/obj/item/stock_parts/capacitor = 2)

/// Accessor for the thruster var.
/datum/ship_engine/ion/proc/thruster() as /obj/machinery/ion_engine
	return thruster
