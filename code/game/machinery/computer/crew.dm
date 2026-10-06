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

CAPABILITIES(/obj/machinery/computer/crew)
	owns_one(nameof(crew_monitor), /datum/tgui_module/crew_monitor, starts = /datum/tgui_module/crew_monitor)
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_use)))


/obj/machinery/computer/crew/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!operable())
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/computer/crew/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/machinery/computer/crew/ui_redirect(mob/user)
	return crew_monitor

/obj/machinery/computer/crew/interact(mob/user)
	crew_monitor.tgui_interact(user)
