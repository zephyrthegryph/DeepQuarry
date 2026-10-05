/obj/machinery/rnd/production/circuit_imprinter
	name = "circuit imprinter"
	desc = "Manufactures circuit boards for the construction of machines."
	icon_state = "circuit_imprinter"
	production_animation = "circuit_imprinter_ani"
	circuit = /obj/item/circuitboard/circuit_imprinter
	allowed_buildtypes = IMPRINTER

/// A lathe's wiring: the hack and the disable (a pulse lasts five seconds, and the window's designs follow the hack) and four duds; no decoy.
CAPABILITIES(/obj/machinery/rnd/production/circuit_imprinter)
	configure(wires(name = "Circuit Imprinter", count = 6, randomize = FALSE))
	configure(lathe_wires(pulse_lasts = 5 SECONDS, refresh = TRUE))
	without(CAP_SHOCK_WIRE)
	on_change(nameof(hacked), EXIT, then(PROC_REF(lathe_hack_ran_out)))

/obj/machinery/rnd/production/circuit_imprinter/compute_efficiency()
	var/rating = get_part_rating(/obj/item/stock_parts/manipulator)

	return 0.5 ** max(rating - 1, 0) // One sheet, half sheet, quarter sheet, eighth sheet.
