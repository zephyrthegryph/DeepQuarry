/obj/machinery/computer/fusion_core_control
	name = "\improper R-UST Mk. 8 core control"
	light_color = COLOR_ORANGE
	circuit = /obj/item/circuitboard/fusion_core_control

	icon_keyboard = "tech_key"
	icon_screen = "core_control"

	var/id_tag = ""
	var/scan_range = 25
	var/tmp/obj/machinery/power/fusion_core/cur_viewed_device
	var/datum/tgui_module/rustcore_monitor/monitor

// Its window is its monitor's (a hand on a working console opens it); a multitool sets the ident tag the monitor looks for.
CAPABILITIES(/obj/machinery/computer/fusion_core_control)
	op("use", hand(), when(req_empty_hand()), label("Use"), wait(0), needs(req_operable()), then(PROC_REF(open_monitor)))
	op("set_tag", tool(TOOL_MULTITOOL), label("Set ident tag"), wait(0),
		asks(/datum/prompt/text, fields = list("title" = "Core Control", "question" = "Enter a new ident tag.", "max_len" = MAX_NAME_LEN)),
		then(PROC_REF(tag_entered)))
	owns_one(nameof(monitor), starts = /datum/tgui_module/rustcore_monitor)
	ref_one(nameof(cur_viewed_device), /obj/machinery/power/fusion_core)

/obj/machinery/computer/fusion_core_control/Initialize(mapload)
	. = ..()
	monitor.core_tag = id_tag


/obj/machinery/computer/fusion_core_control/proc/open_monitor(datum/act/op/A)
	monitor.tgui_interact(A.actor)
	return OP_OK

/obj/machinery/computer/fusion_core_control/proc/tag_entered(datum/act/op/A)
	var/datum/prompt/text/answer = A.answer
	var/new_ident = sanitize_text(answer?.value)
	if(new_ident && A.actor?.Adjacent(src))
		monitor.core_tag = new_ident
	return OP_OK

//Returns 1 if the machine can be interacted with via this console.
/obj/machinery/computer/fusion_core_control/proc/check_core_status(obj/machinery/power/fusion_core/C)
	return istype(C) ? C.check_core_status() : FALSE

/// The core this console is viewing: a relation view, null once that core is deleted.
/obj/machinery/computer/fusion_core_control/proc/cur_viewed_device() as /obj/machinery/power/fusion_core
	return cur_viewed_device

