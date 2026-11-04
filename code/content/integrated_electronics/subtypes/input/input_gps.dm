//This circuit gives information on where the machine is.
/obj/item/integrated_circuit/input/gps
	name = "global positioning system"
	desc = "This allows you to easily know the position of a machine containing this device."
	extended_desc = "The GPS's coordinates it gives is absolute, not relative."
	icon_state = "gps"
	complexity = 4
	inputs = list()
	outputs = list("X"= IC_PINTYPE_NUMBER, "Y" = IC_PINTYPE_NUMBER)
	activators = list("get coordinates" = IC_PINTYPE_PULSE_IN, "on get coordinates" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	power_draw_per_use = 30

/obj/item/integrated_circuit/input/gps/do_work()
	var/turf/T = get_turf(src)

	set_pin_data(IC_OUTPUT, 1, null)
	set_pin_data(IC_OUTPUT, 2, null)
	if(!T)
		push_data()
		return

	set_pin_data(IC_OUTPUT, 1, T.x)
	set_pin_data(IC_OUTPUT, 2, T.y)

	push_data()
	activate_pin(2)
