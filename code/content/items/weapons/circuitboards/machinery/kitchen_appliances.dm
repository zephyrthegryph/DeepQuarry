/obj/item/circuitboard/microwave
	name = T_BOARD("microwave")
	desc = "The circuitboard for a microwave."
	build_path = /obj/machinery/microwave
	board_type = new /datum/frame/frame_types/microwave
	contain_parts = 0
	req_components = list(
							/obj/item/stock_parts/console_screen = 1,
							/obj/item/stock_parts/capacitor = 1,
							/obj/item/stock_parts/micro_laser = 1,
							/obj/item/stock_parts/scanning_module = 1,
							/obj/item/stock_parts/matter_bin = 2)
