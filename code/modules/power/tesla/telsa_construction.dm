//////////////////////////
// Circuits and Research
//////////////////////////

// Tesla coils are built as machines using a circuit researchable in RnD
/obj/item/circuitboard/tesla_coil
	name = T_BOARD("tesla coil")
	build_path = /obj/machinery/power/tesla_coil
	board_type = new /datum/frame/frame_types/machine
	req_components = list(/obj/item/stock_parts/capacitor = 1)

// Grounding rods can be built as machines using a circuit made in an autolathe.
/obj/item/circuitboard/grounding_rod
	name = T_BOARD("grounding rod")
	build_path = /obj/machinery/power/grounding_rod
	board_type = new /datum/frame/frame_types/machine
	req_components = list()

// SPECIAL BOARDS BELOW

/// A multitool reconfigures the coil board into another kind of coil.
CAPABILITIES(/obj/item/circuitboard/tesla_coil)
	op("reconfigure", tool(TOOL_MULTITOOL), label("Reconfigure"), wait(0),
		asks(/datum/prompt/choice, fields = list("title" = "Multitool-Circuitboard interface", "question" = "What do you want to reconfigure the board to?", "choices" = list("Standard", "Relay", "Prism", "Amplifier", "Recaster", "Collector"))),
		then(PROC_REF(reconfigured)))

/obj/item/circuitboard/tesla_coil/proc/reconfigured(datum/act/op/A)
	var/datum/prompt/R = A.answer
	switch(R?.value)
		if("Standard")
			name = T_BOARD("tesla coil")
			build_path = /obj/machinery/power/tesla_coil
		if("Relay")
			name = T_BOARD("tesla relay coil")
			build_path = /obj/machinery/power/tesla_coil/relay
		if("Prism")
			name = T_BOARD("tesla prism coil")
			build_path = /obj/machinery/power/tesla_coil/splitter
		if("Amplifier")
			name = T_BOARD("tesla amplifier coil")
			build_path = /obj/machinery/power/tesla_coil/amplifier
		if("Recaster")
			name = T_BOARD("tesla recaster coil")
			build_path = /obj/machinery/power/tesla_coil/recaster
		if("Collector")
			name = T_BOARD("tesla collector coil")
			build_path = /obj/machinery/power/tesla_coil/collector
	return OP_OK
