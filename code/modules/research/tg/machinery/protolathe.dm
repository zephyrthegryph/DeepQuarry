/obj/machinery/rnd/production/protolathe
	name = "protolathe"
	desc = "Converts raw materials into useful objects."
	icon_state = "protolathe"
	circuit = /obj/item/circuitboard/machine/protolathe
	production_animation = "protolathe_n"
	allowed_buildtypes = PROTOLATHE

/// A lathe's wiring: the hack and the disable (a pulse lasts five seconds, and the window's designs follow the hack) and four duds; no decoy.
CAPABILITIES(/obj/machinery/rnd/production/protolathe)
	configure(wires(name = "Protolathe", count = 6, randomize = FALSE))
	configure(lathe_wires(pulse_lasts = 5 SECONDS, refresh = TRUE))
	without(CAP_SHOCK_WIRE)
	on_change(nameof(hacked), EXIT, then(PROC_REF(lathe_hack_ran_out)))
