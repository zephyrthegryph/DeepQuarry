//Various overrides to make Eris sprites look nicer
/obj/machinery/computer/power_monitor
	icon_keyboard = "power_key"
	icon_screen = "power_monitor"

// ALLOW(sys_update_icon): picks the screen then runs /obj/machinery/computer's procedural compositing
/obj/machinery/computer/power_monitor/update_icon()
	if(has_stat(BROKEN))
		icon_screen = "broken"
	else if(alerting)
		icon_screen = "power_monitor_warn"
	else
		icon_screen = "power_monitor"
	..()

/obj/machinery/computer/rcon
	icon_keyboard = "power_key"
	icon_screen = "ai-fixer"
