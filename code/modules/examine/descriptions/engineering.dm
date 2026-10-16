/obj/machinery/power/supermatter

/obj/machinery/power/apc

/obj/machinery/door/get_description_interaction()
	var/list/results = list()
	if((get_integrity() < max_integrity) && !broken_now())
		results += "[desc_panel_image("welder")]to start repairing damage."
	return results

/obj/machinery/door/airlock/get_description_interaction()
	var/list/results = list()

	if(can_remove_electronics())
		results += "[desc_panel_image("crowbar")]to remove the airlock electronics."
	else
		results += "[desc_panel_image("crowbar")]to open or close if unpowered/broken, and unbolted."

	if(is_welded(src))
		results += "[desc_panel_image("welder")]to unweld, allowing it to open again."
	else
		results += "[desc_panel_image("welder")]to weld, preventing it from opening."

	if(panel_is_open(src))
		results += "[desc_panel_image("screwdriver")]to close the wire panel."
		results += "[desc_panel_image("wirecutters")]to cut an internal wire while hacking."
		results += "[desc_panel_image("multitool")]to pulse an internal wire while hacking."
	else
		results += "[desc_panel_image("screwdriver")]to open the wire panel, enabling the ability to hack."

	results += ..()

	return results

/obj/machinery/portable_atmospherics/canister/get_description_interaction()
	var/list/results = list()

	results += "[desc_panel_image("wrench")]to connect or disconnect from a connector port below."
	results += "[desc_panel_image("air tank")]to fill the air tank from this canister."

	return results
