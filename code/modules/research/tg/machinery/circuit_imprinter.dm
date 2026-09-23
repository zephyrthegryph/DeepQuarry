/obj/machinery/rnd/production/circuit_imprinter
	name = "circuit imprinter"
	desc = "Manufactures circuit boards for the construction of machines."
	icon_state = "circuit_imprinter"
	production_animation = "circuit_imprinter_ani"
	circuit = /obj/item/circuitboard/circuit_imprinter
	allowed_buildtypes = IMPRINTER

/obj/machinery/rnd/production/circuit_imprinter/Initialize(mapload)
	. = ..()
	set_wires(new /datum/wires/circuit_imprinter(src))

/obj/machinery/rnd/production/circuit_imprinter/compute_efficiency()
	var/rating = get_part_rating(/obj/item/stock_parts/manipulator)

	return 0.5 ** max(rating - 1, 0) // One sheet, half sheet, quarter sheet, eighth sheet.
