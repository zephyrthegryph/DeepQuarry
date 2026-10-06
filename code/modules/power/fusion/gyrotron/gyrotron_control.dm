/obj/machinery/computer/gyrotron_control
	name = "gyrotron control console"
	desc = "Used to control the R-UST stability beams."
	light_color = COLOR_BLUE
	circuit = /obj/item/circuitboard/gyrotron_control

	icon_keyboard = "generic_key"
	icon_screen = "mass_driver"

	var/id_tag
	var/scan_range = 25
	var/datum/tgui_module/gyrotron_control/monitor

// Its window is its monitor's (a hand on a working console opens it); a multitool sets the ident tag the monitor looks for.
CAPABILITIES(/obj/machinery/computer/gyrotron_control)
	op("use", hand(), when(req_empty_hand()), label("Use"), wait(0), needs(req_operable()), then(PROC_REF(open_monitor)))
	op("set_tag", tool(TOOL_MULTITOOL), label("Set ident tag"), wait(0),
		asks(/datum/prompt/text, fields = list("title" = "Gyrotron Control", "question" = "Enter a new ident tag.", "max_len" = MAX_NAME_LEN)),
		then(PROC_REF(tag_entered)))
	owns_one(nameof(monitor), starts = /datum/tgui_module/gyrotron_control)

/obj/machinery/computer/gyrotron_control/Initialize(mapload)
	. = ..()
	monitor.gyro_tag = id_tag
	monitor.scan_range = scan_range


/obj/machinery/computer/gyrotron_control/proc/open_monitor(datum/act/op/A)
	monitor.tgui_interact(A.actor)
	return OP_OK

/obj/machinery/computer/gyrotron_control/proc/tag_entered(datum/act/op/A)
	var/datum/prompt/text/answer = A.answer
	var/new_ident = sanitize_text(answer?.value)
	if(new_ident && A.actor?.Adjacent(src))
		monitor.gyro_tag = new_ident
	return OP_OK

