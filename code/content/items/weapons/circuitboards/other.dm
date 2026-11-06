#ifndef T_BOARD
#error T_BOARD macro is not defined but we need it!
#endif

//Stuff that doesn't fit into any category goes here

/obj/item/circuitboard/machine/ore_silo
	name = T_BOARD("Ore Silo")
	build_path = /obj/machinery/ore_silo
	board_type = new /datum/frame/frame_types/machine
	req_components = list()
