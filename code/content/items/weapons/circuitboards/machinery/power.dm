#ifndef T_BOARD
#error T_BOARD macro is not defined but we need it!
#endif

/obj/item/circuitboard/smes
	name = T_BOARD("superconductive magnetic energy storage")
	build_path = /obj/machinery/power/smes/buildable
	board_type = new /datum/frame/frame_types/machine
	req_components = list(/obj/item/smes_coil = 1, /obj/item/stack/cable_coil = 30)

/obj/item/circuitboard/smes/construct(obj/machinery/power/smes/buildable/S)
	if(..(S))
		S.set_output_attempt(0) //built SMES default to off
