/obj/machinery/computer/crew
	name = "crew monitoring computer"
	desc = "Used to monitor active health sensors built into most of the crew's uniforms."
	icon_keyboard = "med_key"
	icon_screen = "crew"
	light_color = "#315ab4"
	use_power = USE_POWER_IDLE
	idle_power_usage = 250
	active_power_usage = 500
	circuit = /obj/item/circuitboard/crew
	var/datum/tgui_module/crew_monitor/crew_monitor

/obj/machinery/computer/crew/Initialize(mapload)
	. = ..()
	crew_monitor = new(src)

/obj/machinery/computer/crew/Destroy()
	qdel(crew_monitor)
	crew_monitor = null
	. = ..()

/obj/machinery/computer/crew/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/crew_monitor_use,
	)
	..()

/// Old attack_hand: `add_fingerprint(user); if(stat & (BROKEN|NOPOWER)) return; tgui_interact(user)`.
/datum/interaction/machine_hand/ungated/crew_monitor_use
	id = "crew_monitor_use"
	name = "Use"
	effect = /obj/machinery/computer/crew/proc/interaction_use

/obj/machinery/computer/crew/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(stat & (BROKEN|NOPOWER))
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/computer/crew/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/machinery/computer/crew/tgui_interact(mob/user, datum/tgui/ui = null)
	crew_monitor.tgui_interact(user, ui)

/obj/machinery/computer/crew/interact(mob/user)
	crew_monitor.tgui_interact(user)
