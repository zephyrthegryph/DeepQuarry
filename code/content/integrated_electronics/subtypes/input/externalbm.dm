/obj/item/integrated_circuit/input/externalbm
	name = "external battery monitor"
	desc = "This can help watch the battery level of any device in range."
	icon_state = "externalbm"
	extended_desc = "This circuit will give you values of charge, max charge and percentage of any device or battery in view"
	w_class = ITEMSIZE_TINY
	complexity = 2
	inputs = list("target" = IC_PINTYPE_REF)
	outputs = list(
		"cell charge" = IC_PINTYPE_NUMBER,
		"max charge" = IC_PINTYPE_NUMBER,
		"percentage" = IC_PINTYPE_NUMBER
		)
	activators = list("read" = IC_PINTYPE_PULSE_IN, "on read" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	power_draw_per_use = 1

/obj/item/integrated_circuit/input/externalbm/do_work()

	var/atom/movable/AM = get_pin_data_as_type(IC_INPUT, 1, /atom/movable)
	set_pin_data(IC_OUTPUT, 1, null)
	set_pin_data(IC_OUTPUT, 2, null)
	set_pin_data(IC_OUTPUT, 3, null)
	if(AM)

		var/obj/item/cell/cell = null
		if(istype(AM, /obj/item/cell)) // Is this already a cell?
			cell = AM
		else // If not, maybe there's a cell inside it?
			for(var/obj/item/cell/C in contents_of(AM))
				if(C) // Find one cell to charge.
					cell = C
					break
		if(cell)

			var/turf/A = get_turf(src)
			if(AM in view(A))
				push_data()
				set_pin_data(IC_OUTPUT, 1, cell.charge)
				set_pin_data(IC_OUTPUT, 2, cell.maxcharge)
				set_pin_data(IC_OUTPUT, 3, cell.percent())
	push_data()
	activate_pin(2)
