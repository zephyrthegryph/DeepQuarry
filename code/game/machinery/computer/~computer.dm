//Various overrides to make Eris sprites look nicer
/obj/machinery/computer/power_monitor
	icon_keyboard = "power_key"
	icon_screen = "power_monitor"

DECLARE_APPEARANCE_PROC(/obj/machinery/computer/power_monitor, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/computer/power_monitor/appearance_overlays()
	. = list()
	if(has_stat(BROKEN))
		set_icon_screen("broken")
	else if(alerting)
		set_icon_screen("power_monitor_warn")
	else
		set_icon_screen("power_monitor")
	. += ..()

/obj/machinery/computer/rcon
	icon_keyboard = "power_key"
	icon_screen = "ai-fixer"
