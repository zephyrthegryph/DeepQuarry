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


/obj/machinery/computer/shutoff_monitor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/shutoff_monitor_use,
	)
	..()

/// The old attack_hand: called ..() then always opened the monitor, regardless of the result.
/datum/interaction/machine_hand/shutoff_monitor_use
	id = "shutoff_monitor_use"
	name = "Use"
	effect = /obj/machinery/computer/shutoff_monitor/proc/interaction_use

/obj/machinery/computer/shutoff_monitor/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	monitor.tgui_interact(user)
	return TRUE

/obj/machinery/computer/shutoff_monitor/draw(datum/look/look)
	..()
	if(operable())
		look.overlay("ai-fixer-empty")
