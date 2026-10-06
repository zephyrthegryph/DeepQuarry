/obj/machinery/computer/fusion_fuel_control
	name = "fuel injection control computer"
	desc = "Displays information about the fuel rods."
	circuit = /obj/item/circuitboard/fusion_fuel_control

	icon_keyboard = "tech_key"
	icon_screen = "fuel_screen"

	var/id_tag
	var/scan_range = 25
	var/datum/tgui_module/rustfuel_control/monitor

// Its window is its monitor's (a hand on a working console opens it); a multitool sets the ident tag the monitor looks for.
CAPABILITIES(/obj/machinery/computer/fusion_fuel_control)
	op("use", hand(), when(req_empty_hand()), label("Use"), wait(0), needs(req_operable()), then(PROC_REF(open_monitor)))
	op("set_tag", tool(TOOL_MULTITOOL), label("Set ident tag"), wait(0),
		asks(/datum/prompt/text, fields = list("title" = "Fuel Control", "question" = "Enter a new ident tag.", "max_len" = MAX_NAME_LEN)),
		then(PROC_REF(tag_entered)))
	owns_one(nameof(monitor), starts = /datum/tgui_module/rustfuel_control)

/obj/machinery/computer/fusion_fuel_control/Initialize(mapload)
	. = ..()
	monitor.fuel_tag = id_tag


/obj/machinery/computer/fusion_fuel_control/proc/open_monitor(datum/act/op/A)
	monitor.tgui_interact(A.actor)
	return OP_OK

/obj/machinery/computer/fusion_fuel_control/proc/tag_entered(datum/act/op/A)
	var/datum/prompt/text/answer = A.answer
	var/new_ident = sanitize_text(answer?.value)
	if(new_ident && A.actor?.Adjacent(src))
		monitor.fuel_tag = new_ident
	return OP_OK

