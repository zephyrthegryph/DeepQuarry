/obj/machinery/computer/shutoff_monitor
	name = "automated shutoff valve monitor"
	desc = "Console used to remotely monitor shutoff valves on the station."
	icon_keyboard = "power_key"
	icon_screen = "power_monitor"
	light_color = "#a97faa"
	circuit = /obj/item/circuitboard/shutoff_monitor
	var/datum/tgui_module/shutoff_monitor/monitor

CAPABILITIES(/obj/machinery/computer/shutoff_monitor)
	owns_one(nameof(monitor), /datum/tgui_module/shutoff_monitor, starts = /datum/tgui_module/shutoff_monitor)
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_use)))


/obj/machinery/computer/shutoff_monitor/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	monitor.tgui_interact(user)
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/machinery/computer/shutoff_monitor, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/computer/shutoff_monitor/appearance_overlays()
	. = list()
	. += ..()
	if(operable())
		. += "ai-fixer-empty"
