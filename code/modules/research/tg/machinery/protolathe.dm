/obj/machinery/rnd/production/protolathe
	name = "protolathe"
	desc = "Converts raw materials into useful objects."
	icon_state = "protolathe"
	circuit = /obj/item/circuitboard/machine/protolathe
	production_animation = "protolathe_n"
	allowed_buildtypes = PROTOLATHE

TYPE_TABLE(/obj/machinery/rnd/production/protolathe, production_initial_wires, /datum/wires/protolathe)
