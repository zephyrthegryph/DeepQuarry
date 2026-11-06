#ifndef T_BOARD
#error T_BOARD macro is not defined but we need it!
#endif

/obj/item/circuitboard/machine/protolathe
	name = T_BOARD("protolathe")
	build_path = /obj/machinery/rnd/production/protolathe
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
							/obj/item/stock_parts/matter_bin = 2,
							/obj/item/stock_parts/manipulator = 2,
							/obj/item/reagent_containers/glass/beaker = 2)
	hidden = TRUE // Base types aren't cared for, a fully unlocked lathe shouldn't be easy to make

/obj/item/circuitboard/machine/protolathe/department
	name = T_BOARD("departmental protolathe")
	build_path = /obj/machinery/rnd/production/protolathe/department
/obj/item/circuitboard/machine/protolathe/department/engineering
	name = T_BOARD("departmental protolathe (engineering)")
	build_path = /obj/machinery/rnd/production/protolathe/department/engineering
	hidden = FALSE
/obj/item/circuitboard/machine/protolathe/department/service
	name = T_BOARD("departmental protolathe (service)")
	build_path = /obj/machinery/rnd/production/protolathe/department/service
	hidden = FALSE
/obj/item/circuitboard/machine/protolathe/department/medical
	name = T_BOARD("departmental protolathe (medical)")
	build_path = /obj/machinery/rnd/production/protolathe/department/medical
	hidden = FALSE
/obj/item/circuitboard/machine/protolathe/department/cargo
	name = T_BOARD("departmental protolathe (cargo)")
	build_path = /obj/machinery/rnd/production/protolathe/department/cargo
	hidden = FALSE
/obj/item/circuitboard/machine/protolathe/department/science
	name = T_BOARD("departmental protolathe (science)")
	build_path = /obj/machinery/rnd/production/protolathe/department/science
	hidden = FALSE
/obj/item/circuitboard/machine/protolathe/department/security
	name = T_BOARD("departmental protolathe (security)")
	build_path = /obj/machinery/rnd/production/protolathe/department/security
	hidden = FALSE
