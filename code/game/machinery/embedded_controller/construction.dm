/obj/item/circuitboard/airlock_cycling
	name = T_BOARD("cycling airlock button")
	build_path = /obj/machinery/access_button
	board_type = new /datum/frame/frame_types/button

/obj/item/circuitboard/airlock_cycling/multitool_act(mob/user, obj/item/tool)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(board_type_chosen), message = "What do you want to reconfigure the board to?", title = "Multitool-Circuitboard interface", choices = list("Button", "Sensor", "Controller - Standard", "Controller - Advanced", "Controller - Access"), requires = PROMPT_ADJACENT)
	return ITEM_INTERACT_SUCCESS

/obj/item/circuitboard/airlock_cycling/proc/board_type_chosen(datum/om/prompt/choice/ask)
	var/result = ask.choice
	switch(result)
		if("Button")
			name = T_BOARD("cycling airlock button")
			build_path = /obj/machinery/access_button
		if("Sensor")
			name = T_BOARD("cycling airlock sensor")
			build_path = /obj/machinery/airlock_sensor
		if("Controller - Standard")
			name = T_BOARD("cycling airlock controller (simple)")
			build_path = /obj/machinery/embedded_controller/radio/airlock/airlock_controller
		if("Controller - Advanced")
			name = T_BOARD("cycling airlock controller (advanced)")
			build_path = /obj/machinery/embedded_controller/radio/airlock/advanced_airlock_controller
		if("Controller - Access")
			name = T_BOARD("cycling airlock controller (access)")
			build_path = /obj/machinery/embedded_controller/radio/airlock/access_controller
	return ITEM_INTERACT_SUCCESS
