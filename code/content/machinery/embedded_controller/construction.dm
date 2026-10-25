/obj/item/circuitboard/airlock_cycling
	name = T_BOARD("cycling airlock button")
	build_path = /obj/machinery/access_button
	board_type = new /datum/frame/frame_types/button

CAPABILITIES(/obj/item/circuitboard/airlock_cycling)
	op("use_multitool", tool(TOOL_MULTITOOL), wait(0), label("Configure"),
		asks(/datum/prompt/choice, fields = list("title" = "Multitool-Circuitboard interface", "question" = "What do you want to reconfigure the board to?", "choices" = list("Button", "Sensor", "Controller - Standard", "Controller - Advanced", "Controller - Access"), "subject" = computed(PROC_REF(board_subject)), "ask_flags" = ASK_ADJACENT | ASK_CAPABLE, "timeout" = 0), step = "board_type", keeps = ADJACENT | ALIVE),
		then(PROC_REF(board_type_chosen)))

/obj/item/circuitboard/airlock_cycling/proc/board_subject(datum/act/op/A)
	return src

/obj/item/circuitboard/airlock_cycling/proc/board_type_chosen(datum/act/op/A)
	var/result = A.step_value("board_type")
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
	return OP_OK
