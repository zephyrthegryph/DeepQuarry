#ifndef T_BOARD
#error T_BOARD macro is not defined but we need it!
#endif

//Circuitboards for frames (mostly wall based frames).  Most of these don't fit into other categories.

//Display

//Alarm

/obj/item/circuitboard/geiger
	name = T_BOARD("geiger counter")
	build_path = /obj/item/geiger/wall
	board_type = new /datum/frame/frame_types/geiger

//Computer

//Machine

/obj/item/circuitboard/recharger
	name = T_BOARD("recharger")
	build_path = /obj/machinery/recharger
	board_type = new /datum/frame/frame_types/recharger
	req_components = list(
							/obj/item/stock_parts/capacitor = 1,
							/obj/item/stack/cable_coil = 5)

/obj/item/circuitboard/recharger/wrecharger
	name = T_BOARD("wall recharger")
	build_path = /obj/machinery/recharger/wallcharger
	board_type = new /datum/frame/frame_types/wall_charger

MATERIAL_MIX(/obj/item/circuitboard/teleporter_hub, list(MAT_STEEL = 50, MAT_GLASS = 50, MAT_GOLD = 100))
/obj/item/circuitboard/teleporter_hub
	name = T_BOARD("teleporter hub")
	build_path = /obj/machinery/teleport/hub
	board_type = new /datum/frame/frame_types/machine // makes buildable
// Balance
	req_components = list(
							/obj/item/bluespace_crystal = 2,
							/obj/item/stock_parts/capacitor = 2,
							/obj/item/stock_parts/scanning_module = 2,
							/obj/item/stock_parts/micro_laser =2,
							/obj/item/stack/cable_coil = 5)
// End

MATERIAL_MIX(/obj/item/circuitboard/teleporter_station, list(MAT_STEEL = 50, MAT_GLASS = 50, MAT_GOLD = 100))
/obj/item/circuitboard/teleporter_station
	name = T_BOARD("teleporter station")
	build_path = /obj/machinery/teleport/station
	board_type = new /datum/frame/frame_types/machine // makes buildable
	req_components = list(
							/obj/item/stock_parts/console_screen = 1,
							/obj/item/stock_parts/capacitor = 2,
							/obj/item/stack/cable_coil = 10)

// Refinery machines
MATERIAL_MIX(/obj/item/circuitboard/microwave/advanced, list(MAT_STEEL = 50, MAT_GLASS = 50))
/obj/item/circuitboard/microwave/advanced
	name = T_BOARD("deluxe microwave")
	build_path = /obj/machinery/microwave/advanced
	board_type = new /datum/frame/frame_types/microwave
	req_components = list(
							/obj/item/stock_parts/console_screen = 1,
							/obj/item/stock_parts/motor = 1,
							/obj/item/stock_parts/capacitor = 1)
