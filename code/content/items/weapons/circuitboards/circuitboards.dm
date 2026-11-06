MATERIAL_MIX(/obj/item/circuitboard/geiger, list(MAT_STEEL = 50, MAT_GLASS = 50))
/obj/item/circuitboard/geiger
	name = T_BOARD("geiger counter")
	build_path = /obj/item/geiger/wall
	board_type = new /datum/frame/frame_types/geiger

#ifndef T_BOARD
#error T_BOARD macro is not defined but we need it!
#endif

/obj/item/circuitboard/get_examine_desc()
	. = ..()
	if(LAZYLEN(req_components))
		var/list/nice_list = list()
		for(var/B in req_components)
			var/atom/A = B
			if(!ispath(A))
				continue
			nice_list += list("[req_components[A]] [initial(A.name)]")
		. += "Required components: [english_list(nice_list)]."
	if(hidden) // Notify the player that this board cannot be printed easily, so don't lose it!
		. += span_danger("It might be hard to find a replacement for a circuit this unique.")

// specific circuit boards!

// Board for the parts lathe in partslathe.dm
// Board for the algae oxygen generator in algae_generator.dm
// Board for the thermal regulator in airconditioner_vr.dm
// Board for the bomb tester in bomb_tester_vr.dm
// Board for the timeclock terminal in timeclock_vr.dm
// Board for the ID restorer in id_restorer_vr.dm
/obj/item/circuitboard/security/xenobio
	name = T_BOARD("xenobiology camera monitor")
	build_path = /obj/machinery/computer/security/xenobio
	network = list(NETWORK_XENOBIO)
	req_access = list()

/obj/item/circuitboard/machine/rdserver
	name = T_BOARD("R&D Server")
	build_path = /obj/machinery/rnd/server
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
		/obj/item/stack/cable_coil = 2,
		/obj/item/stock_parts/scanning_module = 1,
	)
