/obj/item/integrated_circuit/input/internalbm
	name = "internal battery monitor"
	desc = "This monitors the charge level of an internal battery."
	icon_state = "internalbm"
	extended_desc = "This circuit will give you values of charge, max charge and percentage of the internal battery on demand."
	w_class = ITEMSIZE_TINY
	complexity = 1
	inputs = list()
	outputs = list(
		"cell charge" = IC_PINTYPE_NUMBER,
		"max charge" = IC_PINTYPE_NUMBER,
		"percentage" = IC_PINTYPE_NUMBER,
		"refference to assembly" = IC_PINTYPE_REF
		)
	activators = list("read" = IC_PINTYPE_PULSE_IN, "on read" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	power_draw_per_use = 1

/obj/item/integrated_circuit/input/internalbm/do_work()
	set_pin_data(IC_OUTPUT, 1, null)
	set_pin_data(IC_OUTPUT, 2, null)
	set_pin_data(IC_OUTPUT, 3, null)
	set_pin_data(IC_OUTPUT, 4, ic_ref(assembly()))
	if(assembly())
		if(assembly().battery)

			set_pin_data(IC_OUTPUT, 1, assembly().battery.charge)
			set_pin_data(IC_OUTPUT, 2, assembly().battery.maxcharge)
			set_pin_data(IC_OUTPUT, 3, 100*assembly().battery.charge/assembly().battery.maxcharge)
	push_data()
	activate_pin(2)
