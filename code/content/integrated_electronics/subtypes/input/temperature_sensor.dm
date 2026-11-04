/obj/item/integrated_circuit/input/temperature_sensor
	name = "integrated temperature sensor"
	desc = "A tiny temperature sensor module similar to that found in a PDA atmosphere analyser."
	icon_state = "medscan_adv"
	complexity = 3
	inputs = list()
	outputs = list(
		"temperature"       = IC_PINTYPE_NUMBER
	)
	activators = list("scan" = IC_PINTYPE_PULSE_IN, "on scanned" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_RESEARCH
	power_draw_per_use = 20

/obj/item/integrated_circuit/input/temperature_sensor/do_work()
	var/turf/T = get_turf(src)
	if(!istype(T)) //Invalid input
		return
	var/datum/gas_mixture/environment = T.return_air()

	var/total_moles = environment.total_moles()

	if (total_moles)
		set_pin_data(IC_OUTPUT, 1, round(environment.return_temperature()-T0C,0.1))
	else
		set_pin_data(IC_OUTPUT, 1, -273.15)
	push_data()
	activate_pin(2)
